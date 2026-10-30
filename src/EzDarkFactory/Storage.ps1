function Get-EzDarkFactoryStorageProperty {
    param([AllowNull()][object]$Object, [Parameter(Mandatory = $true)][string]$Name)

    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-EzDarkFactoryStoragePathComparison {
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        return [StringComparison]::OrdinalIgnoreCase
    }
    return [StringComparison]::Ordinal
}

function Test-EzDarkFactoryStorageSamePath {
    param([string]$Left, [string]$Right)
    return [string]::Equals(
        [IO.Path]::GetFullPath($Left),
        [IO.Path]::GetFullPath($Right),
        (Get-EzDarkFactoryStoragePathComparison))
}

function Test-EzDarkFactoryStoragePathInside {
    param([string]$Path, [string]$Directory)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullDirectory = [IO.Path]::GetFullPath($Directory)
    $comparison = Get-EzDarkFactoryStoragePathComparison
    if ([string]::Equals($fullPath, $fullDirectory, $comparison)) { return $true }
    $prefix = $fullDirectory.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)) +
        [IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith($prefix, $comparison)
}

function Assert-EzDarkFactoryStorageManagedPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ContainmentRoot,
        [Parameter(Mandatory = $true)][string]$SafetyRoot,
        [Parameter(Mandatory = $true)][string]$Description,
        [switch]$RequireFile,
        [switch]$RequireDirectory
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $containment = [IO.Path]::GetFullPath($ContainmentRoot)
    $safety = [IO.Path]::GetFullPath($SafetyRoot)
    if (-not (Test-EzDarkFactoryStoragePathInside -Path $fullPath -Directory $containment)) {
        throw "$Description escapes its managed root. Resolved path '$fullPath' is outside '$containment'. Refuse the operation and restore the expected ezdarkfactory layout."
    }

    if ($RequireFile -and -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "$Description is missing at '$fullPath'. Restore the expected managed file and retry."
    }
    if ($RequireDirectory -and -not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        throw "$Description directory is missing at '$fullPath'. Restore the expected managed directory and retry."
    }

    $null = Assert-EzDarkFactorySafePath -Path $fullPath -Description $Description
    return $fullPath
}

function Assert-EzDarkFactoryStorageInstanceName {
    param([Parameter(Mandatory = $true)][string]$Name)

    if ($Name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
        throw "Instance name '$Name' is invalid for managed storage. Use 1-64 letters, digits, dot, underscore or hyphen, starting with a letter or digit."
    }
    if ($Name.EndsWith('.', [StringComparison]::Ordinal) -or $Name.EndsWith(' ', [StringComparison]::Ordinal)) {
        throw "Instance name '$Name' is unsafe on Windows because it ends in a dot or space."
    }
    if ($Name -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$') {
        throw "Instance name '$Name' is a reserved Windows device name."
    }
}

function Get-EzDarkFactoryInstanceStoragePaths {
    [CmdletBinding()]
    param(
        [string]$Root = $script:EzDarkFactoryDefaultRoot,
        [Parameter(Mandatory = $true)][string]$InstanceName
    )

    Assert-EzDarkFactoryStorageInstanceName -Name $InstanceName
    $paths = Get-EzDarkFactoryPaths -Root $Root
    $directory = Join-Path $paths.Instances $InstanceName
    return [pscustomobject][ordered]@{
        InstanceName = $InstanceName
        Directory = [IO.Path]::GetFullPath($directory)
        Disk = [IO.Path]::GetFullPath((Join-Path $directory 'disk.qcow2'))
    }
}

function Get-EzDarkFactoryStorageRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FromDirectory,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $from = [IO.Path]::GetFullPath($FromDirectory)
    $target = [IO.Path]::GetFullPath($TargetPath)
    $fromRoot = [IO.Path]::GetPathRoot($from)
    $targetRoot = [IO.Path]::GetPathRoot($target)
    $comparison = Get-EzDarkFactoryStoragePathComparison
    if (-not [string]::Equals($fromRoot, $targetRoot, $comparison)) {
        throw "A relocation-safe relative backing path cannot cross filesystem roots: '$from' -> '$target'. Keep instances and prepared bases inside one ezdarkfactory root."
    }

    $separators = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $fromTail = $from.Substring($fromRoot.Length).Trim($separators)
    $targetTail = $target.Substring($targetRoot.Length).Trim($separators)
    $fromParts = if ($fromTail.Length -eq 0) { @() } else { @($fromTail.Split($separators, [StringSplitOptions]::RemoveEmptyEntries)) }
    $targetParts = if ($targetTail.Length -eq 0) { @() } else { @($targetTail.Split($separators, [StringSplitOptions]::RemoveEmptyEntries)) }

    $common = 0
    while ($common -lt $fromParts.Count -and $common -lt $targetParts.Count -and
        [string]::Equals($fromParts[$common], $targetParts[$common], $comparison)) {
        $common++
    }

    $relative = New-Object 'System.Collections.Generic.List[string]'
    for ($index = $common; $index -lt $fromParts.Count; $index++) { $relative.Add('..') }
    for ($index = $common; $index -lt $targetParts.Count; $index++) { $relative.Add($targetParts[$index]) }
    if ($relative.Count -eq 0) { return '.' }
    return [string]::Join([IO.Path]::DirectorySeparatorChar, $relative.ToArray())
}

function New-EzDarkFactoryStorageLifecycleGuard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('proven-safe', 'running', 'starting', 'stopping', 'unknown')]
        [string]$State,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Source
    )

    return [pscustomobject][ordered]@{
        schemaVersion = 1
        state = $State
        source = $Source
        observedAt = [DateTime]::UtcNow.ToString('o')
    }
}

function Assert-EzDarkFactoryStorageLifecycleGuard {
    param([AllowNull()][object]$LifecycleGuard, [string]$Operation)

    if ($null -eq $LifecycleGuard) {
        throw "$Operation requires explicit positive lifecycle evidence. Missing runtime state is not proof that storage is stopped."
    }
    try { Assert-EzDarkFactoryRuntimeInteger -Value (Get-EzDarkFactoryStorageProperty $LifecycleGuard 'schemaVersion') -Description 'Lifecycle guard schemaVersion' -Minimum 1 -Maximum 1 }
    catch {
        throw "$Operation received an unsupported lifecycle-guard schema. Reconcile instance process state before touching storage."
    }
    $state = [string](Get-EzDarkFactoryStorageProperty $LifecycleGuard 'state')
    if (@('proven-safe', 'running', 'starting', 'stopping', 'unknown') -cnotcontains $state) {
        throw "$Operation received invalid lifecycle state '$state'. Refuse storage access until lifecycle state is reconciled."
    }
    if ($state -cne 'proven-safe') {
        throw "$Operation requires positively proven stopped/absent storage ownership; lifecycle state is '$state'. Reconcile the QEMU process before retrying."
    }
    $source = Get-EzDarkFactoryStorageProperty $LifecycleGuard 'source'
    if ($source -isnot [string] -or [string]::IsNullOrWhiteSpace($source)) {
        throw "$Operation requires lifecycle evidence with a non-empty source."
    }
}

function Invoke-EzDarkFactoryStorageQemuImg {
    param(
        [string]$Root,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [scriptblock]$Runner,
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = 300,
        [switch]$AllowNonZero
    )

    if ($null -ne $Runner) {
        $result = & $Runner $ArgumentList
        if ($null -eq $result -or $null -eq $result.PSObject.Properties['ExitCode'] -or
            $null -eq $result.PSObject.Properties['StdOut'] -or $null -eq $result.PSObject.Properties['StdErr']) {
            throw 'qemu-img storage runner must return ExitCode, StdOut and StdErr.'
        }
    }
    else {
        $tool = Get-EzDarkFactoryQemuToolPath -Name 'qemu-img.exe' -Root $Root
        $result = Invoke-EzDarkFactoryProcess -FilePath $tool -ArgumentList $ArgumentList -WorkingDirectory (Split-Path -Parent $tool) -TimeoutSeconds $TimeoutSeconds
    }

    if (-not $AllowNonZero -and [int]$result.ExitCode -ne 0) {
        $detail = [string]$result.StdErr
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = [string]$result.StdOut }
        if ($detail.Length -gt 2048) { $detail = $detail.Substring(0, 2048) + '...' }
        throw "qemu-img storage operation failed with exit code $($result.ExitCode). $detail"
    }
    return $result
}

function ConvertFrom-EzDarkFactoryStorageJson {
    param([string]$Text, [string]$Description)

    if ([string]::IsNullOrWhiteSpace($Text)) { throw "$Description returned empty JSON output." }
    try { return $Text | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "$Description returned malformed JSON: $($_.Exception.Message)" }
}

function Get-EzDarkFactoryStorageImageInfo {
    [CmdletBinding()]
    param(
        [string]$Root = $script:EzDarkFactoryDefaultRoot,
        [Parameter(Mandatory = $true)][string]$Path,
        [scriptblock]$QemuImgRunner
    )

    $result = Invoke-EzDarkFactoryStorageQemuImg -Root $Root -ArgumentList @(
        'info', '--output=json', [IO.Path]::GetFullPath($Path)
    ) -Runner $QemuImgRunner
    $value = ConvertFrom-EzDarkFactoryStorageJson -Text $result.StdOut -Description "qemu-img info for '$Path'"
    if ($value -isnot [pscustomobject]) { throw "qemu-img info for '$Path' must return one JSON object." }
    return $value
}

function Get-EzDarkFactoryStorageBackingChain {
    [CmdletBinding()]
    param(
        [string]$Root = $script:EzDarkFactoryDefaultRoot,
        [Parameter(Mandatory = $true)][string]$OverlayPath,
        [scriptblock]$QemuImgRunner
    )

    $result = Invoke-EzDarkFactoryStorageQemuImg -Root $Root -ArgumentList @(
        'info', '--backing-chain', '--output=json', [IO.Path]::GetFullPath($OverlayPath)
    ) -Runner $QemuImgRunner
    $parsed = ConvertFrom-EzDarkFactoryStorageJson -Text $result.StdOut -Description "qemu-img backing-chain inspection for '$OverlayPath'"
    $chain = @($parsed)
    if ($chain.Count -eq 0) { throw 'qemu-img backing-chain inspection returned no images.' }
    foreach ($entry in $chain) {
        if ($entry -isnot [pscustomobject]) { throw 'qemu-img backing-chain output must contain only JSON objects.' }
    }
    return $chain
}

function Get-EzDarkFactoryStorageInteger {
    param([object]$Object, [string]$Name, [string]$Description, [switch]$Optional)

    $value = Get-EzDarkFactoryStorageProperty $Object $Name
    if ($null -eq $value -and $Optional) { return [long]0 }
    $integer = $value -is [byte] -or $value -is [int16] -or $value -is [int32] -or
        $value -is [int64] -or $value -is [uint16] -or $value -is [uint32] -or $value -is [uint64]
    if (-not $integer -or [long]$value -lt 0) { throw "$Description field '$Name' must be a non-negative integer." }
    return [long]$value
}

function Resolve-EzDarkFactoryStorageReportedPath {
    param([string]$Filename, [string]$RelativeToDirectory, [string]$Description)

    if ([string]::IsNullOrWhiteSpace($Filename)) { throw "$Description omitted its filename." }
    if ([IO.Path]::IsPathRooted($Filename)) { return [IO.Path]::GetFullPath($Filename) }
    return [IO.Path]::GetFullPath((Join-Path $RelativeToDirectory $Filename))
}

function Test-EzDarkFactoryInstanceOverlay {
    [CmdletBinding()]
    param(
        [string]$Root = $script:EzDarkFactoryDefaultRoot,
        [Parameter(Mandatory = $true)][string]$OverlayPath,
        [Parameter(Mandatory = $true)][string]$BaseId,
        [scriptblock]$QemuImgRunner
    )

    if ($BaseId -cnotmatch '^base-[a-f0-9]{64}$') { throw "Expected base ID '$BaseId' is invalid." }
    $paths = Get-EzDarkFactoryPaths -Root $Root
    $overlay = Assert-EzDarkFactoryStorageManagedPath -Path $OverlayPath -ContainmentRoot $paths.Instances -SafetyRoot $paths.Root -Description 'Instance overlay' -RequireFile
    if ($null -eq $QemuImgRunner) {
        # Production must reject dependencies in mutable bytes BEFORE invoking
        # qemu-img. Injected metadata runners are trusted test boundaries only.
        $expectedBase = Join-Path (Join-Path $paths.Bases $BaseId) 'base.qcow2'
        $relative = Get-EzDarkFactoryStorageRelativePath -FromDirectory ([IO.Path]::GetDirectoryName($overlay)) -TargetPath $expectedBase
        $null = Test-EzDarkFactoryQcow2Header -Path $overlay -ExpectedBacking $relative
        $null = Test-EzDarkFactoryQcow2Header -Path $expectedBase
    }
    $base = Test-EzDarkFactoryPreparedBase -Root $Root -BaseId $BaseId -QemuImgRunner $QemuImgRunner
    $baseImage = Assert-EzDarkFactoryStorageManagedPath -Path $base.Image -ContainmentRoot $paths.Bases -SafetyRoot $paths.Root -Description "Prepared base '$BaseId'" -RequireFile

    $chain = @(Get-EzDarkFactoryStorageBackingChain -Root $Root -OverlayPath $overlay -QemuImgRunner $QemuImgRunner)
    if ($chain.Count -ne 2) {
        throw "Unsupported QCOW2 backing-chain depth $($chain.Count - 1). ezdarkfactory v0.1 requires exactly one instance overlay backed directly by one immutable prepared base."
    }

    $top = $chain[0]
    $back = $chain[1]
    if ([string](Get-EzDarkFactoryStorageProperty $top 'format') -cne 'qcow2') {
        throw 'Instance overlay format must be qcow2.'
    }
    if ([string](Get-EzDarkFactoryStorageProperty $back 'format') -cne 'qcow2') {
        throw 'Instance backing image format must be qcow2.'
    }

    $topFilename = Resolve-EzDarkFactoryStorageReportedPath -Filename ([string](Get-EzDarkFactoryStorageProperty $top 'filename')) -RelativeToDirectory ([IO.Path]::GetDirectoryName($overlay)) -Description 'Overlay chain entry'
    if (-not (Test-EzDarkFactoryStorageSamePath -Left $topFilename -Right $overlay)) {
        throw "qemu-img chain top '$topFilename' does not match the intended instance overlay '$overlay'."
    }

    $backingReference = [string](Get-EzDarkFactoryStorageProperty $top 'backing-filename')
    if ([string]::IsNullOrWhiteSpace($backingReference)) {
        throw 'Instance overlay has no backing file. Recreate it against the recorded prepared base.'
    }
    if ([IO.Path]::IsPathRooted($backingReference)) {
        throw "Instance overlay stores absolute backing path '$backingReference'. Recreate the stopped overlay with ezdarkfactory so cold relocation remains valid."
    }
    $backingFormat = [string](Get-EzDarkFactoryStorageProperty $top 'backing-filename-format')
    if ($backingFormat -cne 'qcow2') {
        throw "Instance overlay backing format is '$backingFormat'; ezdarkfactory requires explicit qcow2 backing format."
    }

    $resolvedBacking = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($overlay)) $backingReference))
    $null = Assert-EzDarkFactoryStorageManagedPath -Path $resolvedBacking -ContainmentRoot $paths.Bases -SafetyRoot $paths.Root -Description 'Resolved instance backing file' -RequireFile
    if (-not (Test-EzDarkFactoryStorageSamePath -Left $resolvedBacking -Right $baseImage)) {
        throw "Instance overlay resolves to backing '$resolvedBacking', but recorded base '$BaseId' requires '$baseImage'. Refuse use until the intended immutable base relationship is restored."
    }

    $reportedBase = Resolve-EzDarkFactoryStorageReportedPath -Filename ([string](Get-EzDarkFactoryStorageProperty $back 'filename')) -RelativeToDirectory ([IO.Path]::GetDirectoryName($overlay)) -Description 'Base chain entry'
    if (-not (Test-EzDarkFactoryStorageSamePath -Left $reportedBase -Right $baseImage)) {
        throw "qemu-img resolved backing '$reportedBase', but the recorded immutable base is '$baseImage'."
    }
    $secondBacking = [string](Get-EzDarkFactoryStorageProperty $back 'backing-filename')
    if (-not [string]::IsNullOrWhiteSpace($secondBacking)) {
        throw "Prepared base unexpectedly has another backing file '$secondBacking'. ezdarkfactory v0.1 forbids a second backing level."
    }

    $overlaySize = Get-EzDarkFactoryStorageInteger -Object $top -Name 'virtual-size' -Description 'Instance overlay'
    $baseSize = Get-EzDarkFactoryStorageInteger -Object $back -Name 'virtual-size' -Description 'Prepared base'
    if ($overlaySize -le 0 -or $baseSize -le 0 -or $overlaySize -ne $baseSize) {
        throw "Instance/base virtual-size mismatch ($overlaySize vs $baseSize). Recreate the overlay against the intended prepared base."
    }

    return [pscustomobject][ordered]@{
        OverlayPath = $overlay
        BaseId = $BaseId
        BasePath = $baseImage
        BaseSha256 = [string]$base.Manifest.baseSha256
        BackingReference = $backingReference
        ResolvedBackingPath = $resolvedBacking
        ChainDepth = 1
        VirtualSizeBytes = $overlaySize
        Chain = $chain
    }
}

function Test-EzDarkFactoryInstanceStorage {
    [CmdletBinding()]
    param(
        [string]$Root = $script:EzDarkFactoryDefaultRoot,
        [Parameter(Mandatory = $true)][string]$InstanceName,
        [Parameter(Mandatory = $true)][string]$BaseId,
        [scriptblock]$QemuImgRunner
    )

    $storage = Get-EzDarkFactoryInstanceStoragePaths -Root $Root -InstanceName $InstanceName
    return Test-EzDarkFactoryInstanceOverlay -Root $Root -OverlayPath $storage.Disk -BaseId $BaseId -QemuImgRunner $QemuImgRunner
}

function Move-EzDarkFactoryStorageFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [ValidateRange(1, 100)][int]$Attempts = 20,
        [ValidateRange(0, 5000)][int]$DelayMilliseconds = 100,
        [scriptblock]$Mover
    )

    $sourcePath = Assert-EzDarkFactorySafePath -Path $Source -Description 'Atomic disk source'
    $destinationPath = Assert-EzDarkFactorySafePath -Path $Destination -Description 'Atomic disk destination'
    if (-not [string]::Equals([IO.Path]::GetPathRoot($sourcePath), [IO.Path]::GetPathRoot($destinationPath), (Get-EzDarkFactoryStoragePathComparison))) {
        throw "Atomic storage promotion requires one filesystem root: '$sourcePath' -> '$destinationPath'."
    }

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $null = Assert-EzDarkFactorySafePath -Path $sourcePath -Description 'Atomic disk source'
        $null = Assert-EzDarkFactorySafePath -Path $destinationPath -Description 'Atomic disk destination'
        if (-not [IO.File]::Exists($sourcePath)) { throw "Storage promotion source is missing: '$sourcePath'." }
        if ([IO.File]::Exists($destinationPath) -or [IO.Directory]::Exists($destinationPath)) {
            throw "Storage promotion destination already exists: '$destinationPath'."
        }
        try {
            if ($null -ne $Mover) { & $Mover $sourcePath $destinationPath }
            else { [IO.File]::Move($sourcePath, $destinationPath) }
            return
        }
        catch {
            $leaf = $_.Exception
            while ($null -ne $leaf.InnerException) { $leaf = $leaf.InnerException }
            $transient = $leaf -is [IO.IOException] -or $leaf -is [UnauthorizedAccessException]
            if (-not $transient -or $attempt -eq $Attempts) { throw }
            if (-not [IO.File]::Exists($sourcePath) -or [IO.File]::Exists($destinationPath)) { throw }
            if ($DelayMilliseconds -gt 0) { Start-Sleep -Milliseconds $DelayMilliseconds }
        }
    }
}

function New-EzDarkFactoryInstanceOverlayCandidate {
    param(
        [string]$Root,
        [string]$Destination,
        [object]$PreparedBase,
        [scriptblock]$QemuImgRunner
    )

    $directory = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Destination))
    $relativeBacking = Get-EzDarkFactoryStorageRelativePath -FromDirectory $directory -TargetPath $PreparedBase.Image
    if ([IO.Path]::IsPathRooted($relativeBacking)) { throw 'Internal error: calculated instance backing reference is not relative.' }

    $null = Invoke-EzDarkFactoryStorageQemuImg -Root $Root -ArgumentList @(
        'create', '-f', 'qcow2', '-F', 'qcow2', '-b', $relativeBacking, [IO.Path]::GetFullPath($Destination)
    ) -Runner $QemuImgRunner
    return $relativeBacking
}

function New-EzDarkFactoryInstanceOverlay {
    [CmdletBinding()]
    param(
        [string]$Root = $script:EzDarkFactoryDefaultRoot,
        [Parameter(Mandatory = $true)][string]$InstanceName,
        [Parameter(Mandatory = $true)][string]$BaseId,
        [Parameter(Mandatory = $true)][AllowNull()][object]$LifecycleGuard,
        [scriptblock]$QemuImgRunner
    )

    Assert-EzDarkFactoryStorageLifecycleGuard -LifecycleGuard $LifecycleGuard -Operation 'Instance overlay creation'
    $paths = Get-EzDarkFactoryPaths -Root $Root
    $storage = Get-EzDarkFactoryInstanceStoragePaths -Root $Root -InstanceName $InstanceName
    $null = Assert-EzDarkFactoryStorageManagedPath -Path $storage.Directory -ContainmentRoot $paths.Instances -SafetyRoot $paths.Root -Description 'Instance storage directory'
    if (Test-Path -LiteralPath $storage.Disk) {
        throw "Instance overlay already exists at '$($storage.Disk)'. Refusing to overwrite mutable storage."
    }

    $preparedBase = Test-EzDarkFactoryPreparedBase -Root $Root -BaseId $BaseId -QemuImgRunner $QemuImgRunner
    $null = Assert-EzDarkFactoryStorageManagedPath -Path $preparedBase.Image -ContainmentRoot $paths.Bases -SafetyRoot $paths.Root -Description "Prepared base '$BaseId'" -RequireFile

    [void][IO.Directory]::CreateDirectory($paths.Instances)
    [void][IO.Directory]::CreateDirectory($storage.Directory)
    $null = Assert-EzDarkFactoryStorageManagedPath -Path $storage.Directory -ContainmentRoot $paths.Instances -SafetyRoot $paths.Root -Description 'Instance storage directory' -RequireDirectory

    $candidate = Join-Path $storage.Directory ('.disk-create-' + [Guid]::NewGuid().ToString('N') + '.qcow2')
    try {
        $relative = New-EzDarkFactoryInstanceOverlayCandidate -Root $Root -Destination $candidate -PreparedBase $preparedBase -QemuImgRunner $QemuImgRunner
        $validated = Test-EzDarkFactoryInstanceOverlay -Root $Root -OverlayPath $candidate -BaseId $BaseId -QemuImgRunner $QemuImgRunner
        if ($validated.BackingReference -cne $relative) {
            throw 'Created overlay did not preserve the requested relocation-safe backing reference.'
        }
        Move-EzDarkFactoryStorageFile -Source $candidate -Destination $storage.Disk
        return [pscustomobject][ordered]@{
            InstanceName = $InstanceName
            Disk = $storage.Disk
            BaseId = $BaseId
            BaseSha256 = [string]$preparedBase.Manifest.baseSha256
            BackingReference = $relative
            ChainDepth = 1
        }
    }
    catch {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            try { Remove-Item -LiteralPath $candidate -Force } catch { }
        }
        throw
    }
}

function Test-EzDarkFactoryStoppedImageIntegrity {
    [CmdletBinding()]
    param(
        [string]$Root = $script:EzDarkFactoryDefaultRoot,
        [Parameter(Mandatory = $true)][string]$InstanceName,
        [Parameter(Mandatory = $true)][string]$BaseId,
        [Parameter(Mandatory = $true)][AllowNull()][object]$LifecycleGuard,
        [scriptblock]$QemuImgRunner
    )

    Assert-EzDarkFactoryStorageLifecycleGuard -LifecycleGuard $LifecycleGuard -Operation 'Stopped-image integrity check'
    $validated = Test-EzDarkFactoryInstanceStorage -Root $Root -InstanceName $InstanceName -BaseId $BaseId -QemuImgRunner $QemuImgRunner
    $result = Invoke-EzDarkFactoryStorageQemuImg -Root $Root -ArgumentList @(
        'check', '--output=json', '-f', 'qcow2', $validated.OverlayPath
    ) -Runner $QemuImgRunner -AllowNonZero

    $report = ConvertFrom-EzDarkFactoryStorageJson -Text $result.StdOut -Description "qemu-img check for '$($validated.OverlayPath)'"
    if ($report -isnot [pscustomobject]) { throw 'qemu-img check must return one JSON object.' }
    $format = [string](Get-EzDarkFactoryStorageProperty $report 'format')
    if ($format -cne 'qcow2') { throw "qemu-img check reported unexpected format '$format'." }
    $checkErrors = Get-EzDarkFactoryStorageInteger -Object $report -Name 'check-errors' -Description 'qemu-img check'
    $corruptions = Get-EzDarkFactoryStorageInteger -Object $report -Name 'corruptions' -Description 'qemu-img check' -Optional
    $leaks = Get-EzDarkFactoryStorageInteger -Object $report -Name 'leaks' -Description 'qemu-img check' -Optional

    return [pscustomobject][ordered]@{
        Healthy = ([int]$result.ExitCode -eq 0 -and $checkErrors -eq 0 -and $corruptions -eq 0 -and $leaks -eq 0)
        ExitCode = [int]$result.ExitCode
        CheckErrors = $checkErrors
        Corruptions = $corruptions
        Leaks = $leaks
        OverlayPath = $validated.OverlayPath
        BaseId = $BaseId
    }
}

function Reset-EzDarkFactoryInstanceOverlayStorage {
    [CmdletBinding()]
    param(
        [string]$Root = $script:EzDarkFactoryDefaultRoot,
        [Parameter(Mandatory = $true)][string]$InstanceName,
        [Parameter(Mandatory = $true)][string]$BaseId,
        [Parameter(Mandatory = $true)][AllowNull()][object]$LifecycleGuard,
        [scriptblock]$QemuImgRunner,
        [scriptblock]$FileMover,
        [switch]$PreserveBackup,
        [AllowEmptyString()][string]$RecoveryPath = ''
    )

    Assert-EzDarkFactoryStorageLifecycleGuard -LifecycleGuard $LifecycleGuard -Operation 'Instance overlay replacement'
    $paths = Get-EzDarkFactoryPaths -Root $Root
    $storage = Get-EzDarkFactoryInstanceStoragePaths -Root $Root -InstanceName $InstanceName
    $existing = Test-EzDarkFactoryInstanceStorage -Root $Root -InstanceName $InstanceName -BaseId $BaseId -QemuImgRunner $QemuImgRunner
    $preparedBase = Test-EzDarkFactoryPreparedBase -Root $Root -BaseId $BaseId -QemuImgRunner $QemuImgRunner

    $candidate = Join-Path $storage.Directory ('.disk-replacement-' + [Guid]::NewGuid().ToString('N') + '.qcow2')
    $backup = Join-Path $storage.Directory ('.disk-backup-' + [Guid]::NewGuid().ToString('N') + '.qcow2')
    if (-not [string]::IsNullOrWhiteSpace($RecoveryPath)) {
        $backup = Assert-EzDarkFactoryStorageManagedPath -Path $RecoveryPath -ContainmentRoot $storage.Directory -SafetyRoot $paths.Root -Description 'Reset recovery disk'
        if (-not (Test-EzDarkFactoryStorageSamePath -Left ([IO.Path]::GetDirectoryName($backup)) -Right $storage.Directory) -or
            [IO.Path]::GetFileName($backup) -cnotmatch '^\.disk-backup-[a-f0-9]{32}\.qcow2$') {
            throw 'Reset recovery disk must use an explicit unique backup name in the instance directory.'
        }
    }
    if (Test-Path -LiteralPath $backup) { throw "Reset recovery artifact already exists at '$backup'. Refusing replacement." }
    $originalMoved = $false
    $replacementCommitted = $false

    try {
        $relative = New-EzDarkFactoryInstanceOverlayCandidate -Root $Root -Destination $candidate -PreparedBase $preparedBase -QemuImgRunner $QemuImgRunner
        $validatedCandidate = Test-EzDarkFactoryInstanceOverlay -Root $Root -OverlayPath $candidate -BaseId $BaseId -QemuImgRunner $QemuImgRunner
        if ($validatedCandidate.BackingReference -cne $relative) {
            throw 'Replacement overlay did not preserve the requested relocation-safe backing reference.'
        }

        Move-EzDarkFactoryStorageFile -Source $storage.Disk -Destination $backup -Mover $FileMover
        $originalMoved = $true
        try {
            Move-EzDarkFactoryStorageFile -Source $candidate -Destination $storage.Disk -Mover $FileMover
            $replacementCommitted = $true
        }
        catch {
            if (-not (Test-Path -LiteralPath $storage.Disk) -and (Test-Path -LiteralPath $backup -PathType Leaf)) {
                try {
                    Move-EzDarkFactoryStorageFile -Source $backup -Destination $storage.Disk -Mover $FileMover
                    $originalMoved = $false
                }
                catch {
                    throw [InvalidOperationException]::new(
                        "Replacement promotion failed and automatic restoration also failed. The original overlay remains recoverable at '$backup'. Do not start the instance until storage is reconciled.",
                        $_.Exception)
                }
            }
            throw
        }

        if (-not $PreserveBackup -and (Test-Path -LiteralPath $backup -PathType Leaf)) {
            try { Remove-Item -LiteralPath $backup -Force } catch { }
        }
        return [pscustomobject][ordered]@{
            InstanceName = $InstanceName
            Disk = $storage.Disk
            BaseId = $BaseId
            BackingReference = $relative
            Replaced = $true
            RecoveryArtifact = $(if (Test-Path -LiteralPath $backup -PathType Leaf) { $backup } else { $null })
        }
    }
    catch {
        if (-not $replacementCommitted -and -not $originalMoved -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            try { Remove-Item -LiteralPath $candidate -Force } catch { }
        }
        throw
    }
}
