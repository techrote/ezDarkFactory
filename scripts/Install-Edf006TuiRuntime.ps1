#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$DestinationRoot)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$lockPath = Join-Path $repositoryRoot 'manifests/edf006-tui-runtime.json'
$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json

if ($lock.schemaVersion -ne 1 -or $lock.runtimeId -cnotmatch '^edf006-[a-z0-9.-]+$') {
    throw 'Invalid EDF-006 TUI runtime lock schema/runtime ID.'
}
if ($lock.python.version -cne '3.12.10' -or $lock.python.architecture -cne 'win-x64' -or
    $lock.python.sha256 -cnotmatch '^[a-f0-9]{64}$') {
    throw 'Invalid pinned CPython runtime identity.'
}
if ($lock.framework.name -cne 'textual' -or $lock.framework.version -cne '8.2.8' -or
    $lock.framework.sourceCommit -cnotmatch '^[a-f0-9]{40}$') {
    throw 'Invalid pinned Textual framework identity.'
}
if ($lock.policy.allowSdist -or $lock.policy.allowPipResolution -or $lock.policy.syntaxExtras) {
    throw 'EDF-006 production TUI lock may not enable sdists, pip resolution, or syntax extras.'
}

if (-not [IO.Path]::IsPathRooted($DestinationRoot)) {
    throw 'DestinationRoot must be an explicit absolute portable workspace path.'
}
$destination = Get-Item -LiteralPath $DestinationRoot -Force
if ($destination -isnot [IO.DirectoryInfo]) { throw 'DestinationRoot must be an existing directory.' }
if (($destination.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'DestinationRoot may not be a reparse point/symlink.'
}
$repoPrefix = $repositoryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($destination.FullName -ieq $repositoryRoot -or $destination.FullName.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Install the generated TUI runtime outside the source repository.'
}

function Assert-Sha256([string]$Path, [string]$Expected) {
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $Expected.ToLowerInvariant()) {
        throw "SHA-256 mismatch for $([IO.Path]::GetFileName($Path)): expected $Expected, got $actual."
    }
}

function Invoke-DownloadOnce([string]$Uri, [string]$OutFile) {
    $parsed = [Uri]$Uri
    if ($parsed.Scheme -cne 'https') { throw "Refusing non-HTTPS acquisition: $Uri" }
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -TimeoutSec 120
}

function Expand-VerifiedZip([string]$Archive, [string]$Target) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Directory]::CreateDirectory($Target) | Out-Null
    $targetFull = [IO.Path]::GetFullPath($Target).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $prefix = $targetFull + [IO.Path]::DirectorySeparatorChar
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('/', [IO.Path]::DirectorySeparatorChar)
            if ([string]::IsNullOrEmpty($name)) { continue }
            if ([IO.Path]::IsPathRooted($name) -or $name -match '(^|[\\/])\.\.([\\/]|$)') {
                throw "Unsafe ZIP member in verified acquisition: $($entry.FullName)"
            }
            $out = [IO.Path]::GetFullPath((Join-Path $targetFull $name))
            if (-not $out.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "ZIP member escapes destination: $($entry.FullName)"
            }
            if ([string]::IsNullOrEmpty($entry.Name)) {
                [IO.Directory]::CreateDirectory($out) | Out-Null
                continue
            }
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($out)) | Out-Null
            $input = $entry.Open()
            try {
                $output = New-Object IO.FileStream($out, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try { $input.CopyTo($output) } finally { $output.Dispose() }
            }
            finally { $input.Dispose() }
        }
    }
    finally { $zip.Dispose() }
}

function Resolve-PinnedWheel([object]$Package) {
    if ($Package.filename -cnotmatch '-py3-none-any\.whl$' -or $Package.sha256 -cnotmatch '^[a-f0-9]{64}$') {
        throw "Package $($Package.name) is not an allowed pure-Python pinned wheel."
    }
    $metadataUri = 'https://pypi.org/pypi/' + [Uri]::EscapeDataString([string]$Package.name) + '/' + [Uri]::EscapeDataString([string]$Package.version) + '/json'
    $metadata = Invoke-RestMethod -Uri $metadataUri -TimeoutSec 60
    $matches = @($metadata.urls | Where-Object { $_.filename -ceq $Package.filename -and $_.packagetype -ceq 'bdist_wheel' })
    if ($matches.Count -ne 1) { throw "PyPI metadata did not yield exactly one pinned wheel for $($Package.name)." }
    $candidate = $matches[0]
    $uri = [Uri]$candidate.url
    if ($uri.Scheme -cne 'https' -or $uri.Host -cne [string]$lock.policy.wheelHost) {
        throw "Pinned wheel for $($Package.name) resolved outside the approved PyPI file host."
    }
    if ([string]$candidate.digests.sha256 -ine [string]$Package.sha256) {
        throw "PyPI metadata hash disagrees with the checked-in lock for $($Package.name)."
    }
    if ($candidate.yanked) { throw "Pinned wheel for $($Package.name) is yanked." }
    return [string]$candidate.url
}

$target = Join-Path $destination.FullName ('edf006-tui-' + [string]$lock.runtimeId)
if (Test-Path -LiteralPath $target) {
    throw "Refusing to overwrite existing TUI runtime: $target"
}
$work = $target + '.staging-' + [Guid]::NewGuid().ToString('N')
$runtime = Join-Path $work 'runtime'
$downloads = Join-Path $work 'downloads'
[IO.Directory]::CreateDirectory($runtime) | Out-Null
[IO.Directory]::CreateDirectory($downloads) | Out-Null

$oldTls = [Net.ServicePointManager]::SecurityProtocol
$ProgressPreference = 'SilentlyContinue'
try {
    [Net.ServicePointManager]::SecurityProtocol = $oldTls -bor [Net.SecurityProtocolType]::Tls12

    $pythonArchive = Join-Path $downloads ([string]$lock.python.filename)
    $pythonUri = [Uri][string]$lock.python.url
    if ($pythonUri.Host -cne 'www.python.org') { throw 'CPython runtime URL must remain on www.python.org.' }
    Invoke-DownloadOnce -Uri $pythonUri.AbsoluteUri -OutFile $pythonArchive
    Assert-Sha256 -Path $pythonArchive -Expected ([string]$lock.python.sha256)
    Expand-VerifiedZip -Archive $pythonArchive -Target $runtime

    $sitePackages = Join-Path $runtime 'Lib/site-packages'
    [IO.Directory]::CreateDirectory($sitePackages) | Out-Null
    foreach ($package in @($lock.packages)) {
        $wheelUri = Resolve-PinnedWheel $package
        $wheel = Join-Path $downloads ([string]$package.filename)
        Invoke-DownloadOnce -Uri $wheelUri -OutFile $wheel
        Assert-Sha256 -Path $wheel -Expected ([string]$package.sha256)
        Expand-VerifiedZip -Archive $wheel -Target $sitePackages
    }

    $pth = Join-Path $runtime 'python312._pth'
    if (-not (Test-Path -LiteralPath $pth -PathType Leaf)) { throw 'Verified embedded CPython is missing python312._pth.' }
    $pthContent = "python312.zip`r`n.`r`nLib/site-packages`r`nimport site`r`n"
    [IO.File]::WriteAllText($pth, $pthContent, (New-Object Text.UTF8Encoding($false)))

    $python = Join-Path $runtime 'python.exe'
    if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw 'Verified embedded CPython is missing python.exe.' }
    $identity = @(& $python -I -c 'import sys,textual; print(sys.version.split()[0]); print(textual.__version__)')
    if ($LASTEXITCODE -ne 0 -or $identity.Count -ne 2) { throw 'Verified TUI runtime failed its import/version probe.' }
    $pythonVersion = ([string]$identity[0]).Trim()
    $textualVersion = ([string]$identity[1]).Trim()
    if ($pythonVersion -cne [string]$lock.python.version -or $textualVersion -cne [string]$lock.framework.version) {
        throw "Installed runtime identity mismatch: python=$pythonVersion textual=$textualVersion"
    }

    Remove-Item -LiteralPath $downloads -Recurse -Force
    $receipt = [ordered]@{
        schemaVersion = 1
        runtimeId = [string]$lock.runtimeId
        python = [string]$lock.python.version
        textual = [string]$lock.framework.version
        frameworkSourceCommit = [string]$lock.framework.sourceCommit
        lockSha256 = (Get-FileHash -LiteralPath $lockPath -Algorithm SHA256).Hash.ToLowerInvariant()
    } | ConvertTo-Json -Depth 4
    [IO.File]::WriteAllText((Join-Path $runtime 'edf006-runtime.json'), $receipt + "`n", (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $runtime -Destination $target
    Remove-Item -LiteralPath $work -Recurse -Force
    Write-Host ('EDF-006 pinned TUI runtime verified: CPython {0}, Textual {1}.' -f $lock.python.version, $lock.framework.version)
    Write-Output (Join-Path $target 'python.exe')
}
catch {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    throw
}
finally {
    [Net.ServicePointManager]::SecurityProtocol = $oldTls
}
