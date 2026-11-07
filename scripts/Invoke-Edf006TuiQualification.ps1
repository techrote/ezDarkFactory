#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$OutputDirectory)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not [IO.Path]::IsPathRooted($OutputDirectory)) { throw 'OutputDirectory must be absolute.' }
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$workspace = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ('runtime-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($workspace) | Out-Null
try {
    $python = @(& (Join-Path $root 'scripts/Install-Edf006TuiRuntime.ps1') -DestinationRoot $workspace) | Select-Object -Last 1
    if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw 'Pinned TUI installer did not return python.exe.' }
    $probe = Join-Path $root 'tools/edf006_textual_probe.py'
    $resultText = @(& $python -I $probe --self-test) -join ''
    if ($LASTEXITCODE -ne 0) { throw 'EDF-006 Textual headless integration probe failed.' }
    $result = $resultText | ConvertFrom-Json
    if ($result.evidence -cne 'FAST-CI-HEADLESS' -or $result.physical_tui) {
        throw 'TUI integration probe returned an invalid evidence classification.'
    }
    if ($result.source.textual -cne '8.2.8' -or $result.headless.semantic_actions -ne 1) {
        throw 'TUI integration probe returned an unexpected runtime/semantic result.'
    }
    $receiptPath = Join-Path $OutputDirectory 'edf006-tui-fast-ci.json'
    [IO.File]::WriteAllText($receiptPath, ($result | ConvertTo-Json -Depth 8) + "`n", (New-Object Text.UTF8Encoding($false)))
    Write-Host ('EDF-006 TUI FAST-CI PASS: {0}' -f $resultText)
}
finally {
    if (Test-Path -LiteralPath $workspace) { Remove-Item -LiteralPath $workspace -Recurse -Force }
}
