#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][ValidateSet(5, 7)][int]$ExpectedMajor
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version 2.0
$script:EzDarkFactoryRepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or [IntPtr]::Size -ne 8) { throw 'EDF-004 focused guest qualification requires Windows x64.' }
if ($PSVersionTable.PSVersion.Major -ne $ExpectedMajor) { throw 'The executing PowerShell engine does not match the requested lane.' }
$tooling = Get-Content -Raw -LiteralPath (Join-Path $script:EzDarkFactoryRepositoryRoot 'tests/tooling.json') | ConvertFrom-Json
if ($ExpectedMajor -eq 7 -and $PSVersionTable.PSVersion.ToString() -cne $tooling.powerShell7.version) { throw 'The executing PowerShell 7 version does not match tests/tooling.json.' }
$head = ((git -C $script:EzDarkFactoryRepositoryRoot rev-parse HEAD) -join '').Trim()
if ($LASTEXITCODE -ne 0 -or $head -cnotmatch '^[a-f0-9]{40}$') { throw 'Cannot identify qualification commit.' }
$tree = ((git -C $script:EzDarkFactoryRepositoryRoot rev-parse 'HEAD^{tree}') -join '').Trim()
if ($LASTEXITCODE -ne 0 -or $tree -cnotmatch '^[a-f0-9]{40}$') { throw 'Cannot identify qualification tree.' }
$dirty = @(git -C $script:EzDarkFactoryRepositoryRoot status --porcelain --untracked-files=normal)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'Qualification requires a clean exact checkout; no dirty source can qualify.' }
$sourcePaths = @(
    'src/EzDarkFactory/Profiles.ps1',
    'src/EzDarkFactory/Registry.ps1',
    'guest/profiles/fresh-project/v1/profile.json',
    'guest/profiles/fresh-project/v1/provision.sh',
    'guest/base-cloud-init/baseline.json',
    'guest/base-cloud-init/user-data.yaml',
    'tests/TestHarness.ps1',
    'tests/Edf004FreshGuest.Tests.ps1',
    'scripts/Invoke-Edf004Qualification.ps1'
)
$digests = [ordered]@{}
foreach ($relative in $sourcePaths) { $digests[$relative] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $script:EzDarkFactoryRepositoryRoot $relative)).Hash.ToLowerInvariant() }
. (Join-Path $script:EzDarkFactoryRepositoryRoot 'tests/TestHarness.ps1')
Import-Module (Join-Path $script:EzDarkFactoryRepositoryRoot 'src/EzDarkFactory/EzDarkFactory.psd1') -Force
foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $script:EzDarkFactoryRepositoryRoot 'tests') -Filter '*.Tests.ps1' -File | Sort-Object Name)) { . $file.FullName }
$tests = @($script:EzDarkFactoryTestCases | Where-Object { $_.Name -like 'EDF-004:*' })
if ($tests.Count -lt 6) { throw 'Fewer than six EDF-004 tests were discovered; refusing incomplete success.' }
$cases = New-Object 'System.Collections.Generic.List[object]'
$failureCount = 0
$receipt = [ordered]@{
    schemaVersion = 1; issue = 'EDF-004'; sourceRevision = $head; sourceTree = $tree
    cleanCheckout = $true; sourceSha256 = $digests; powerShell = $PSVersionTable.PSVersion.ToString()
    os = [Environment]::OSVersion.ToString(); processArchitectureBits = ([IntPtr]::Size * 8)
    startedAt = [DateTime]::UtcNow.ToString('o'); endedAt = $null; softwarePass = $false
    realGuestExecuted = $false
    physicalCase = [ordered]@{ id = 'EDF-004-REAL-GUEST'; result = 'UNMEASURED'; reason = 'This focused lane validates source/generated guest contracts only; real QEMU/TCG/WHPX is reserved for separately labelled runtime qualification.' }
    tests = @(); failed = 0
}
try {
    foreach ($test in $tests) {
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $record = [ordered]@{ name = $test.Name; result = 'FAIL'; elapsedMilliseconds = 0; measurements = @(); error = $null }
        try {
            if ($test.SkipReason) { throw ('Mandatory EDF-004 focused case was skipped: ' + $test.SkipReason) }
            $messages = @(& $test.Body $test.Data 6>&1)
            foreach ($message in $messages) { Write-Host ([string]$message) }
            $record.measurements = @($messages | ForEach-Object { [string]$_ } | Where-Object { $_ -like 'EDF004_MEASUREMENT*' })
            $record.result = 'PASS'
            Write-Host ('PASS ' + $test.Name)
        }
        catch {
            $failureCount++
            $record.error = & (Get-Module EzDarkFactory) { param($text) Protect-EzDarkFactoryDiagnosticText -Text $text } $_.Exception.Message
            Write-Host ('FAIL ' + $test.Name + ': ' + $record.error)
            Write-Host $_.ScriptStackTrace
        }
        $record.elapsedMilliseconds = $clock.ElapsedMilliseconds
        $cases.Add([pscustomobject]$record)
    }
    foreach ($relative in $sourcePaths) {
        $after = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $script:EzDarkFactoryRepositoryRoot $relative)).Hash.ToLowerInvariant()
        if ($after -cne $digests[$relative]) { throw ('Source changed during qualification: ' + $relative) }
    }
    $dirty = @(git -C $script:EzDarkFactoryRepositoryRoot status --porcelain --untracked-files=normal)
    if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'Source checkout changed during qualification.' }
    $receipt.softwarePass = $failureCount -eq 0
}
finally {
    $receipt.tests = @($cases.ToArray())
    $receipt.failed = $failureCount
    $receipt.endedAt = [DateTime]::UtcNow.ToString('o')
    [void][IO.Directory]::CreateDirectory($OutputDirectory)
    $path = Join-Path $OutputDirectory ('edf004-powershell-' + $ExpectedMajor + '.json')
    [IO.File]::WriteAllText($path, (($receipt | ConvertTo-Json -Depth 10) + "`n"), [Text.UTF8Encoding]::new($false))
    Get-FileHash -Algorithm SHA256 -LiteralPath $path
    Write-Host ('EDF004_RESULT tests=' + $tests.Count + ';failures=' + $failureCount + ';realGuest=UNMEASURED;softwarePass=' + $receipt.softwarePass)
}
if (-not $receipt.softwarePass) { throw ('EDF-004 qualification failed: ' + $failureCount + ' focused case(s).') }
