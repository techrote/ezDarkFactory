#requires -Version 5.1
# Offline, network-free functional regression of the real pinned test installer.
# Every mocked response has INVALID bytes: extraction/execution must never happen.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$installer = Join-Path $repo 'scripts/Install-TestPowerShell.ps1'
$pin = Get-Content -LiteralPath (Join-Path $repo 'tests/tooling.json') -Raw | ConvertFrom-Json
$official = [string]$pin.powerShell7.url
$mirror = 'https://downloads.sourceforge.net/project/powershell.mirror/v' + $pin.powerShell7.version + '/PowerShell-' + $pin.powerShell7.version + '-win-x64.zip'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('edf006-pinned-pwsh-fixture-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixtureRoot)

# These functions are dynamically visible to the invoked child script. They
# record URL order and never access a real network or supply valid ZIP bytes.
$script:requests = @()
$script:fixtureMode = ''
function Invoke-WebRequest {
    [CmdletBinding()]
    param([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing,
          [int]$TimeoutSec)
    $script:requests += $Uri
    if ($script:fixtureMode -eq 'all-down' -or
        ($script:fixtureMode -eq 'official-down' -and $Uri -eq $official)) {
        throw 'SYNTHETIC-TRANSPORT-FAILURE'
    }
    [IO.File]::WriteAllBytes($OutFile, [byte[]](0x50, 0x4b, 0x03, 0x04))
}
function Start-Sleep { param([int]$Seconds) }  # no delay for fake outages

try {
    foreach ($case in @(
        @{ Name = 'official-corrupt'; Mode = 'official-corrupt'; Expected = @($official); Refusal = 'wrong byte length' },
        @{ Name = 'official-down-mirror-corrupt'; Mode = 'official-down'; Expected = @($official, $official, $official, $mirror); Refusal = 'wrong byte length' },
        @{ Name = 'both-transports-down'; Mode = 'all-down'; Expected = @($official, $official, $official, $mirror, $mirror); Refusal = 'Could not acquire' }
    )) {
        $script:fixtureMode = $case.Mode
        $script:requests = @()
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
        if (@($script:requests).Count -ne @($case.Expected).Count) {
            throw ('Incorrect acquisition attempt count: ' + $case.Name)
        }
        for ($i = 0; $i -lt @($case.Expected).Count; $i++) {
            if ($script:requests[$i] -cne $case.Expected[$i]) {
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
}
