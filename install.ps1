#Requires -Version 5.1
<#
.SYNOPSIS
Installs Astra in the current user's Codex pet picker.
.PARAMETER CodexHome
Optional Codex data directory. Defaults to CODEX_HOME, then the user's .codex directory.
.EXAMPLE
.\install.ps1
.EXAMPLE
.\install.ps1 -CodexHome 'D:\Codex Data' -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param([string]$CodexHome)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($CodexHome)) {
    $CodexHome = $env:CODEX_HOME
}
if ([string]::IsNullOrWhiteSpace($CodexHome)) {
    $CodexHome = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'
}
$codexRoot = [IO.Path]::GetFullPath($CodexHome)
$petDirectory = Join-Path (Join-Path $codexRoot 'pets') 'astra'
$sourceDirectory = Join-Path $PSScriptRoot 'pet'
$files = @('spritesheet.png', 'pet.json') # Publish the manifest last.
$checksums = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'checksums.json') | ConvertFrom-Json

foreach ($name in $files) {
    $source = Join-Path $sourceDirectory $name
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Missing package file: $name. Download or clone the complete repository."
    }
    $actual = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    $expected = $checksums.PSObject.Properties[$name]
    if ($null -eq $expected -or $actual -ine $expected.Value) {
        throw "Checksum mismatch for $name. The installation has not been changed."
    }
}
$manifest = Get-Content -Raw -LiteralPath (Join-Path $sourceDirectory 'pet.json') | ConvertFrom-Json
if ($manifest.displayName -ne 'Astra' -or $manifest.spriteVersionNumber -ne 2 -or $manifest.spritesheetPath -ne 'spritesheet.png') {
    throw 'The bundled pet manifest does not match this installer.'
}

# Avoid writing through a redirected pet directory.
foreach ($directory in @((Join-Path $codexRoot 'pets'), $petDirectory)) {
    if (Test-Path -LiteralPath $directory) {
        $entry = Get-Item -Force -LiteralPath $directory
        if (-not $entry.PSIsContainer -or ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Expected a regular directory: $directory"
        }
    }
}

$alreadyInstalled = $true
foreach ($name in $files) {
    $target = Join-Path $petDirectory $name
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        $alreadyInstalled = $false
    } elseif ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ine $checksums.PSObject.Properties[$name].Value) {
        $alreadyInstalled = $false
    }
}
if ($alreadyInstalled) {
    Write-Host "Astra is already installed at $petDirectory"
    Write-Host 'Select Astra in the Codex pet picker. Restart Codex if Astra is not listed.'
    return
}
if (-not $PSCmdlet.ShouldProcess($petDirectory, 'Install Astra and back up existing pet files')) {
    return
}

$backupDirectory = $null
$previousFiles = @($files | Where-Object { Test-Path -LiteralPath (Join-Path $petDirectory $_) -PathType Leaf })
if ($previousFiles.Count -gt 0) {
    $backupName = 'astra-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [Guid]::NewGuid().ToString('N')
    $backupDirectory = Join-Path (Join-Path $codexRoot 'pet-backups') $backupName
    [IO.Directory]::CreateDirectory($backupDirectory) | Out-Null
    foreach ($name in $previousFiles) {
        [IO.File]::Copy((Join-Path $petDirectory $name), (Join-Path $backupDirectory $name), $false)
    }
    Write-Host "Previous pet files backed up to $backupDirectory"
}
[IO.Directory]::CreateDirectory($petDirectory) | Out-Null

function Copy-AtomicFile([string]$Source, [string]$Destination) {
    $temporaryFile = $Destination + '.tmp-' + [Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::Copy($Source, $temporaryFile, $false)
        if ([IO.File]::Exists($Destination)) {
            [IO.File]::Replace($temporaryFile, $Destination, [NullString]::Value)
        } else {
            [IO.File]::Move($temporaryFile, $Destination)
        }
    } finally {
        if ([IO.File]::Exists($temporaryFile)) {
            [IO.File]::Delete($temporaryFile)
        }
    }
}

$published = [Collections.Generic.List[string]]::new()
try {
    foreach ($name in $files) {
        $target = Join-Path $petDirectory $name
        Copy-AtomicFile (Join-Path $sourceDirectory $name) $target
        $published.Add($name)
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ine $checksums.PSObject.Properties[$name].Value) {
            throw "Installed file verification failed: $name"
        }
    }
} catch {
    foreach ($name in $published) {
        $target = Join-Path $petDirectory $name
        if ($previousFiles -contains $name) {
            Copy-AtomicFile (Join-Path $backupDirectory $name) $target
        } elseif ([IO.File]::Exists($target)) {
            [IO.File]::Delete($target)
        }
    }
    throw
}

Write-Host "Installed Astra at $petDirectory"
Write-Host 'Select Astra in the Codex pet picker. Restart Codex if Astra is not listed.'
