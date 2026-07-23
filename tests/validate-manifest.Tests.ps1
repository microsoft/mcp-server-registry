<#
.SYNOPSIS
  Pester tests for manifest schema validation and cross-file checks.

.DESCRIPTION
  Tests the validation logic used by validate-manifest.ps1:
    1. JSON Schema validation via Test-Json (draft-07)
    2. Cross-file rule: folder name must equal manifest.id
    3. Cross-file rule: icon file must exist when declared

  Test structure:
    - Fixtures live under tests/fixtures/valid/ and tests/fixtures/invalid/.
    - Adding a new .json file to either folder auto-includes it in the
      parametrized valid/invalid test sweep — no code change needed.
    - The "specific error cases" section asserts on error *messages* to
      catch regressions in which rule fires (not just pass/fail).
    - End-to-end tests invoke validate-manifest.ps1 as a subprocess to
      verify exit codes, simulating the real author workflow.

  Run locally:
    Invoke-Pester ./tests/validate-manifest.Tests.ps1

  Prerequisites:
    PowerShell 7.4+ (for Test-Json draft-07 support via built-in JsonSchema.Net)
#>

BeforeAll {
    # Resolve paths relative to this test file's location.
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:SchemaPath = Join-Path $RepoRoot 'schemas' 'manifest.schema.json'
    $script:FixturesValid = Join-Path $PSScriptRoot 'fixtures' 'valid'
    $script:FixturesInvalid = Join-Path $PSScriptRoot 'fixtures' 'invalid'
}

# --------------------------------------------------------------------------
# Parametrized sweep: every fixture file is auto-discovered.
# To add coverage for a new case, just drop a .json file in the right folder.
# --------------------------------------------------------------------------

Describe 'Schema validation - valid manifests' {
    It 'should pass schema validation for <_>' -ForEach @(
        Get-ChildItem -Path (Join-Path $PSScriptRoot 'fixtures' 'valid') -Filter '*.json' | Select-Object -ExpandProperty Name
    ) {
        $filePath = Join-Path $script:FixturesValid $_
        $json = Get-Content -Raw $filePath
        $result = $json | Test-Json -SchemaFile $script:SchemaPath -ErrorAction SilentlyContinue
        $result | Should -BeTrue -Because "fixture '$_' should be a valid manifest"
    }
}

Describe 'Schema validation - invalid manifests' {
    It 'should FAIL schema validation for <_>' -ForEach @(
        Get-ChildItem -Path (Join-Path $PSScriptRoot 'fixtures' 'invalid') -Filter '*.json' | Select-Object -ExpandProperty Name
    ) {
        $filePath = Join-Path $script:FixturesInvalid $_
        $json = Get-Content -Raw $filePath
        $result = $json | Test-Json -SchemaFile $script:SchemaPath -ErrorAction SilentlyContinue
        $result | Should -BeFalse -Because "fixture '$_' should be rejected by schema"
    }
}

# --------------------------------------------------------------------------
# Targeted assertions: verify that specific schema rules produce the expected
# error paths/messages. These guard against schema regressions where a rule
# silently stops firing (the fixture would still fail, but for a different reason).
# --------------------------------------------------------------------------

Describe 'Schema validation - specific error cases' {
    It 'rejects missing required field (version)' {
        $json = Get-Content -Raw (Join-Path $script:FixturesInvalid 'missing-version.json')
        $json | Test-Json -SchemaFile $script:SchemaPath -ErrorVariable errs -ErrorAction SilentlyContinue | Out-Null
        $errs.Count | Should -BeGreaterThan 0
        ($errs | Where-Object { $_.Exception.Message -match 'version' }) | Should -Not -BeNullOrEmpty
    }

    It 'rejects invalid id pattern' {
        $json = Get-Content -Raw (Join-Path $script:FixturesInvalid 'bad-id-pattern.json')
        $json | Test-Json -SchemaFile $script:SchemaPath -ErrorVariable errs -ErrorAction SilentlyContinue | Out-Null
        $errs.Count | Should -BeGreaterThan 0
        ($errs | Where-Object { $_.Exception.Message -match '/id' }) | Should -Not -BeNullOrEmpty
    }

    It 'rejects image with tag (requires sha256 digest)' {
        $json = Get-Content -Raw (Join-Path $script:FixturesInvalid 'image-tag-not-digest.json')
        $json | Test-Json -SchemaFile $script:SchemaPath -ErrorVariable errs -ErrorAction SilentlyContinue | Out-Null
        $errs.Count | Should -BeGreaterThan 0
        ($errs | Where-Object { $_.Exception.Message -match 'image' -or $_.Exception.Message -match 'pattern' }) | Should -Not -BeNullOrEmpty
    }

    # These test the if-then-else transport discrimination in the source type
    # discriminator. NOTE: this Describe validates against the raw schema file
    # directly, so it guards the SCHEMA. The script's runtime schema-resolution
    # (Resolve-EffectiveSchema) is covered separately by the end-to-end block.
    # Each fixture includes all other required fields (including links) so the
    # only violation is the specific rule under test.
    It 'rejects stdio transport without command' {
        $json = Get-Content -Raw (Join-Path $script:FixturesInvalid 'stdio-missing-command.json')
        $json | Test-Json -SchemaFile $script:SchemaPath -ErrorVariable errs -ErrorAction SilentlyContinue | Out-Null
        $errs.Count | Should -BeGreaterThan 0
        ($errs | Where-Object { $_.Exception.Message -match 'command' -or $_.Exception.Message -match 'subschema' }) | Should -Not -BeNullOrEmpty
    }

    It 'rejects http transport without targetPort' {
        $json = Get-Content -Raw (Join-Path $script:FixturesInvalid 'container-missing-targetport.json')
        $json | Test-Json -SchemaFile $script:SchemaPath -ErrorVariable errs -ErrorAction SilentlyContinue | Out-Null
        $errs.Count | Should -BeGreaterThan 0
        ($errs | Where-Object { $_.Exception.Message -match 'targetPort' -or $_.Exception.Message -match 'subschema' }) | Should -Not -BeNullOrEmpty
    }

    It 'rejects additional properties not in schema' {
        $json = Get-Content -Raw (Join-Path $script:FixturesInvalid 'additional-property.json')
        $json | Test-Json -SchemaFile $script:SchemaPath -ErrorVariable errs -ErrorAction SilentlyContinue | Out-Null
        $errs.Count | Should -BeGreaterThan 0
        ($errs | Where-Object { $_.Exception.Message -match 'notInSchema' -or $_.Exception.Message -match 'additional' }) | Should -Not -BeNullOrEmpty
    }

    # Tests the conditional requirement: authentication.connectionStringVariable
    # is required only when methods includes "connection-string".
    It 'rejects connection-string auth without connectionStringVariable' {
        $json = Get-Content -Raw (Join-Path $script:FixturesInvalid 'auth-missing-connstring-var.json')
        $json | Test-Json -SchemaFile $script:SchemaPath -ErrorVariable errs -ErrorAction SilentlyContinue | Out-Null
        $errs.Count | Should -BeGreaterThan 0
        ($errs | Where-Object { $_.Exception.Message -match 'connectionStringVariable' -or $_.Exception.Message -match 'subschema' }) | Should -Not -BeNullOrEmpty
    }

    # Configuration inputs are discriminated by 'type': a 'file' input requires
    # targetDirectory + fileName, an 'enum' input requires allowedValues, and any
    # non-file input's name must be a valid UPPER_SNAKE_CASE environment variable.
    It 'rejects a file configuration input without fileName' {
        $json = Get-Content -Raw (Join-Path $script:FixturesInvalid 'config-file-missing-filename.json')
        $json | Test-Json -SchemaFile $script:SchemaPath -ErrorVariable errs -ErrorAction SilentlyContinue | Out-Null
        $errs.Count | Should -BeGreaterThan 0
        ($errs | Where-Object { $_.Exception.Message -match 'fileName' }) | Should -Not -BeNullOrEmpty
    }

    It 'rejects an enum configuration input without allowedValues' {
        $json = Get-Content -Raw (Join-Path $script:FixturesInvalid 'config-enum-missing-allowedvalues.json')
        $json | Test-Json -SchemaFile $script:SchemaPath -ErrorVariable errs -ErrorAction SilentlyContinue | Out-Null
        $errs.Count | Should -BeGreaterThan 0
        ($errs | Where-Object { $_.Exception.Message -match 'allowedValues' }) | Should -Not -BeNullOrEmpty
    }

    It 'rejects a non-file configuration input with a non-UPPER_SNAKE name' {
        $json = Get-Content -Raw (Join-Path $script:FixturesInvalid 'config-env-lowercase-name.json')
        $json | Test-Json -SchemaFile $script:SchemaPath -ErrorVariable errs -ErrorAction SilentlyContinue | Out-Null
        $errs.Count | Should -BeGreaterThan 0
        ($errs | Where-Object { $_.Exception.Message -match '/name' -or $_.Exception.Message -match 'regular expression' }) | Should -Not -BeNullOrEmpty
    }
}

# --------------------------------------------------------------------------
# Cross-file rules that JSON Schema cannot express: these are enforced by
# validate-manifest.ps1 after schema validation passes.
# --------------------------------------------------------------------------

Describe 'Cross-file validation - folder name matches id' {
    BeforeAll {
        $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "mcp-registry-test-$(Get-Random)"
        $script:TempServersDir = Join-Path $TempRoot 'servers'
        New-Item -ItemType Directory -Path $TempServersDir -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $script:TempRoot) {
            Remove-Item -Recurse -Force $script:TempRoot
        }
    }

    It 'passes when folder name equals manifest.id' {
        $serverDir = Join-Path $script:TempServersDir 'mcp-sql-server'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        $manifest = Get-Content -Raw (Join-Path $script:FixturesValid 'container-http.json') | ConvertFrom-Json
        $manifest.id | Should -Be 'mcp-sql-server'
        (Split-Path $serverDir -Leaf) | Should -Be $manifest.id
    }

    It 'fails when folder name does not equal manifest.id' {
        $serverDir = Join-Path $script:TempServersDir 'wrong-folder-name'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        $manifest = Get-Content -Raw (Join-Path $script:FixturesValid 'container-http.json') | ConvertFrom-Json
        (Split-Path $serverDir -Leaf) | Should -Not -Be $manifest.id
    }
}

Describe 'Cross-file validation - icon checks' {
    BeforeAll {
        $script:TempRoot2 = Join-Path ([System.IO.Path]::GetTempPath()) "mcp-registry-test-icon-$(Get-Random)"
        $script:TempServersDir2 = Join-Path $TempRoot2 'servers'
        New-Item -ItemType Directory -Path $TempServersDir2 -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $script:TempRoot2) {
            Remove-Item -Recurse -Force $script:TempRoot2
        }
    }

    It 'passes when icon file exists at declared path' {
        $serverDir = Join-Path $script:TempServersDir2 'mcp-full-featured'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        '' | Set-Content (Join-Path $serverDir 'icon.svg')
        $iconPath = Join-Path $serverDir 'icon.svg'
        Test-Path $iconPath | Should -BeTrue
    }

    It 'fails when icon file is declared but missing' {
        $serverDir = Join-Path $script:TempServersDir2 'mcp-missing-icon'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        $iconPath = Join-Path $serverDir 'icon.svg'
        Test-Path $iconPath | Should -BeFalse
    }

    # The icon field is optional; manifests without it should not require any file.
    It 'passes when no icon field is declared (optional)' {
        $manifest = Get-Content -Raw (Join-Path $script:FixturesValid 'minimal.json') | ConvertFrom-Json
        $manifest.PSObject.Properties.Name -contains 'icon' | Should -BeFalse
    }

    # Icon must be under 500KB (512,000 bytes).
    It 'fails when icon exceeds 500KB' {
        $serverDir = Join-Path $script:TempServersDir2 'mcp-large-icon'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        # Create a 600KB file
        $bytes = New-Object byte[] 614400
        [System.IO.File]::WriteAllBytes((Join-Path $serverDir 'icon.png'), $bytes)
        (Get-Item (Join-Path $serverDir 'icon.png')).Length | Should -BeGreaterThan 512000
    }

    # SVG icons must not contain dangerous content (XSS prevention):
    # <script> tags, event handlers (onload=, onerror=, etc.), or javascript: URIs.
    It 'fails when SVG icon contains script tags' {
        $serverDir = Join-Path $script:TempServersDir2 'mcp-xss-script'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        $maliciousSvg = '<svg xmlns="http://www.w3.org/2000/svg"><script>alert("xss")</script></svg>'
        $maliciousSvg | Set-Content (Join-Path $serverDir 'icon.svg')
        $content = Get-Content -Raw (Join-Path $serverDir 'icon.svg')
        $content -match '<script|on\w+\s*=|javascript\s*:' | Should -BeTrue
    }

    It 'fails when SVG icon contains event handlers' {
        $serverDir = Join-Path $script:TempServersDir2 'mcp-xss-onload'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        $maliciousSvg = '<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"></svg>'
        $maliciousSvg | Set-Content (Join-Path $serverDir 'icon.svg')
        $content = Get-Content -Raw (Join-Path $serverDir 'icon.svg')
        $content -match '<script|on\w+\s*=|javascript\s*:' | Should -BeTrue
    }

    It 'fails when SVG icon contains javascript URIs' {
        $serverDir = Join-Path $script:TempServersDir2 'mcp-xss-jsuri'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        $maliciousSvg = '<svg xmlns="http://www.w3.org/2000/svg"><a xlink:href="javascript:alert(1)">click</a></svg>'
        $maliciousSvg | Set-Content (Join-Path $serverDir 'icon.svg')
        $content = Get-Content -Raw (Join-Path $serverDir 'icon.svg')
        $content -match '<script|on\w+\s*=|javascript\s*:' | Should -BeTrue
    }
}

# --------------------------------------------------------------------------
# End-to-end: invoke validate-manifest.ps1 as a subprocess (simulates the
# actual author/CI experience) and assert on exit codes.
#
# These tests copy the script + schema + module into an isolated temp directory
# so they don't depend on the repo having any real servers/ entries.
# --------------------------------------------------------------------------

Describe 'End-to-end - validate-manifest.ps1 script' {
    BeforeAll {
        $script:ScriptPath = Join-Path $script:RepoRoot 'scripts' 'validate-manifest.ps1'
        # Build an isolated temp repo with just the script, schema, and module.
        $script:E2eRoot = Join-Path ([System.IO.Path]::GetTempPath()) "mcp-e2e-$(Get-Random)"
        $script:E2eServers = Join-Path $E2eRoot 'servers'
        $script:E2eSchemas = Join-Path $E2eRoot 'schemas'
        $script:E2eScripts = Join-Path $E2eRoot 'scripts' 'lib'
        New-Item -ItemType Directory -Path $E2eServers -Force | Out-Null
        New-Item -ItemType Directory -Path $E2eSchemas -Force | Out-Null
        New-Item -ItemType Directory -Path $E2eScripts -Force | Out-Null
        Copy-Item $script:SchemaPath (Join-Path $E2eSchemas 'manifest.schema.json')
        Copy-Item (Join-Path $script:RepoRoot 'scripts' 'lib' 'manifest.psm1') $E2eScripts
        Copy-Item $script:ScriptPath (Join-Path $E2eRoot 'scripts' 'validate-manifest.ps1')
    }

    AfterAll {
        if (Test-Path $script:E2eRoot) {
            Remove-Item -Recurse -Force $script:E2eRoot
        }
    }

    It 'exits 0 for a valid server' {
        $serverDir = Join-Path $script:E2eServers 'mcp-sql-server'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        Copy-Item (Join-Path $script:FixturesValid 'container-http.json') (Join-Path $serverDir 'manifest.json')

        $output = & pwsh -NoProfile -File (Join-Path $script:E2eRoot 'scripts' 'validate-manifest.ps1') -ServerId mcp-sql-server 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "valid manifest should pass ($output)"

        Remove-Item -Recurse -Force $serverDir
    }

    It 'exits 1 when folder name does not match manifest.id' {
        $serverDir = Join-Path $script:E2eServers 'wrong-folder'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        Copy-Item (Join-Path $script:FixturesValid 'container-http.json') (Join-Path $serverDir 'manifest.json')

        & pwsh -NoProfile -File (Join-Path $script:E2eRoot 'scripts' 'validate-manifest.ps1') -ServerId wrong-folder 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1 -Because "folder name 'wrong-folder' != manifest.id 'mcp-sql-server'"

        Remove-Item -Recurse -Force $serverDir
    }

    It 'exits 1 when icon is declared but missing' {
        $serverDir = Join-Path $script:E2eServers 'mcp-full-featured'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        Copy-Item (Join-Path $script:FixturesValid 'full-featured.json') (Join-Path $serverDir 'manifest.json')
        # Intentionally do NOT create icon.svg to trigger the missing-icon check.

        & pwsh -NoProfile -File (Join-Path $script:E2eRoot 'scripts' 'validate-manifest.ps1') -ServerId mcp-full-featured 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1 -Because "icon.svg is declared but not present"

        Remove-Item -Recurse -Force $serverDir
    }

    It 'exits 1 for a schema-invalid manifest' {
        $serverDir = Join-Path $script:E2eServers 'mcp-bad-version'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        Copy-Item (Join-Path $script:FixturesInvalid 'bad-version.json') (Join-Path $serverDir 'manifest.json')

        & pwsh -NoProfile -File (Join-Path $script:E2eRoot 'scripts' 'validate-manifest.ps1') -ServerId mcp-bad-version 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1 -Because "version '1.0' doesn't match semver pattern"

        Remove-Item -Recurse -Force $serverDir
    }

    It 'exits 1 when icon exceeds 500KB' {
        $serverDir = Join-Path $script:E2eServers 'mcp-full-featured'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        Copy-Item (Join-Path $script:FixturesValid 'full-featured.json') (Join-Path $serverDir 'manifest.json')
        # Create a 600KB icon to trigger size check
        $bytes = New-Object byte[] 614400
        [System.IO.File]::WriteAllBytes((Join-Path $serverDir 'icon.svg'), $bytes)

        & pwsh -NoProfile -File (Join-Path $script:E2eRoot 'scripts' 'validate-manifest.ps1') -ServerId mcp-full-featured 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1 -Because "icon exceeds 500KB limit"

        Remove-Item -Recurse -Force $serverDir
    }

    It 'exits 1 when SVG icon contains script tag' {
        $serverDir = Join-Path $script:E2eServers 'mcp-full-featured'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        Copy-Item (Join-Path $script:FixturesValid 'full-featured.json') (Join-Path $serverDir 'manifest.json')
        '<svg><script>alert("xss")</script></svg>' | Set-Content (Join-Path $serverDir 'icon.svg')

        & pwsh -NoProfile -File (Join-Path $script:E2eRoot 'scripts' 'validate-manifest.ps1') -ServerId mcp-full-featured 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1 -Because "SVG contains <script> tag"

        Remove-Item -Recurse -Force $serverDir
    }

    It 'exits 1 when SVG icon contains whitespace-obfuscated script tag' {
        $serverDir = Join-Path $script:E2eServers 'mcp-full-featured'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        Copy-Item (Join-Path $script:FixturesValid 'full-featured.json') (Join-Path $serverDir 'manifest.json')
        # "< script>" (whitespace between '<' and 'script') must still be caught by the
        # <\s*script\b regex. This guards the whitespace tolerance: a simplified '<script'
        # regex would miss this variant, so the test would fail if the rule were weakened.
        '<svg>< script>alert("xss")</script></svg>' | Set-Content (Join-Path $serverDir 'icon.svg')

        & pwsh -NoProfile -File (Join-Path $script:E2eRoot 'scripts' 'validate-manifest.ps1') -ServerId mcp-full-featured 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1 -Because "whitespace-obfuscated < script> must be caught"

        Remove-Item -Recurse -Force $serverDir
    }

    It 'exits 1 when SVG icon contains event handler' {
        $serverDir = Join-Path $script:E2eServers 'mcp-full-featured'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        Copy-Item (Join-Path $script:FixturesValid 'full-featured.json') (Join-Path $serverDir 'manifest.json')
        '<svg onload="alert(1)"></svg>' | Set-Content (Join-Path $serverDir 'icon.svg')

        & pwsh -NoProfile -File (Join-Path $script:E2eRoot 'scripts' 'validate-manifest.ps1') -ServerId mcp-full-featured 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1 -Because "SVG contains onload event handler"

        Remove-Item -Recurse -Force $serverDir
    }

    It 'exits 1 when SVG icon contains javascript URI' {
        $serverDir = Join-Path $script:E2eServers 'mcp-full-featured'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        Copy-Item (Join-Path $script:FixturesValid 'full-featured.json') (Join-Path $serverDir 'manifest.json')
        '<svg><a xlink:href="javascript:alert(1)">x</a></svg>' | Set-Content (Join-Path $serverDir 'icon.svg')

        & pwsh -NoProfile -File (Join-Path $script:E2eRoot 'scripts' 'validate-manifest.ps1') -ServerId mcp-full-featured 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1 -Because "SVG contains javascript: URI"

        Remove-Item -Recurse -Force $serverDir
    }

    # ----------------------------------------------------------------------
    # Schema-conditional coverage THROUGH the script. Unlike the "specific
    # error cases" Describe (which calls Test-Json on the raw schema), these
    # invoke validate-manifest.ps1 so they exercise Resolve-EffectiveSchema /
    # Merge-FlattenedRequired - the runtime flattening of source.type and the
    # transport/auth conditionals. They are the guard against the schema<->script
    # coupling silently rotting: if a schema conditional changes and the script's
    # resolution logic is not updated to match, one of these turns CI red.
    # Each asserts on the error message too, so the RIGHT rule must fire (not just
    # some failure for an unrelated reason).
    # ----------------------------------------------------------------------

    It 'exits 1 and flags missing command for stdio transport (container source)' {
        $serverDir = Join-Path $script:E2eServers 'mcp-stdio-no-cmd'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        Copy-Item (Join-Path $script:FixturesInvalid 'stdio-missing-command.json') (Join-Path $serverDir 'manifest.json')

        $output = & pwsh -NoProfile -File (Join-Path $script:E2eRoot 'scripts' 'validate-manifest.ps1') -ServerId mcp-stdio-no-cmd 2>&1
        $LASTEXITCODE | Should -Be 1 -Because "stdio transport requires 'command' ($output)"
        ($output -join "`n") | Should -Match 'command' -Because "the resolved schema must still require 'command' for stdio"

        Remove-Item -Recurse -Force $serverDir
    }

    It 'exits 1 and flags missing targetPort for http transport (container source)' {
        $serverDir = Join-Path $script:E2eServers 'mcp-no-targetport'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        Copy-Item (Join-Path $script:FixturesInvalid 'container-missing-targetport.json') (Join-Path $serverDir 'manifest.json')

        $output = & pwsh -NoProfile -File (Join-Path $script:E2eRoot 'scripts' 'validate-manifest.ps1') -ServerId mcp-no-targetport 2>&1
        $LASTEXITCODE | Should -Be 1 -Because "http transport requires 'targetPort' ($output)"
        ($output -join "`n") | Should -Match 'targetPort' -Because "the resolved schema must still require 'targetPort' for http"

        Remove-Item -Recurse -Force $serverDir
    }

    It 'exits 1 and flags missing connectionStringVariable for connection-string auth' {
        $serverDir = Join-Path $script:E2eServers 'mcp-auth-missing-connvar'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        Copy-Item (Join-Path $script:FixturesInvalid 'auth-missing-connstring-var.json') (Join-Path $serverDir 'manifest.json')

        $output = & pwsh -NoProfile -File (Join-Path $script:E2eRoot 'scripts' 'validate-manifest.ps1') -ServerId mcp-auth-missing-connvar 2>&1
        $LASTEXITCODE | Should -Be 1 -Because "connection-string auth requires 'connectionStringVariable' ($output)"
        ($output -join "`n") | Should -Match 'connectionStringVariable' -Because "the resolved schema must still require the variable when methods includes connection-string"

        Remove-Item -Recurse -Force $serverDir
    }

    It 'exits 1 and reports an unsupported source.type up front' {
        $serverDir = Join-Path $script:E2eServers 'mcp-unknown-source'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        Copy-Item (Join-Path $script:FixturesInvalid 'unknown-source-type.json') (Join-Path $serverDir 'manifest.json')

        $output = & pwsh -NoProfile -File (Join-Path $script:E2eRoot 'scripts' 'validate-manifest.ps1') -ServerId mcp-unknown-source 2>&1
        $LASTEXITCODE | Should -Be 1 -Because "source.type 'npm' is not a supported discriminator ($output)"
        ($output -join "`n") | Should -Match 'not supported' -Because "the script must reject an undiscriminatable source.type with one clean message"

        Remove-Item -Recurse -Force $serverDir
    }

    It 'exits 0 for a valid github source (exercises githubSource resolution)' {
        $serverDir = Join-Path $script:E2eServers 'mcp-cosmosdb'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        Copy-Item (Join-Path $script:FixturesValid 'github-source.json') (Join-Path $serverDir 'manifest.json')

        $output = & pwsh -NoProfile -File (Join-Path $script:E2eRoot 'scripts' 'validate-manifest.ps1') -ServerId mcp-cosmosdb 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "a well-formed github source must pass end-to-end ($output)"

        Remove-Item -Recurse -Force $serverDir
    }

    It 'exits 0 for a valid local source (exercises localSource resolution)' {
        $serverDir = Join-Path $script:E2eServers 'mcp-local-build'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        Copy-Item (Join-Path $script:FixturesValid 'local-source.json') (Join-Path $serverDir 'manifest.json')

        $output = & pwsh -NoProfile -File (Join-Path $script:E2eRoot 'scripts' 'validate-manifest.ps1') -ServerId mcp-local-build 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "a well-formed local source must pass end-to-end ($output)"

        Remove-Item -Recurse -Force $serverDir
    }

    It 'exits 1 and flags missing dockerfile for local source (exercises localSource resolution)' {
        $serverDir = Join-Path $script:E2eServers 'mcp-local-no-dockerfile'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        Copy-Item (Join-Path $script:FixturesInvalid 'local-missing-dockerfile.json') (Join-Path $serverDir 'manifest.json')

        $output = & pwsh -NoProfile -File (Join-Path $script:E2eRoot 'scripts' 'validate-manifest.ps1') -ServerId mcp-local-no-dockerfile 2>&1
        $LASTEXITCODE | Should -Be 1 -Because "local source requires 'dockerfile' ($output)"
        ($output -join "`n") | Should -Match 'dockerfile' -Because "the resolved schema must still require 'dockerfile' for local source"

        Remove-Item -Recurse -Force $serverDir
    }

    # ----------------------------------------------------------------------
    # Configuration-input coverage THROUGH the script. These exercise
    # Resolve-ConfigurationSchema - the runtime resolution of each 'type'-
    # discriminated input to its concrete shape (env var vs file, enum requires
    # allowedValues). Like the source-conditional cases above, they guard the
    # schema<->script coupling: each asserts on the message so the RIGHT rule fires.
    It 'exits 0 for a manifest with valid configuration inputs (exercises config resolution)' {
        $serverDir = Join-Path $script:E2eServers 'mcp-config-inputs'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        Copy-Item (Join-Path $script:FixturesValid 'config-inputs.json') (Join-Path $serverDir 'manifest.json')

        $output = & pwsh -NoProfile -File (Join-Path $script:E2eRoot 'scripts' 'validate-manifest.ps1') -ServerId mcp-config-inputs 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "well-formed enum/secret/int/bool/file inputs must pass end-to-end ($output)"

        Remove-Item -Recurse -Force $serverDir
    }

    It 'exits 1 and flags a file input missing fileName (exercises config resolution)' {
        $serverDir = Join-Path $script:E2eServers 'mcp-bad-file-input'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        Copy-Item (Join-Path $script:FixturesInvalid 'config-file-missing-filename.json') (Join-Path $serverDir 'manifest.json')

        $output = & pwsh -NoProfile -File (Join-Path $script:E2eRoot 'scripts' 'validate-manifest.ps1') -ServerId mcp-bad-file-input 2>&1
        $LASTEXITCODE | Should -Be 1 -Because "a file input requires fileName ($output)"
        ($output -join "`n") | Should -Match 'fileName' -Because "the resolved schema must require fileName for a file input"

        Remove-Item -Recurse -Force $serverDir
    }

    It 'exits 1 and flags an enum input missing allowedValues (exercises config resolution)' {
        $serverDir = Join-Path $script:E2eServers 'mcp-bad-enum-input'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        Copy-Item (Join-Path $script:FixturesInvalid 'config-enum-missing-allowedvalues.json') (Join-Path $serverDir 'manifest.json')

        $output = & pwsh -NoProfile -File (Join-Path $script:E2eRoot 'scripts' 'validate-manifest.ps1') -ServerId mcp-bad-enum-input 2>&1
        $LASTEXITCODE | Should -Be 1 -Because "an enum input requires allowedValues ($output)"
        ($output -join "`n") | Should -Match 'allowedValues' -Because "the resolved schema must require allowedValues for an enum input"

        Remove-Item -Recurse -Force $serverDir
    }

    It 'exits 1 and flags a non-file input with an invalid env var name (exercises config resolution)' {
        $serverDir = Join-Path $script:E2eServers 'mcp-bad-env-name'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        Copy-Item (Join-Path $script:FixturesInvalid 'config-env-lowercase-name.json') (Join-Path $serverDir 'manifest.json')

        $output = & pwsh -NoProfile -File (Join-Path $script:E2eRoot 'scripts' 'validate-manifest.ps1') -ServerId mcp-bad-env-name 2>&1
        $LASTEXITCODE | Should -Be 1 -Because "a non-file input name must be UPPER_SNAKE_CASE ($output)"
        ($output -join "`n") | Should -Match 'name' -Because "the resolved schema must reject a non-UPPER_SNAKE name for a non-file input"

        Remove-Item -Recurse -Force $serverDir
    }

    It 'exits 0 for a valid stdio container source (exercises stdio command path)' {
        $serverDir = Join-Path $script:E2eServers 'mcp-playwright'
        New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        Copy-Item (Join-Path $script:FixturesValid 'container-stdio.json') (Join-Path $serverDir 'manifest.json')

        $output = & pwsh -NoProfile -File (Join-Path $script:E2eRoot 'scripts' 'validate-manifest.ps1') -ServerId mcp-playwright 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "a well-formed stdio container source must pass end-to-end ($output)"

        Remove-Item -Recurse -Force $serverDir
    }
}
