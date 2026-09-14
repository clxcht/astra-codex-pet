#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $repoRoot 'install.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('astra-installer-test-' + [Guid]::NewGuid().ToString('N'))
$oldCodexHome = $env:CODEX_HOME

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAILED: $Message" }
}

try {
    $dryRun = Join-Path $testRoot 'dry run'
    & $installer -CodexHome $dryRun -WhatIf
    Assert-True (-not (Test-Path -LiteralPath $dryRun)) 'WhatIf must not write files'

    $testData = Join-Path $testRoot 'custom data with spaces'
    [IO.Directory]::CreateDirectory($testData) | Out-Null
    $settings = Join-Path $testData '.codex-global-state.json'
    [IO.File]::WriteAllText($settings, '{"unrelated":"preserve me"}')
    $settingsHash = (Get-FileHash -LiteralPath $settings).Hash
    $otherPet = Join-Path $testData 'pets\another-pet\keep.txt'
    [IO.Directory]::CreateDirectory((Split-Path -Parent $otherPet)) | Out-Null
    [IO.File]::WriteAllText($otherPet, 'keep me')

    & $installer -CodexHome $testData
    foreach ($name in @('pet.json', 'spritesheet.png')) {
        $source = Join-Path (Join-Path $repoRoot 'pet') $name
        $target = Join-Path (Join-Path $testData 'pets\astra') $name
        Assert-True ((Get-FileHash -LiteralPath $source).Hash -eq (Get-FileHash -LiteralPath $target).Hash) "Fresh install: $name"
    }
    Assert-True ((Get-FileHash -LiteralPath $settings).Hash -eq $settingsHash) 'Settings must remain unchanged'
    Assert-True ((Get-Content -Raw -LiteralPath $otherPet) -eq 'keep me') 'Other pets must remain unchanged'

    & $installer -CodexHome $testData
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $testData 'pet-backups'))) 'Identical reinstall must not create backups'

    $installedManifest = Join-Path $testData 'pets\astra\pet.json'
    [IO.File]::WriteAllText($installedManifest, '{"displayName":"previous version"}')
    $previousHash = (Get-FileHash -LiteralPath $installedManifest).Hash
    & $installer -CodexHome $testData
    $backups = @(Get-ChildItem -Directory -LiteralPath (Join-Path $testData 'pet-backups'))
    Assert-True ($backups.Count -eq 1) 'Changed install must produce one backup'
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $backups[0].FullName 'pet.json')).Hash -eq $previousHash) 'Backup must preserve the old manifest'

    $env:CODEX_HOME = Join-Path $testRoot 'environment default'
    & $installer
    Assert-True (Test-Path -LiteralPath (Join-Path $env:CODEX_HOME 'pets\astra\pet.json')) 'CODEX_HOME must be respected'

    $badPackage = Join-Path $testRoot 'bad package'
    [IO.Directory]::CreateDirectory((Join-Path $badPackage 'pet')) | Out-Null
    foreach ($name in @('install.ps1', 'checksums.json')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $name) -Destination $badPackage
    }
    Copy-Item -LiteralPath (Join-Path $repoRoot 'pet\pet.json') -Destination (Join-Path $badPackage 'pet')
    [IO.File]::WriteAllText((Join-Path $badPackage 'pet\spritesheet.png'), 'corrupt')
    $badTarget = Join-Path $testRoot 'must not exist'
    $rejected = $false
    try { & (Join-Path $badPackage 'install.ps1') -CodexHome $badTarget }
    catch { $rejected = $_.Exception.Message -like '*Checksum mismatch*' }
    Assert-True $rejected 'Corrupted artwork must be rejected'
    Assert-True (-not (Test-Path -LiteralPath $badTarget)) 'Invalid package must not change the destination'
    Write-Host 'PASS: dry run, fresh install, preserved settings and other pets, idempotent reinstall, backup, CODEX_HOME, and corrupt-package rejection.'
} finally {
    $env:CODEX_HOME = $oldCodexHome
    # Resolve and verify this unique test directory before recursive cleanup.
    $resolvedRoot = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if ($resolvedRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        ([IO.Path]::GetFileName($resolvedRoot) -like 'astra-installer-test-*') -and
        (Test-Path -LiteralPath $resolvedRoot)) {
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
    }
}
