<#
.SYNOPSIS
  Manifest-reading helpers for the public registry repo's validation.

  Public-input only: enumerate and load server manifests. The privileged
  build/publish helpers (ACR naming, digest resolution) live in the internal
  mcp-service repo, not here.

  Cross-platform PowerShell (pwsh 7+).
#>

Set-StrictMode -Version Latest

# Root of the repository (this file lives in scripts/lib/).
function Get-RepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
}

# Load and parse a server manifest as a PSCustomObject.
function Get-ServerManifest {
    param(
        [Parameter(Mandatory)] [string] $ServerId,
        [string] $RepoRoot = (Get-RepoRoot)
    )
    $path = Join-Path $RepoRoot 'servers' $ServerId 'manifest.json'
    if (-not (Test-Path $path)) {
        throw "Manifest not found for server '$ServerId' at $path"
    }
    return Get-Content -Raw -Path $path | ConvertFrom-Json
}

# Enumerate all server ids (folders under servers/ that contain a manifest.json,
# excluding the _template scaffold).
function Get-AllServerIds {
    param([string] $RepoRoot = (Get-RepoRoot))
    $serversDir = Join-Path $RepoRoot 'servers'
    Get-ChildItem -Path $serversDir -Directory |
        Where-Object { $_.Name -ne '_template' } |
        Where-Object { Test-Path (Join-Path $_.FullName 'manifest.json') } |
        Select-Object -ExpandProperty Name |
        Sort-Object
}

Export-ModuleMember -Function *
