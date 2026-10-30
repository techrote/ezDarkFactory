#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SourceCache = '.provenance-cache',
    [string]$Python = 'python',
    [string]$PowerShell7 = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'The complete EDF-002 PowerShell 5.1/7 gate requires Windows. Linux can run the SOURCE/Python gate.'
}
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cache = if ([IO.Path]::IsPathRooted($SourceCache)) { $SourceCache } else { Join-Path $root $SourceCache }
& $Python (Join-Path $root 'tools/check.py') --fetch --sources $cache
if ($LASTEXITCODE -ne 0) { throw 'EDF provenance/Python gate failed.' }
$ps5 = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
if (-not (Test-Path -LiteralPath $ps5 -PathType Leaf)) { throw 'Required Windows PowerShell 5.1 executable is missing.' }
foreach ($check in @('Repository', 'ControlPlane')) {
    & $ps5 -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'scripts/Invoke-CiCheck.ps1') -Check $check -ExpectedMajor 5
    if ($LASTEXITCODE -ne 0) { throw "Windows PowerShell 5.1 $check gate failed." }
}
if ([string]::IsNullOrWhiteSpace($PowerShell7)) {
    $PowerShell7 = & (Join-Path $root 'scripts/Install-TestPowerShell.ps1') -DestinationRoot (Join-Path $root 'runtime/test-tools')
}
if (-not (Test-Path -LiteralPath $PowerShell7 -PathType Leaf)) { throw 'Verified pinned PowerShell 7 executable is missing.' }
& $PowerShell7 -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'scripts/Invoke-CiCheck.ps1') -Check ControlPlane -ExpectedMajor 7
if ($LASTEXITCODE -ne 0) { throw 'Pinned PowerShell 7 control-plane gate failed.' }
Write-Host 'EDF FAST-CI PASS: SOURCE/Python, repository contract, Windows PowerShell 5.1 and pinned PowerShell 7.'
