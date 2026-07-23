<#
.SYNOPSIS
  Validate one or all server manifests against schemas/manifest.schema.json and
  enforce registry-specific rules that JSON Schema alone can't express.

.DESCRIPTION
  Schema validation uses the built-in Test-Json cmdlet (PowerShell 7.4+), which
  implements JSON Schema draft-07 via the bundled JsonSchema.Net library.
  Additional cross-file checks:
    - folder name must equal manifest.id
    - icon file referenced by manifest.icon must exist in the folder

  Used by the PR validation workflow and runnable locally.

.NOTES
  Requires PowerShell 7.4+. No external dependencies. Cross-platform.
#>
[CmdletBinding()]
param(
    # Validate a single server id; omit to validate all.
    [string] $ServerId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ensure PowerShell version supports Test-Json with JsonSchema.Net (draft-07).
if ($PSVersionTable.PSVersion -lt [version]'7.4.0') {
    throw "PowerShell 7.4+ is required for draft-07 JSON Schema validation. Current: $($PSVersionTable.PSVersion)"
}

Import-Module (Join-Path $PSScriptRoot 'lib' 'manifest.psm1') -Force

# Strip if/then/else from a (sub)schema and fold the given property names into its
# 'required' list. Turns a value-dependent conditional (e.g. transport==stdio then
# require command, else require targetPort) into a flat 'required' set for the one
# manifest being validated, so Test-Json never evaluates - or reports noise from -
# the branch that does not apply.
function Merge-FlattenedRequired {
    param(
        [Parameter(Mandatory)] $Schema,
        [string[]] $Extra = @()
    )
    foreach ($k in 'if', 'then', 'else') {
        if ($Schema.PSObject.Properties.Name -contains $k) {
            $Schema.PSObject.Properties.Remove($k)
        }
    }
    $required = [System.Collections.Generic.List[string]]::new()
    if ($Schema.PSObject.Properties.Name -contains 'required') {
        foreach ($r in $Schema.required) { $required.Add([string]$r) }
    }
    foreach ($e in $Extra) {
        if ($e -and -not $required.Contains($e)) { $required.Add($e) }
    }
    if ($required.Count -gt 0) {
        if ($Schema.PSObject.Properties.Name -contains 'required') {
            $Schema.required = [string[]]$required.ToArray()
        } else {
            $Schema | Add-Member -NotePropertyName 'required' -NotePropertyValue ([string[]]$required.ToArray())
        }
    }
    return $Schema
}

# Resolve the 'configuration' array to a positional tuple of concrete per-item
# schemas. Each configuration input is discriminated by 'type': a 'file' input is
# delivered as a mounted file (and requires targetDirectory + fileName), every
# other type is delivered as an environment variable (whose 'name' must be a valid
# UPPER_SNAKE_CASE variable), and an 'enum' input requires allowedValues. Baking
# each item's requirements in up front - instead of leaving the value-dependent
# if/then/else in items - means Test-Json evaluates one concrete shape per item and
# reports only actionable errors, with no non-matching 'type' branch noise. This
# mirrors the source discriminator resolution above.
function Resolve-ConfigurationSchema {
    param(
        [Parameter(Mandatory)] $Schema,
        [Parameter(Mandatory)] $Manifest
    )
    $hasConfig = ($Manifest.PSObject.Properties.Name -contains 'configuration') -and $Manifest.configuration
    if (-not $hasConfig) { return $Schema }

    $configProp = $Schema.properties.configuration
    $baseItem = $configProp.items

    $tuple = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @($Manifest.configuration)) {
        # Deep-copy the base item schema, then strip the conditionals and fold this
        # item's concrete requirements into a flat shape.
        $resolved = $baseItem | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
        if ($resolved.PSObject.Properties.Name -contains 'allOf') {
            $resolved.PSObject.Properties.Remove('allOf')
        }

        $type = 'string'
        if (($item.PSObject.Properties.Name -contains 'type') -and $item.type) {
            $type = [string]$item.type
        }

        $required = [System.Collections.Generic.List[string]]::new()
        foreach ($r in $resolved.required) { $required.Add([string]$r) }

        if ($type -eq 'file') {
            foreach ($r in 'targetDirectory', 'fileName') {
                if (-not $required.Contains($r)) { $required.Add($r) }
            }
            $namePattern = '^[a-zA-Z][a-zA-Z0-9_-]*$'
        } else {
            $namePattern = '^[A-Z_][A-Z0-9_]*$'
        }
        if (($type -eq 'enum') -and -not $required.Contains('allowedValues')) {
            $required.Add('allowedValues')
        }

        $resolved.required = [string[]]$required.ToArray()
        $resolved.properties.name | Add-Member -NotePropertyName 'pattern' -NotePropertyValue $namePattern -Force

        $tuple.Add($resolved)
    }

    $configProp.items = [object[]]$tuple.ToArray()
    $configProp | Add-Member -NotePropertyName 'additionalItems' -NotePropertyValue $false -Force
    return $Schema
}
# conditionals resolved for THIS manifest: the source discriminator is replaced by
# the single matching definition (containerSource | githubSource), and the
# value-dependent requirements (transport -> command|targetPort, auth methods ->
# connectionStringVariable) are flattened into plain 'required' lists. The result
# has no if/then/else/oneOf/allOf, so Test-Json reports only real errors - there is
# no non-matching-branch assertion noise to string-match away.
function Resolve-EffectiveSchema {
    param(
        [Parameter(Mandatory)] [string] $SchemaPath,
        [Parameter(Mandatory)] $Manifest,
        [Parameter(Mandatory)] [ValidateSet('containerSource', 'githubSource', 'localSource')] [string] $DefName
    )
    $schema = Get-Content -Raw $SchemaPath | ConvertFrom-Json -Depth 100

    # source: swap the discriminator for the concrete, flattened definition.
    $transport = 'http'
    if (($Manifest.source.PSObject.Properties.Name -contains 'transport') -and $Manifest.source.transport) {
        $transport = [string]$Manifest.source.transport
    }
    $transportExtra = if ($transport -eq 'stdio') { @('command') } else { @('targetPort') }
    $schema.properties.source = Merge-FlattenedRequired -Schema $schema.definitions.$DefName -Extra $transportExtra

    # authentication (optional): flatten the connection-string requirement.
    if (($Manifest.PSObject.Properties.Name -contains 'authentication') -and $Manifest.authentication) {
        $methods = @()
        if (($Manifest.authentication.PSObject.Properties.Name -contains 'methods') -and $Manifest.authentication.methods) {
            $methods = @($Manifest.authentication.methods)
        }
        $authExtra = if ($methods -contains 'connection-string') { @('connectionStringVariable') } else { @() }
        $schema.properties.authentication = Merge-FlattenedRequired -Schema $schema.properties.authentication -Extra $authExtra
    }

    # configuration (optional): resolve the type-discriminated inputs to a concrete
    # per-item tuple (env var vs file, enum requires allowedValues).
    $schema = Resolve-ConfigurationSchema -Schema $schema -Manifest $Manifest

    return $schema
}

$repoRoot = Get-RepoRoot
$schemaPath = Join-Path $repoRoot 'schemas' 'manifest.schema.json'

[array] $ids = @(
    if ($ServerId) { $ServerId } else { Get-AllServerIds -RepoRoot $repoRoot }
)
if ($ids.Count -eq 0) {
    Write-Host "No servers to validate." -ForegroundColor Yellow
    return
}

$failures = [System.Collections.Generic.List[string]]::new()

foreach ($id in $ids) {
    Write-Host "--- Validating $id ---" -ForegroundColor Cyan
    $serverDir = Join-Path $repoRoot 'servers' $id
    $manifestPath = Join-Path $serverDir 'manifest.json'

    if (-not (Test-Path $manifestPath)) {
        $failures.Add("${id}: manifest.json not found")
        continue
    }

    $json = Get-Content -Raw $manifestPath

    # 1. JSON Schema validation (draft-07 via built-in Test-Json).
    #    Test-Json surfaces every failed assertion in the schema, including the
    #    'if' clauses of if/then/else and the non-matching arms of a oneOf/allOf
    #    discriminator (e.g. "Expected 'github' at '/source/type'" for a container
    #    manifest). Those are not real errors, and string-matching them out of the
    #    message list is brittle. Instead we discriminate up front on source.type
    #    and validate against an instance-resolved schema flattened to a single
    #    concrete shape, so every reported error is genuinely actionable.
    $manifest = $null
    try {
        $manifest = $json | ConvertFrom-Json -Depth 100 -ErrorAction Stop
    } catch {
        $failures.Add("${id}: manifest.json is not valid JSON - $($_.Exception.Message)")
        continue
    }

    $hasSource = ($manifest.PSObject.Properties.Name -contains 'source') -and $manifest.source
    $sourceType = if ($hasSource -and ($manifest.source.PSObject.Properties.Name -contains 'type')) {
        [string]$manifest.source.type
    } else { $null }
    $defName = switch ($sourceType) { 'container' { 'containerSource' } 'github' { 'githubSource' } 'local' { 'localSource' } default { $null } }

    # A present-but-undiscriminatable source is reported directly (one clean
    # message) rather than letting the branch assertions cascade into noise.
    if ($hasSource -and -not $defName) {
        if (-not $sourceType) {
            $failures.Add("${id}: source.type is required (expected 'container', 'github', or 'local')")
        } else {
            $failures.Add("${id}: source.type '$sourceType' is not supported (expected 'container', 'github', or 'local')")
        }
        continue
    }

    if ($defName) {
        $effectiveSchema = Resolve-EffectiveSchema -SchemaPath $schemaPath -Manifest $manifest -DefName $defName
        $tmpSchema = (New-TemporaryFile).FullName
        try {
            $effectiveSchema | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $tmpSchema -Encoding utf8
            $valid = $json | Test-Json -SchemaFile $tmpSchema -ErrorVariable schemaErrors -ErrorAction SilentlyContinue
        } finally {
            Remove-Item -LiteralPath $tmpSchema -Force -ErrorAction SilentlyContinue
        }
    } else {
        # No source at all: validate against the base schema so the top-level
        # "required: source" error surfaces cleanly (there is no branch to cascade).
        $valid = $json | Test-Json -SchemaFile $schemaPath -ErrorVariable schemaErrors -ErrorAction SilentlyContinue
    }

    if (-not $valid) {
        $messages = $schemaErrors | ForEach-Object {
            $_.Exception.Message -replace '^The JSON is not valid with the schema:\s*', ''
        } | Select-Object -Unique

        foreach ($msg in $messages) {
            $failures.Add("${id}: $msg")
        }
        continue
    }

    # 2. Folder name == id.
    if ($manifest.id -ne $id) {
        $failures.Add("${id}: manifest.id '$($manifest.id)' does not match folder name '$id'")
    }

    # 3. Icon checks (when declared).
    if (($manifest.PSObject.Properties.Name -contains 'icon') -and $manifest.icon) {
        $iconPath = Join-Path $serverDir $manifest.icon
        if (-not (Test-Path $iconPath)) {
            $failures.Add("${id}: icon '$($manifest.icon)' not found in servers/$id/")
        } else {
            $iconSize = (Get-Item $iconPath).Length
            if ($iconSize -gt 512000) {
                $failures.Add("${id}: icon '$($manifest.icon)' is $([math]::Round($iconSize / 1024))KB (max 500KB)")
            }
            if ($manifest.icon -match '\.svg$') {
                $svgContent = Get-Content -Raw $iconPath
                # Whitespace-tolerant with a word boundary so obfuscations like
                # "< script>" or "<\nscript>" are caught, while benign words such
                # as "<scripture>" are not flagged.
                if ($svgContent -match '<\s*script\b|on\w+\s*=|javascript\s*:') {
                    $failures.Add("${id}: icon '$($manifest.icon)' contains dangerous content (scripts, event handlers, or javascript: URIs are not allowed)")
                }
            }
        }
    }

    if (-not ($failures | Where-Object { $_ -like "${id}:*" })) {
        Write-Host "  OK" -ForegroundColor Green
    }
}

if ($failures.Count -gt 0) {
    Write-Host "`nValidation FAILED:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

Write-Host "`nAll manifests valid." -ForegroundColor Green
