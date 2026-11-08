#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$DestinationRoot)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$tooling = Get-Content -LiteralPath (Join-Path $repositoryRoot 'tests/tooling.json') -Raw | ConvertFrom-Json
$pin = $tooling.powerShell7
if ($pin.version -notmatch '^7\.[0-9]+\.[0-9]+$' -or $pin.sha256 -notmatch '^[a-fA-F0-9]{64}$') {
    throw 'The PowerShell test-runtime version or SHA-256 pin in tests/tooling.json is invalid.'
}
$expectedUrl = 'https://github.com/PowerShell/PowerShell/releases/download/v' + $pin.version + '/PowerShell-' + $pin.version + '-win-x64.zip'
if ($pin.url -cne $expectedUrl -or $pin.sizeBytes -le 0) {
    throw 'The PowerShell test runtime must use its exact official versioned Windows x64 ZIP and byte length.'
}
$destination = Get-Item -LiteralPath $DestinationRoot -Force
if ($destination -isnot [IO.DirectoryInfo]) { throw 'DestinationRoot must be an existing temporary directory.' }
$rootPrefix = $repositoryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($destination.FullName -ieq $repositoryRoot -or $destination.FullName.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Install the CI test runtime outside the repository, under RUNNER_TEMP.'
}

$target = Join-Path $destination.FullName ('ezdarkfactory-test-powershell-' + $pin.version + '-' + [Guid]::NewGuid().ToString('N'))
$archive = $target + '.zip'
$oldTls = [Net.ServicePointManager]::SecurityProtocol
$ProgressPreference = 'SilentlyContinue'
try {
    [Net.ServicePointManager]::SecurityProtocol = $oldTls -bor [Net.SecurityProtocolType]::Tls12
    # The SourceForge project is a third-party bit-for-bit mirror, not an
    # alternate package authority. Both transports MUST pass the SAME exact
    # upstream byte-length and SHA-256 checks before any extraction or execution.
    # A successful HTTP response with wrong bytes fails closed rather than
    # silently trying a different source (a supply-chain anomaly is not an outage).
    $mirrorUrl = 'https://downloads.sourceforge.net/project/powershell.mirror/v' + $pin.version + '/PowerShell-' + $pin.version + '-win-x64.zip'
    $sources = @(
        [pscustomobject]@{ Label = 'GitHub Releases'; Url = $pin.url; Attempts = 3 },
        [pscustomobject]@{ Label = 'SourceForge exact-version mirror'; Url = $mirrorUrl; Attempts = 2 }
    )
    $downloaded = $false
    $sourceLabel = ''
    foreach ($source in $sources) {
        for ($attempt = 1; $attempt -le $source.Attempts; $attempt++) {
            try {
                Invoke-WebRequest -Uri $source.Url -OutFile $archive -UseBasicParsing -TimeoutSec 60
                $downloaded = $true
                $sourceLabel = $source.Label
                break
            }
            catch {
                if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
                Write-Warning ('Pinned PowerShell transport unavailable: {0} attempt {1}/{2} ({3}).' -f $source.Label, $attempt, $source.Attempts, $_.Exception.GetType().Name)
                if ($attempt -lt $source.Attempts) { Start-Sleep -Seconds 2 }
            }
        }
        if ($downloaded) { break }
    }
    if (-not $downloaded) {
        throw 'Could not acquire the pinned PowerShell test runtime via either bounded, fixed-version transport. No unverified payload was used.'
    }
    if ((Get-Item -LiteralPath $archive).Length -ne $pin.sizeBytes) {
        throw 'The PowerShell test-runtime download has the wrong byte length. No payload was extracted or executed.'
    }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $pin.sha256) {
        throw 'The PowerShell test-runtime SHA-256 does not match tests/tooling.json. No payload was extracted or executed.'
    }
    Expand-Archive -LiteralPath $archive -DestinationPath $target
    $executable = Join-Path $target 'pwsh.exe'
    $version = @(& $executable -NoLogo -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()') -join ''
    if ($LASTEXITCODE -ne 0 -or $version -cne $pin.version) {
        throw "The verified PowerShell payload did not execute as version $($pin.version)."
    }
    Write-Host ('Verified PowerShell {0} test runtime via {1} (official SHA-256 {2}).' -f $pin.version, $sourceLabel, $pin.sha256)
    Write-Output $executable
}
catch {
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    throw
}
finally {
    [Net.ServicePointManager]::SecurityProtocol = $oldTls
    if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
}
