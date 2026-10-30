function Get-EzDarkFactoryObjectProperty {
    param([AllowNull()][object]$Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Invoke-EzDarkFactoryBaseQemuImg {
    param(
        [string]$Root,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [scriptblock]$Runner,
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = 600
    )

    if ($null -ne $Runner) {
        $result = & $Runner $ArgumentList
        if ($null -eq $result -or $null -eq $result.PSObject.Properties['ExitCode']) {
            throw 'qemu-img test runner must return ExitCode, StdOut and StdErr.'
        }
        if ([int]$result.ExitCode -ne 0) {
            throw "qemu-img fixture failed with exit code $($result.ExitCode): $($result.StdErr)"
        }
        return $result
    }

    $tool = Get-EzDarkFactoryQemuToolPath -Name 'qemu-img.exe' -Root $Root
    return Invoke-EzDarkFactoryProcess -FilePath $tool -ArgumentList $ArgumentList -WorkingDirectory (Split-Path -Parent $tool) -TimeoutSeconds $TimeoutSeconds -ThrowOnError
}

function Get-EzDarkFactoryQemuImageInfo {
    param([string]$Root, [string]$Path, [scriptblock]$Runner)

    $result = Invoke-EzDarkFactoryBaseQemuImg -Root $Root -ArgumentList @('info', '--output=json', $Path) -Runner $Runner
    try { return $result.StdOut | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "qemu-img returned invalid JSON while inspecting '$Path': $($_.Exception.Message)" }
}

function Assert-EzDarkFactoryStandaloneQcow2 {
    param([object]$Info, [string]$Description)

    if ((Get-EzDarkFactoryObjectProperty $Info 'format') -cne 'qcow2') {
        throw "$Description must be qcow2."
    }
    $backing = Get-EzDarkFactoryObjectProperty $Info 'backing-filename'
    if (-not [string]::IsNullOrWhiteSpace([string]$backing)) {
        throw "$Description must be standalone with no backing file; found '$backing'."
    }
    $virtualSize = Get-EzDarkFactoryObjectProperty $Info 'virtual-size'
    if ($null -eq $virtualSize -or [long]$virtualSize -le 0) {
        throw "$Description must report a positive virtual size."
    }
}

function New-EzDarkFactoryBaseStagingDisk {
    [CmdletBinding()]
    param(
        [string]$Root = $script:EzDarkFactoryDefaultRoot,
        [Parameter(Mandatory = $true)][string]$SourceImage,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][ValidateRange(8, 256)][int]$VirtualSizeGiB,
        [scriptblock]$QemuImgRunner
    )

    $sourceInfo = Get-EzDarkFactoryQemuImageInfo -Root $Root -Path $SourceImage -Runner $QemuImgRunner
    Assert-EzDarkFactoryStandaloneQcow2 -Info $sourceInfo -Description 'Verified Ubuntu source image'

    $null = Invoke-EzDarkFactoryBaseQemuImg -Root $Root -ArgumentList @(
        'create', '-f', 'qcow2', '-F', 'qcow2', '-b', [IO.Path]::GetFullPath($SourceImage), [IO.Path]::GetFullPath($Destination)
    ) -Runner $QemuImgRunner
    $null = Invoke-EzDarkFactoryBaseQemuImg -Root $Root -ArgumentList @(
        'resize', [IO.Path]::GetFullPath($Destination), ($VirtualSizeGiB.ToString() + 'G')
    ) -Runner $QemuImgRunner

    $info = Get-EzDarkFactoryQemuImageInfo -Root $Root -Path $Destination -Runner $QemuImgRunner
    if ((Get-EzDarkFactoryObjectProperty $info 'format') -cne 'qcow2') {
        throw 'Prepared-base staging image is not qcow2.'
    }
    if ([string]::IsNullOrWhiteSpace([string](Get-EzDarkFactoryObjectProperty $info 'backing-filename'))) {
        throw 'Prepared-base staging image lost its verified source backing file.'
    }
    return $info
}

function Convert-EzDarkFactoryBaseToStandalone {
    [CmdletBinding()]
    param(
        [string]$Root = $script:EzDarkFactoryDefaultRoot,
        [Parameter(Mandatory = $true)][string]$StagingDisk,
        [Parameter(Mandatory = $true)][string]$Destination,
        [scriptblock]$QemuImgRunner
    )

    $null = Invoke-EzDarkFactoryBaseQemuImg -Root $Root -ArgumentList @(
        'convert', '-f', 'qcow2', '-O', 'qcow2', [IO.Path]::GetFullPath($StagingDisk), [IO.Path]::GetFullPath($Destination)
    ) -Runner $QemuImgRunner -TimeoutSeconds 1800

    $info = Get-EzDarkFactoryQemuImageInfo -Root $Root -Path $Destination -Runner $QemuImgRunner
    Assert-EzDarkFactoryStandaloneQcow2 -Info $info -Description 'Prepared base'
    $null = Invoke-EzDarkFactoryBaseQemuImg -Root $Root -ArgumentList @(
        'check', '--output=json', '-f', 'qcow2', [IO.Path]::GetFullPath($Destination)
    ) -Runner $QemuImgRunner -TimeoutSeconds 1800
    return $info
}

function Start-EzDarkFactoryBaseQemuProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = Resolve-EzDarkFactoryProcessFileSystemPath -Path $FilePath
    $startInfo.WorkingDirectory = Resolve-EzDarkFactoryProcessFileSystemPath -Path $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $startInfo.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
    if ($null -ne $startInfo.PSObject.Properties['ArgumentList']) {
        foreach ($argument in $ArgumentList) { $startInfo.ArgumentList.Add($argument) }
    }
    else {
        $escaped = New-Object 'System.Collections.Generic.List[string]'
        foreach ($argument in $ArgumentList) {
            $escaped.Add((ConvertTo-EzDarkFactoryWindowsArgument -Argument $argument))
        }
        $startInfo.Arguments = [string]::Join(' ', $escaped.ToArray())
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $started = $false
    try {
        Start-EzDarkFactoryProcessWithoutInputPreamble -Process $process -TimeoutMilliseconds 30000 -Started ([ref]$started)
        if (-not $started) { throw 'The operating system did not create the QEMU process.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.BaseStream.Close()
        return [pscustomobject]@{
            Process = $process
            StdOutTask = $stdoutTask
            StdErrTask = $stderrTask
        }
    }
    catch {
        if ($started) { try { $process.Kill() } catch { } }
        $process.Dispose()
        throw
    }
}

function Stop-EzDarkFactoryBaseQemuProcess {
    param([AllowNull()][object]$Handle)
    if ($null -eq $Handle) { return }
    try {
        if (-not $Handle.Process.HasExited) {
            $null = Stop-EzDarkFactoryTimedOutProcess -Process $Handle.Process
        }
    }
    catch { }
}

function Complete-EzDarkFactoryBaseQemuProcess {
    param([Parameter(Mandatory = $true)][object]$Handle)

    if (-not $Handle.Process.HasExited) {
        throw 'QEMU process is still running and cannot be completed.'
    }
    if (-not $Handle.StdOutTask.Wait(5000) -or -not $Handle.StdErrTask.Wait(5000)) {
        throw 'QEMU exited but its output streams did not drain.'
    }
    return [pscustomobject]@{
        ExitCode = $Handle.Process.ExitCode
        StdOut = $Handle.StdOutTask.Result
        StdErr = $Handle.StdErrTask.Result
    }
}

function Read-EzDarkFactorySharedTextTail {
    param([Parameter(Mandatory = $true)][string]$Path, [int]$MaxBytes = 2097152)

    if (-not [IO.File]::Exists($Path)) { return '' }
    $stream = $null
    $reader = $null
    try {
        $stream = New-Object IO.FileStream(
            $Path, [IO.FileMode]::Open, [IO.FileAccess]::Read,
            ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        if ($stream.Length -gt $MaxBytes) { $stream.Seek(-$MaxBytes, [IO.SeekOrigin]::End) | Out-Null }
        $reader = New-Object IO.StreamReader($stream, (New-Object Text.UTF8Encoding($false, $false)), $true, 4096, $true)
        return $reader.ReadToEnd()
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-EzDarkFactorySerialMarker {
    param([string]$Text, [string]$Name)
    $match = [regex]::Matches($Text, '(?m)^' + [regex]::Escape($Name) + '=(?<value>[^\r\n]*)\r?$')
    if ($match.Count -eq 0) { return $null }
    return $match[$match.Count - 1].Groups['value'].Value
}

function ConvertFrom-EzDarkFactoryMarkerBase64 {
    param([AllowNull()][string]$Value, [string]$Description)
    if ($null -eq $Value) { throw "Guest provisioning did not report $Description." }
    try { return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value)) }
    catch { throw "Guest provisioning reported invalid base64 for $Description." }
}

function Get-EzDarkFactoryBaseGuestFacts {
    param([string]$SerialText, [string]$BuildId)

    if ((Get-EzDarkFactorySerialMarker $SerialText 'EDF_BASE_READY') -cne '1') {
        throw 'Guest provisioning did not emit the explicit prepared-base READY marker.'
    }
    if ((Get-EzDarkFactorySerialMarker $SerialText 'EDF_BASE_TOOLS_OK') -cne '1') {
        throw 'Guest provisioning did not prove the baseline tool validation succeeded.'
    }
    if ((Get-EzDarkFactorySerialMarker $SerialText 'EDF_BASE_CLEAN_OK') -cne '1') {
        throw 'Guest provisioning did not prove cloud-init and identity cleanup succeeded.'
    }
    if ((Get-EzDarkFactorySerialMarker $SerialText 'EDF_BASE_BUILD_ID') -cne $BuildId) {
        throw 'Guest provisioning READY marker belongs to a different build identity.'
    }

    return [pscustomobject][ordered]@{
        OsId = ConvertFrom-EzDarkFactoryMarkerBase64 (Get-EzDarkFactorySerialMarker $SerialText 'EDF_BASE_OS_ID_B64') 'guest OS ID'
        OsVersion = ConvertFrom-EzDarkFactoryMarkerBase64 (Get-EzDarkFactorySerialMarker $SerialText 'EDF_BASE_OS_VERSION_B64') 'guest OS version'
        CloudInitVersion = ConvertFrom-EzDarkFactoryMarkerBase64 (Get-EzDarkFactorySerialMarker $SerialText 'EDF_BASE_CLOUD_INIT_B64') 'cloud-init version'
        ToolsValidated = $true
        IdentityCleaned = $true
    }
}

function Invoke-EzDarkFactoryBaseProvisioningVm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$QemuSystem,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][object]$SeedServer,
        [Parameter(Mandatory = $true)][string]$SerialLog,
        [Parameter(Mandatory = $true)][string]$BuildId,
        [ValidateRange(30, 86400)][int]$TimeoutSeconds = 2700
    )

    if (Test-Path -LiteralPath $SerialLog) { Remove-Item -LiteralPath $SerialLog -Force }
    $handle = $null
    try {
        $handle = Start-EzDarkFactoryBaseQemuProcess -FilePath $QemuSystem -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        $serialText = ''
        while ([DateTime]::UtcNow -lt $deadline) {
            $null = Invoke-EzDarkFactorySeedServerPending -Server $SeedServer -MaxRequests 8
            $serialText = Read-EzDarkFactorySharedTextTail -Path $SerialLog

            $failure = Get-EzDarkFactorySerialMarker $serialText 'EDF_BASE_FAILURE_B64'
            if ($null -ne $failure) {
                $detail = ConvertFrom-EzDarkFactoryMarkerBase64 $failure 'guest provisioning failure'
                throw "Guest baseline validation failed: $detail"
            }
            if ($handle.Process.HasExited) { break }
            Start-Sleep -Milliseconds 100
        }

        if (-not $handle.Process.HasExited) {
            Stop-EzDarkFactoryBaseQemuProcess -Handle $handle
            $paths = @($SeedServer.RequestPaths.ToArray())
            $pathSummary = if ($paths.Count -eq 0) { 'none' } else { ($paths -join ', ') }
            throw "Prepared-base guest provisioning exceeded its $TimeoutSeconds second timeout. Seed requests handled: $($SeedServer.RequestCount); paths: $pathSummary."
        }

        $result = Complete-EzDarkFactoryBaseQemuProcess -Handle $handle
        $serialText = Read-EzDarkFactorySharedTextTail -Path $SerialLog
        if ($result.ExitCode -ne 0) {
            $detail = $result.StdErr.Trim()
            if ($detail.Length -gt 2048) { $detail = $detail.Substring(0, 2048) + '...' }
            throw "QEMU exited with code $($result.ExitCode) before a prepared base could be accepted. $detail"
        }
        return Get-EzDarkFactoryBaseGuestFacts -SerialText $serialText -BuildId $BuildId
    }
    finally {
        if ($null -ne $handle) {
            Stop-EzDarkFactoryBaseQemuProcess -Handle $handle
            $handle.Process.Dispose()
        }
    }
}

function Assert-EzDarkFactoryPreparedBaseManifest {
    param([object]$Manifest)

    if ((Get-EzDarkFactoryObjectProperty $Manifest 'schemaVersion') -eq 2) {
        Assert-EzDarkFactorySnapshotBaseManifest -Manifest $Manifest
        return
    }
    Assert-EzDarkFactoryJsonSchema -Value $Manifest -SchemaVersion 1 -Description 'Prepared-base manifest'
    Assert-EzDarkFactoryBaseRecipeFields -Value $Manifest -Expected @(
        'schemaVersion', 'baseId', 'baseSha256', 'virtualSizeBytes', 'builtAt',
        'source', 'provisioning', 'qemu', 'guest', 'build'
    ) -Description 'Prepared-base manifest'
    if ($Manifest.baseId -isnot [string] -or $Manifest.baseId -cnotmatch '^base-[a-f0-9]{64}$') {
        throw 'Prepared-base manifest baseId is invalid.'
    }
    Assert-EzDarkFactoryArtifactDigest -Algorithm SHA256 -ExpectedDigest $Manifest.baseSha256
    if ($Manifest.baseId -cne ('base-' + $Manifest.baseSha256)) {
        throw 'Prepared-base ID must be content-addressed by the complete base SHA-256.'
    }
    $size = $Manifest.virtualSizeBytes
    $integer = $size -is [int] -or $size -is [long] -or $size -is [uint32] -or $size -is [uint64]
    if (-not $integer -or [long]$size -le 0) { throw 'Prepared-base virtualSizeBytes must be positive.' }
    if ($Manifest.builtAt -isnot [string] -or [string]::IsNullOrWhiteSpace($Manifest.builtAt)) {
        throw 'Prepared-base builtAt must be an ISO timestamp string.'
    }

    Assert-EzDarkFactoryBaseRecipeFields -Value $Manifest.source -Expected @(
        'manifestSha256', 'imageSha256', 'publication', 'filename'
    ) -Description 'Prepared-base source provenance'
    Assert-EzDarkFactoryArtifactDigest -Algorithm SHA256 -ExpectedDigest $Manifest.source.manifestSha256
    Assert-EzDarkFactoryArtifactDigest -Algorithm SHA256 -ExpectedDigest $Manifest.source.imageSha256

    Assert-EzDarkFactoryBaseRecipeFields -Value $Manifest.provisioning -Expected @(
        'recipeVersion', 'digest'
    ) -Description 'Prepared-base provisioning provenance'
    Assert-EzDarkFactoryArtifactDigest -Algorithm SHA256 -ExpectedDigest $Manifest.provisioning.digest

    Assert-EzDarkFactoryBaseRecipeFields -Value $Manifest.qemu -Expected @(
        'manifestSha256', 'qemuSystemVersion', 'qemuImgVersion', 'providerBuild'
    ) -Description 'Prepared-base QEMU provenance'
    Assert-EzDarkFactoryArtifactDigest -Algorithm SHA256 -ExpectedDigest $Manifest.qemu.manifestSha256

    Assert-EzDarkFactoryBaseRecipeFields -Value $Manifest.guest -Expected @(
        'osId', 'osVersion', 'cloudInitVersion', 'baselineToolsValidated', 'identityCleaned'
    ) -Description 'Prepared-base guest provenance'
    if ($Manifest.guest.baselineToolsValidated -ne $true -or $Manifest.guest.identityCleaned -ne $true) {
        throw 'Prepared-base guest provenance must prove tool validation and identity cleanup.'
    }

    Assert-EzDarkFactoryBaseRecipeFields -Value $Manifest.build -Expected @(
        'accelerator', 'machine', 'firmwareCode', 'firmwareVariablesTemplate'
    ) -Description 'Prepared-base build provenance'
    if (@('whpx', 'tcg') -cnotcontains $Manifest.build.accelerator) {
        throw 'Prepared-base build accelerator must be whpx or tcg.'
    }
}

function Read-EzDarkFactoryPreparedBaseManifest {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ((Get-Item -LiteralPath $Path -Force -ErrorAction Stop).Length -gt 65536) {
        throw 'Base provenance manifest exceeds the supported 64-KiB bound.'
    }
    $text = (Read-EzDarkFactoryBoundedText -Path $Path)
    try { $probe = $text | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "Base provenance manifest is malformed JSON: $($_.Exception.Message)" }
    $version = Get-EzDarkFactoryObjectProperty $probe 'schemaVersion'
    Assert-EzDarkFactoryRuntimeInteger -Value $version -Description 'Base manifest schemaVersion' -Minimum 1 -Maximum 2
    $manifest = ConvertFrom-EzDarkFactoryJsonText -Text $text -SchemaVersion ([int]$version) -Description "Base provenance '$Path'"
    Assert-EzDarkFactoryPreparedBaseManifest -Manifest $manifest
    return $manifest
}

function Test-EzDarkFactoryPreparedBaseDirectory {
    param(
        [string]$Root,
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$BaseId,
        [scriptblock]$QemuImgRunner
    )

    if ($BaseId -cnotmatch '^base-[a-f0-9]{64}$') { throw "Invalid prepared-base ID '$BaseId'." }
    $paths = Get-EzDarkFactoryPaths -Root $Root
    $directoryPath = [IO.Path]::GetFullPath($Directory)
    $basesPath = [IO.Path]::GetFullPath($paths.Bases)
    $comparison = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        [StringComparison]::OrdinalIgnoreCase
    } else {
        [StringComparison]::Ordinal
    }
    $prefix = $basesPath.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $directoryPath.StartsWith($prefix, $comparison)) {
        throw "Prepared-base candidate directory escapes the managed base root: '$directoryPath'."
    }
    if (-not (Test-Path -LiteralPath $directoryPath -PathType Container)) {
        throw "Prepared-base candidate directory does not exist: '$directoryPath'."
    }
    $null = Assert-EzDarkFactoryStorageManagedPath -Path $directoryPath -ContainmentRoot $paths.Bases -SafetyRoot $paths.Root -Description 'Prepared-base candidate directory' -RequireDirectory

    $image = Join-Path $directoryPath 'base.qcow2'
    $manifestPath = Join-Path $directoryPath 'manifest.json'
    if (-not (Test-Path -LiteralPath $image -PathType Leaf) -or -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Prepared base '$BaseId' is incomplete. Expected base.qcow2 and manifest.json."
    }
    foreach ($path in @($image, $manifestPath)) {
        if ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Prepared-base image and manifest must not be reparse points.'
        }
    }

    $manifest = Read-EzDarkFactoryPreparedBaseManifest -Path $manifestPath
    if ($manifest.baseId -cne $BaseId) { throw 'Prepared-base directory identity does not match its manifest.' }
    $observed = Get-EzDarkFactoryFileDigest -Path $image -Algorithm SHA256
    if ($observed -cne $manifest.baseSha256) { throw 'Prepared-base content digest does not match its manifest.' }

    if ($manifest.schemaVersion -eq 2) {
        $null = Test-EzDarkFactoryQcow2Header -Path $image
        if (((Get-Item -LiteralPath $manifestPath -Force).Attributes -band [IO.FileAttributes]::ReadOnly) -eq 0) {
            throw 'Snapshot-base provenance manifest is not marked read-only.'
        }
    }
    $info = Get-EzDarkFactoryQemuImageInfo -Root $Root -Path $image -Runner $QemuImgRunner
    Assert-EzDarkFactoryStandaloneQcow2 -Info $info -Description "Prepared base '$BaseId'"
    if ([long](Get-EzDarkFactoryObjectProperty $info 'virtual-size') -ne [long]$manifest.virtualSizeBytes) {
        throw 'Prepared-base virtual size does not match its manifest.'
    }
    if ((Get-Item -LiteralPath $image -Force).Attributes -band [IO.FileAttributes]::ReadOnly) {
        $readOnly = $true
    }
    else {
        throw 'Prepared-base image is not marked read-only by the immutable-base contract.'
    }

    return [pscustomobject][ordered]@{
        BaseId = $BaseId
        Directory = $directoryPath
        Image = $image
        ManifestPath = $manifestPath
        Manifest = $manifest
        ReadOnly = $readOnly
    }
}

function Test-EzDarkFactoryPreparedBase {
    [CmdletBinding()]
    param(
        [string]$Root = $script:EzDarkFactoryDefaultRoot,
        [Parameter(Mandatory = $true)][string]$BaseId,
        [scriptblock]$QemuImgRunner
    )

    $paths = Get-EzDarkFactoryPaths -Root $Root
    return Test-EzDarkFactoryPreparedBaseDirectory -Root $Root -Directory (Join-Path $paths.Bases $BaseId) -BaseId $BaseId -QemuImgRunner $QemuImgRunner
}

function Write-EzDarkFactoryBaseFailureEvidence {
    param([string]$StagingDirectory, [string]$BuildId, [object]$Failure)

    if (-not (Test-Path -LiteralPath $StagingDirectory -PathType Container)) { return }
    try {
        $value = [pscustomobject][ordered]@{
            schemaVersion = 1
            buildId = $BuildId
            failedAt = [DateTime]::UtcNow.ToString('o')
            message = (Protect-EzDarkFactoryDiagnosticText -Text $Failure.Exception.Message)
        }
        Write-EzDarkFactoryJson -Path (Join-Path $StagingDirectory 'failure.json') -Value $value -SchemaVersion 1
    }
    catch { }
}

function Invoke-EzDarkFactoryBaseBuild {
    [CmdletBinding()]
    param(
        [string]$Root = $script:EzDarkFactoryDefaultRoot,
        [ValidateSet('whpx', 'tcg')][string]$Accelerator = 'whpx',
        [ValidateRange(30, 86400)][int]$BuildTimeoutSeconds = 2700,
        [scriptblock]$QemuStatusProvider,
        [scriptblock]$SourceProvider,
        [scriptblock]$QemuImgRunner,
        [scriptblock]$GuestRunner
    )

    $paths = Get-EzDarkFactoryPaths -Root $Root
    $qemuManifest = Get-EzDarkFactoryQemuManifest -Root $Root
    $qemuManifestDigest = Get-EzDarkFactoryFileDigest -Path $paths.QemuManifest -Algorithm SHA256
    $qemuStatus = if ($null -ne $QemuStatusProvider) {
        & $QemuStatusProvider $Root $qemuManifest
    }
    else {
        Get-EzDarkFactoryManagedQemuStatus -Root $Root -Manifest $qemuManifest -ManifestPath $paths.QemuManifest
    }
    if ($null -eq $qemuStatus -or -not $qemuStatus.Valid) {
        $reason = if ($null -ne $qemuStatus) { $qemuStatus.Reason } else { 'No managed QEMU status was returned.' }
        throw "Prepared-base build requires a validated managed QEMU runtime. $reason Run '.\ezdarkfactory.ps1 bootstrap' and retry."
    }

    $sourceManifest = Get-EzDarkFactorySourceImageManifest -Root $Root
    $sourceManifestDigest = Get-EzDarkFactoryFileDigest -Path $paths.UbuntuManifest -Algorithm SHA256
    $source = if ($null -ne $SourceProvider) { & $SourceProvider $Root $sourceManifest } else { Get-EzDarkFactoryVerifiedSourceImage -Root $Root }
    if ($null -eq $source -or -not $source.path -or -not (Test-Path -LiteralPath $source.path -PathType Leaf)) {
        throw "Prepared-base build requires the verified Ubuntu source image. Run '.\ezdarkfactory.ps1 base acquire' and retry."
    }
    $sourceDigest = Get-EzDarkFactoryFileDigest -Path $source.path -Algorithm SHA256
    if ($sourceDigest -cne $sourceManifest.sha256) {
        throw 'Ubuntu source image changed after acquisition and no longer matches the reviewed manifest.'
    }

    $recipe = Get-EzDarkFactoryBaseRecipe -Root $Root
    $buildId = [Guid]::NewGuid().ToString('N')
    $null = Assert-EzDarkFactorySafePath -Path $paths.Bases -Description 'Managed directory'
    [void][IO.Directory]::CreateDirectory($paths.Bases)
    $stage = Join-Path $paths.Bases ('.build-' + $buildId)
    $null = Assert-EzDarkFactorySafePath -Path $stage -Description 'Managed directory'
    [void][IO.Directory]::CreateDirectory($stage)
    $seedDirectory = Join-Path $stage 'seed'
    $null = Assert-EzDarkFactorySafePath -Path $seedDirectory -Description 'Managed directory'
    [void][IO.Directory]::CreateDirectory($seedDirectory)
    $seedServer = $null
    $publish = $null

    try {
        $seed = New-EzDarkFactoryBaseSeedData -Root $Root -BuildId $buildId
        $utf8 = New-Object Text.UTF8Encoding($false)
        [IO.File]::WriteAllText((Join-Path $seedDirectory 'user-data'), $seed.UserData, $utf8)
        [IO.File]::WriteAllText((Join-Path $seedDirectory 'meta-data'), $seed.MetaData, $utf8)

        $firmware = Get-EzDarkFactoryBaseFirmwarePaths -Root $Root -StagingDirectory $stage
        $stagingDisk = Join-Path $stage 'staging.qcow2'
        $null = New-EzDarkFactoryBaseStagingDisk -Root $Root -SourceImage $source.path -Destination $stagingDisk -VirtualSizeGiB $recipe.virtualSizeGiB -QemuImgRunner $QemuImgRunner

        $serialLog = Join-Path $stage 'serial.log'
        $seedServer = Start-EzDarkFactorySeedServer -UserData $seed.UserData -MetaData $seed.MetaData -TimeoutSeconds $BuildTimeoutSeconds
        try {
            $command = New-EzDarkFactoryBaseQemuArguments -BuildId $buildId -Recipe $recipe -StagingDisk $stagingDisk -FirmwareCode $firmware.Code -FirmwareVariables $firmware.Variables -SerialLog $serialLog -SeedHostPort $seedServer.Port -Accelerator $Accelerator
            $context = [pscustomobject][ordered]@{
                Root = $Root
                BuildId = $buildId
                QemuSystem = $qemuStatus.QemuSystem
                Arguments = $command.Arguments
                SeedServer = $seedServer
                SeedUrl = $command.SeedUrl
                GuestForward = $command.GuestForward
                SerialLog = $serialLog
                StagingDisk = $stagingDisk
                Accelerator = $Accelerator
                TimeoutSeconds = $BuildTimeoutSeconds
            }
            $guestFacts = if ($null -ne $GuestRunner) {
                & $GuestRunner $context
            }
            else {
                Invoke-EzDarkFactoryBaseProvisioningVm -QemuSystem $context.QemuSystem -ArgumentList $context.Arguments -WorkingDirectory $paths.Qemu -SeedServer $seedServer -SerialLog $serialLog -BuildId $buildId -TimeoutSeconds $BuildTimeoutSeconds
            }
        }
        finally {
            if ($null -ne $seedServer) {
                Stop-EzDarkFactorySeedServer -Server $seedServer
                $seedServer = $null
            }
        }

        if ($null -eq $guestFacts -or $guestFacts.ToolsValidated -ne $true -or $guestFacts.IdentityCleaned -ne $true) {
            throw 'Guest provisioning did not return validated tool and identity-cleanup evidence.'
        }

        $flat = Join-Path $stage 'base-flat.qcow2'
        $flatInfo = Convert-EzDarkFactoryBaseToStandalone -Root $Root -StagingDisk $stagingDisk -Destination $flat -QemuImgRunner $QemuImgRunner
        if (-not (Test-Path -LiteralPath $flat -PathType Leaf)) {
            throw 'qemu-img flattening did not produce the prepared-base file.'
        }

        $baseDigest = Get-EzDarkFactoryFileDigest -Path $flat -Algorithm SHA256
        $baseId = 'base-' + $baseDigest
        $virtualSize = [long](Get-EzDarkFactoryObjectProperty $flatInfo 'virtual-size')
        $manifest = [pscustomobject][ordered]@{
            schemaVersion = 1
            baseId = $baseId
            baseSha256 = $baseDigest
            virtualSizeBytes = $virtualSize
            builtAt = [DateTime]::UtcNow.ToString('o')
            source = [pscustomobject][ordered]@{
                manifestSha256 = $sourceManifestDigest
                imageSha256 = $sourceDigest
                publication = [string]$sourceManifest.publication
                filename = [string]$sourceManifest.filename
            }
            provisioning = [pscustomobject][ordered]@{
                recipeVersion = [string]$recipe.recipeVersion
                digest = [string]$seed.ProvisioningDigest
            }
            qemu = [pscustomobject][ordered]@{
                manifestSha256 = $qemuManifestDigest
                qemuSystemVersion = [string]$qemuStatus.QemuSystemVersion
                qemuImgVersion = [string]$qemuStatus.QemuImgVersion
                providerBuild = [string]$qemuManifest.qemu.providerBuild
            }
            guest = [pscustomobject][ordered]@{
                osId = [string]$guestFacts.OsId
                osVersion = [string]$guestFacts.OsVersion
                cloudInitVersion = [string]$guestFacts.CloudInitVersion
                baselineToolsValidated = $true
                identityCleaned = $true
            }
            build = [pscustomobject][ordered]@{
                accelerator = $Accelerator
                machine = [string]$recipe.machine
                firmwareCode = $firmware.CodeName
                firmwareVariablesTemplate = $firmware.VariablesTemplateName
            }
        }
        Assert-EzDarkFactoryPreparedBaseManifest -Manifest $manifest

        $publish = Join-Path $paths.Bases ('.publish-' + [Guid]::NewGuid().ToString('N'))
        $null = Assert-EzDarkFactorySafePath -Path $publish -Description 'Managed directory'
        [void][IO.Directory]::CreateDirectory($publish)
        $publishImage = Join-Path $publish 'base.qcow2'
        [IO.File]::Move($flat, $publishImage)
        $publishManifest = Join-Path $publish 'manifest.json'
        Write-EzDarkFactoryJson -Path $publishManifest -Value $manifest -SchemaVersion 1

        $imageAttributes = (Get-Item -LiteralPath $publishImage -Force).Attributes -bor [IO.FileAttributes]::ReadOnly
        [IO.File]::SetAttributes($publishImage, $imageAttributes)
        $manifestAttributes = (Get-Item -LiteralPath $publishManifest -Force).Attributes -bor [IO.FileAttributes]::ReadOnly
        [IO.File]::SetAttributes($publishManifest, $manifestAttributes)

        # Fully validate the read-only candidate while it is still non-authoritative.
        # The subsequent same-volume rename is the publication commit point.
        $candidate = Test-EzDarkFactoryPreparedBaseDirectory -Root $Root -Directory $publish -BaseId $baseId -QemuImgRunner $QemuImgRunner

        $final = Join-Path $paths.Bases $baseId
        if (Test-Path -LiteralPath $final -PathType Container) {
            $existing = Test-EzDarkFactoryPreparedBase -Root $Root -BaseId $baseId -QemuImgRunner $QemuImgRunner
            if ($existing.Manifest.baseSha256 -cne $baseDigest) {
                throw "Content-addressed prepared-base collision at '$baseId'. Refusing replacement."
            }
            Remove-EzDarkFactorySafeTree -Path $publish
            $publish = $null
            try { Remove-EzDarkFactorySafeTree -Path $stage } catch { }
            return [pscustomobject][ordered]@{
                baseId = $baseId
                path = $existing.Image
                manifestPath = $existing.ManifestPath
                sha256 = $baseDigest
                virtualSizeBytes = $virtualSize
                reused = $true
                accelerator = $Accelerator
            }
        }

        Move-EzDarkFactoryDirectoryAtomically -Source $publish -Destination $final
        $publish = $null
        try { Remove-EzDarkFactorySafeTree -Path $stage } catch { }

        return [pscustomobject][ordered]@{
            baseId = $baseId
            path = Join-Path $final 'base.qcow2'
            manifestPath = Join-Path $final 'manifest.json'
            sha256 = $baseDigest
            virtualSizeBytes = $virtualSize
            reused = $false
            accelerator = $Accelerator
        }
    }
    catch {
        if ($null -ne $seedServer) {
            try { Stop-EzDarkFactorySeedServer -Server $seedServer } catch { }
        }
        if ($null -ne $publish -and (Test-Path -LiteralPath $publish -PathType Container)) {
            try { Remove-EzDarkFactorySafeTree -Path $publish } catch { }
        }
        Write-EzDarkFactoryBaseFailureEvidence -StagingDirectory $stage -BuildId $buildId -Failure $_
        throw [InvalidOperationException]::new(
            "Prepared-base build failed. No authoritative base was promoted. Diagnostic staging evidence is retained at '$stage'. $($_.Exception.Message)",
            $_.Exception)
    }
    finally {
        # Retain disk/log/failure evidence, not transport input files. Seeds are
        # regenerated from reviewed source; no seed body is copied into logs.
        if ($null -ne $seedServer) { try { Stop-EzDarkFactorySeedServer -Server $seedServer } catch { } }
        if (Test-Path -LiteralPath $seedDirectory) { try { Remove-EzDarkFactorySafeTree -Path $seedDirectory } catch { } }
    }
}
