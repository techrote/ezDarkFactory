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

    # Synthetic-only event bridge for the actual selected Textual fixture.
    $fixtureText = @(& $python -I (Join-Path $root 'tools/edf006_physical_tui.py') --headless-smoke) -join ''
    if ($LASTEXITCODE -ne 0) { throw 'EDF-006 physical fixture headless smoke failed.' }
    $fixture = $fixtureText | ConvertFrom-Json
    if ($fixture.evidence -cne 'FAST-CI-HEADLESS' -or $fixture.physical_tui -or
        $fixture.actions.menu_open -ne 5 -or $fixture.actions.menu_escape -ne 2 -or
        $fixture.actions.menu_dismiss_consumed -ne 2 -or
        $fixture.actions.overlay_key_consumed -ne 3 -or
        $fixture.actions.overlay_pointer_consumed -ne 1 -or
        $fixture.actions.context_menu_open -ne 1 -or
        $fixture.actions.divider_begin -ne 5 -or
        $fixture.actions.divider_commit -ne 1 -or $fixture.actions.divider_cancel -ne 4 -or
        $fixture.actions.overlay_resize_dismiss -ne 1 -or
        $fixture.actions.paste_refused -ne 2 -or $fixture.actions.paste_allowed -ne 1 -or
        $fixture.actions.recover -ne 1 -or
        $fixture.input_to_visible_frame_p95_ms -ne $null) {
        throw 'EDF-006 physical fixture synthetic receipt failed validation.'
    }
    Write-Host ('EDF-006 Textual physical fixture HEADLESS PASS: {0}' -f $fixtureText)

    # Compose trusted bootstrap + bounded per-root workers in an actual Textual
    # event loop. Synthetic roots only; never native presentation evidence.
    $monitorText = @(& $python -I (Join-Path $root 'tools/edf006_fleet_monitor.py') --headless-smoke) -join ''
    if ($LASTEXITCODE -ne 0) { throw 'EDF-006 multi-root Textual monitor headless smoke failed.' }
    $monitor = $monitorText | ConvertFrom-Json
    if ($monitor.evidence -cne 'FAST-CI-HEADLESS' -or $monitor.physical_tui -or
        $monitor.live_instances_observed -or $monitor.input_to_visible_frame_p95_ms -ne $null -or
        $monitor.bootstrap -cne 'synthetic' -or
        (@($monitor.peer_states) -join ',') -cne 'unreachable,current,conflict') {
        throw 'EDF-006 fleet monitor reported invalid synthetic evidence.'
    }
    Write-Host ('EDF-006 read-only fleet monitor HEADLESS PASS: {0}' -f $monitorText)
}
finally {
    if (Test-Path -LiteralPath $workspace) { Remove-Item -LiteralPath $workspace -Recurse -Force }
}
