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
    # All transports are untrusted byte couriers for the SAME upstream ZIP.
    # A returned HTML/error page or a corrupt archive must never be extracted.
    # Reject that candidate before trying another explicitly reviewed transport.
    # Asset 551207033 is the official v7.6.6 win-x64 ZIP as published by
    # PowerShell/PowerShell; updating the PowerShell pin requires reviewing it.
    if ($pin.version -cne '7.6.6') {
        throw 'Review the official REST asset ID when changing the PowerShell CI pin.'
    }
    $apiAssetUrl = 'https://api.github.com/repos/PowerShell/PowerShell/releases/assets/551207033'
    $mirrorUrl = 'https://downloads.sourceforge.net/project/powershell.mirror/v' + $pin.version + '/PowerShell-' + $pin.version + '-win-x64.zip'
    $directMirrorUrl = 'https://master.dl.sourceforge.net/project/powershell.mirror/v' + $pin.version + '/PowerShell-' + $pin.version + '-win-x64.zip'
    $sources = @(
        [pscustomobject]@{ Label = 'GitHub Releases'; Url = $pin.url; Attempts = 2; Api = $false },
        [pscustomobject]@{ Label = 'Official GitHub REST asset'; Url = $apiAssetUrl; Attempts = 2; Api = $true },
        [pscustomobject]@{ Label = 'SourceForge routed mirror'; Url = $mirrorUrl; Attempts = 2; Api = $false },
        [pscustomobject]@{ Label = 'SourceForge direct mirror'; Url = $directMirrorUrl; Attempts = 1; Api = $false }
    )
    $downloaded = $false
    $sourceLabel = ''
    foreach ($source in $sources) {
        for ($attempt = 1; $attempt -le $source.Attempts; $attempt++) {
            try {
                $request = @{
                    Uri = $source.Url
                    OutFile = $archive
                    UseBasicParsing = $true
                    TimeoutSec = 35
                }
                if ($source.Api) {
                    $request.Headers = @{
                        Accept = 'application/octet-stream'
                        'User-Agent' = 'ezDarkFactory-pinned-ci'
                    }
                }
                Invoke-WebRequest @request
                if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
                    throw 'The selected transport returned no archive.'
                }
                if ((Get-Item -LiteralPath $archive).Length -ne $pin.sizeBytes) {
                    Write-Warning ('Rejected nonmatching PowerShell transport bytes ({0}, length).' -f $source.Label)
                    continue
                }
                if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $pin.sha256) {
                    Write-Warning ('Rejected nonmatching PowerShell transport bytes ({0}, SHA-256).' -f $source.Label)
                    continue
                }
                $downloaded = $true
                $sourceLabel = $source.Label
                break
            }
            catch {
                Write-Warning ('Pinned PowerShell transport unavailable: {0} attempt {1}/{2} ({3}).' -f $source.Label, $attempt, $source.Attempts, $_.Exception.GetType().Name)
                if ($attempt -lt $source.Attempts) { Start-Sleep -Seconds 2 }
            }
            finally {
                if (-not $downloaded -and (Test-Path -LiteralPath $archive)) {
                    Remove-Item -LiteralPath $archive -Force
                }
            }
        }
        if ($downloaded) { break }
    }
    if (-not $downloaded) {
        throw 'Could not acquire the byte-length and SHA-256 verified pinned PowerShell test runtime from any reviewed transport. No unverified payload was executed.'
    }
    # Defensive recheck immediately before extraction; every transport is
    # required to satisfy the immutable official length and checksum.
    if ((Get-Item -LiteralPath $archive).Length -ne $pin.sizeBytes -or
        (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $pin.sha256) {
        throw 'Verified PowerShell archive changed before extraction; refusing execution.'
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
