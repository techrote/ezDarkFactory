#requires -Version 5.1
# Offline, network-free functional regression of the real pinned test installer.
# Every mocked response has INVALID bytes: extraction/execution must never happen.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$installer = Join-Path $repo 'scripts/Install-Edf006ResilientTestPowerShell.ps1'
$pin = Get-Content -LiteralPath (Join-Path $repo 'tests/tooling.json') -Raw | ConvertFrom-Json
$official = [string]$pin.powerShell7.url
$mirror = 'https://downloads.sourceforge.net/project/powershell.mirror/v' + $pin.powerShell7.version + '/PowerShell-' + $pin.powerShell7.version + '-win-x64.zip'
$api = 'https://api.github.com/repos/PowerShell/PowerShell/releases/assets/551207033'
$direct = 'https://master.dl.sourceforge.net/project/powershell.mirror/v' + $pin.powerShell7.version + '/PowerShell-' + $pin.powerShell7.version + '-win-x64.zip'
$global:EDF006FixtureOfficial = $official
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('edf006-pinned-pwsh-fixture-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixtureRoot)

# These functions are dynamically visible to the invoked child script. They
# record URL order and never access a real network or supply valid ZIP bytes.
$global:EDF006FixtureUris = @()
$global:EDF006FixtureMode = ''
function global:Invoke-WebRequest {
    [CmdletBinding()]
    param([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing,
          [int]$TimeoutSec, [hashtable]$Headers)
    $global:EDF006FixtureUris += $Uri
    if ($global:EDF006FixtureMode -eq 'all-down' -or
        ($global:EDF006FixtureMode -eq 'official-down' -and $Uri -eq $global:EDF006FixtureOfficial)) {
        throw 'SYNTHETIC-TRANSPORT-FAILURE'
    }
    [IO.File]::WriteAllBytes($OutFile, [byte[]](0x50, 0x4b, 0x03, 0x04))
}
function global:Start-Sleep { param([int]$Seconds) }  # no delay for fake outages

try {
    foreach ($case in @(
        @{ Name = 'official-corrupt'; Mode = 'official-corrupt'; Expected = @($official, $api, $mirror, $direct); Refusal = 'Could not acquire' },
        @{ Name = 'official-down-other-payloads-corrupt'; Mode = 'official-down'; Expected = @($official, $official, $api, $mirror, $direct); Refusal = 'Could not acquire' },
        @{ Name = 'all-transports-down'; Mode = 'all-down'; Expected = @($official, $official, $api, $api, $mirror, $mirror, $direct); Refusal = 'Could not acquire' }
    )) {
        $global:EDF006FixtureMode = $case.Mode
        $global:EDF006FixtureUris = @()
        $refused = $false
        try {
            $null = & $installer -DestinationRoot $fixtureRoot
        }
        catch {
            if ($_.Exception.Message -notmatch [regex]::Escape($case.Refusal)) {
                throw ('Unexpected refusal in ' + $case.Name + ': ' + $_.Exception.Message)
            }
            $refused = $true
        }
        if (-not $refused) {
            throw ('Invalid archive or missing transports were accepted: ' + $case.Name)
        }
        if (@($global:EDF006FixtureUris).Count -ne @($case.Expected).Count) {
            throw ('Incorrect acquisition attempt count: ' + $case.Name)
        }
        for ($i = 0; $i -lt @($case.Expected).Count; $i++) {
            if ($global:EDF006FixtureUris[$i] -cne $case.Expected[$i]) {
                throw ('Unpinned source or incorrect acquisition order: ' + $case.Name)
            }
        }
        if (@(Get-ChildItem -LiteralPath $fixtureRoot -Force).Count -ne 0) {
            throw ('Unverified download or extracted payload left behind: ' + $case.Name)
        }
        Write-Host ('PASS EDF-006 pinned test-runtime ' + $case.Name)
    }
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Force -Recurse
    }
    Remove-Item -Path Function:\Invoke-WebRequest,Function:\Start-Sleep -ErrorAction SilentlyContinue
    Remove-Variable -Name EDF006FixtureOfficial,EDF006FixtureMode,EDF006FixtureUris -Scope Global -ErrorAction SilentlyContinue
}
