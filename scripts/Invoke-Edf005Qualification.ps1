#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory, [Parameter(Mandatory)][ValidateSet(5,7)][int]$ExpectedMajor)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version 2.0
$script:EzDarkFactoryRepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or [IntPtr]::Size -ne 8) { throw 'EDF-005 focused test requires Windows x64 filesystem semantics.' }
if ($PSVersionTable.PSVersion.Major -ne $ExpectedMajor) { throw 'PowerShell major does not match requested focused lane.' }
if ($ExpectedMajor -eq 7) {
    $tool = Get-Content -LiteralPath (Join-Path $script:EzDarkFactoryRepositoryRoot 'tests/tooling.json') -Raw | ConvertFrom-Json
    if ($PSVersionTable.PSVersion.ToString() -cne $tool.powerShell7.version) { throw 'PowerShell 7 version is not pinned tooling.' }
}
$head = ((git -C $script:EzDarkFactoryRepositoryRoot rev-parse HEAD) -join '').Trim()
$tree = ((git -C $script:EzDarkFactoryRepositoryRoot rev-parse 'HEAD^{tree}') -join '').Trim()
if ($LASTEXITCODE -ne 0 -or $head -cnotmatch '^[a-f0-9]{40}$' -or $tree -cnotmatch '^[a-f0-9]{40}$') { throw 'Missing exact source identity.' }
if (@(git -C $script:EzDarkFactoryRepositoryRoot status --porcelain).Count -ne 0) { throw 'Source must be clean.' }
$files = @('src/EzDarkFactory/Control.ps1','src/EzDarkFactory/Manager.ps1',
    'src/EzDarkFactory/Edf005.psm1',
    'ezdarkfactory.ps1','ezdarkfactory-control.ps1','ezdarkfactory-worker.ps1','ezdarkfactory-attach.ps1',
    'docs/schemas/control-dispatch.v1.schema.json','docs/schemas/shell-descriptor.v1.schema.json',
    'tests/Edf005Control.Tests.ps1','scripts/Invoke-Edf005Qualification.ps1')
$digests = [ordered]@{}
foreach ($file in $files) { $digests[$file] = (Get-FileHash -LiteralPath (Join-Path $script:EzDarkFactoryRepositoryRoot $file) -Algorithm SHA256).Hash.ToLowerInvariant() }
. (Join-Path $script:EzDarkFactoryRepositoryRoot 'tests/TestHarness.ps1')
Import-Module (Join-Path $script:EzDarkFactoryRepositoryRoot 'src/EzDarkFactory/Edf005.psm1') -Force
. (Join-Path $script:EzDarkFactoryRepositoryRoot 'tests/Edf005Control.Tests.ps1')
$tests = @($script:EzDarkFactoryTestCases | Where-Object { $_.Name -like 'EDF-005:*' })
if ($tests.Count -lt 22) { throw 'EDF-005 qualification requires at least eight mandatory tests.' }
$cases = New-Object 'System.Collections.Generic.List[object]'
$failed = 0
$receipt = [ordered]@{
    schemaVersion = 1; issue = 'EDF-005'; head = $head; tree = $tree
    os = [Environment]::OSVersion.ToString(); powerShell = $PSVersionTable.PSVersion.ToString()
    sourceSha256 = $digests; began_at = [DateTime]::UtcNow.ToString('o'); ended_at = $null
    tests = @(); failed = $null; passed = $null
    qemu = 'UNMEASURED'; whpx = 'UNMEASURED'; physicalTui = 'NOT IMPLEMENTED'
}
try {
    foreach ($test in $tests) {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $case = [ordered]@{ name = $test.Name; result = 'FAIL'; milliseconds = 0; diagnostic = $null }
        try {
            if ($test.SkipReason) { throw ('Mandatory focused case was skipped: ' + $test.SkipReason) }
            & $test.Body $test.Data | Out-Null
            $case.result = 'PASS'
            Write-Host ('PASS ' + $test.Name)
        }
        catch {
            $failed++
            $case.diagnostic = $_.Exception.Message
            Write-Host ('FAIL ' + $test.Name + ': ' + $case.diagnostic)
            Write-Host $_.ScriptStackTrace
        }
        $case.milliseconds = $watch.ElapsedMilliseconds
        $cases.Add([pscustomobject]$case)
    }
    foreach ($file in $files) {
        if ((Get-FileHash -LiteralPath (Join-Path $script:EzDarkFactoryRepositoryRoot $file) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $digests[$file]) { throw 'Source mutated during qualification.' }
    }
    if (@(git -C $script:EzDarkFactoryRepositoryRoot status --porcelain).Count -ne 0) { throw 'Qualification dirtied source.' }
}
finally {
    $receipt.tests = @($cases.ToArray()); $receipt.failed = $failed
    $receipt.passed = $tests.Count - $failed; $receipt.ended_at = [DateTime]::UtcNow.ToString('o')
    [void][IO.Directory]::CreateDirectory($OutputDirectory)
    $path = Join-Path $OutputDirectory ('edf005-ps' + $ExpectedMajor + '.json')
    [IO.File]::WriteAllText($path, (($receipt | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    Get-FileHash -Algorithm SHA256 -LiteralPath $path | Format-List | Out-Host
    Write-Host ('EDF005_RESULT passed=' + $receipt.passed + ';failed=' + $failed + ';qemu=UNMEASURED')
}
if ($failed -ne 0) { throw "$failed EDF-005 focused test(s) failed." }
