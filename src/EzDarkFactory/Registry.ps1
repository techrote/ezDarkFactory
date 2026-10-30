function Resolve-EzDarkFactoryInstanceResources {
    [CmdletBinding()]
    param(
        [string]$Root = $script:EzDarkFactoryDefaultRoot,
        [AllowEmptyString()][string]$Profile = '',
        [AllowNull()][Nullable[int]]$Cpus = $null,
        [AllowNull()][Nullable[int]]$MemoryMiB = $null
    )

    $configuration = Get-EzDarkFactoryConfiguration -Root $Root
    $profileName = if ([string]::IsNullOrWhiteSpace($Profile)) {
        [string]$configuration.defaultProfile
    } else {
        $Profile.ToLowerInvariant()
    }
    if (@('light', 'normal', 'heavy', 'custom') -cnotcontains $profileName) {
        throw "Resource profile '$Profile' is invalid. Use light, normal, heavy or custom with explicit CPU and memory values."
    }
    if ($profileName -ceq 'custom' -and ($null -eq $Cpus -or $null -eq $MemoryMiB)) {
        throw 'The custom resource profile requires both -Cpus and -MemoryMiB.'
    }
    $profileValue = if ($profileName -ceq 'custom') { $configuration.profiles.normal } else { $configuration.profiles.$profileName }
    $resolvedCpus = if ($null -ne $Cpus) { [int]$Cpus } else { [int]$profileValue.cpus }
    $resolvedMemory = if ($null -ne $MemoryMiB) { [int]$MemoryMiB } else { [int]$profileValue.memoryMiB }
    Assert-EzDarkFactoryRuntimeInteger -Value $resolvedCpus -Description 'Instance CPU count' -Minimum 1 -Maximum 256
    Assert-EzDarkFactoryRuntimeInteger -Value $resolvedMemory -Description 'Instance memoryMiB' -Minimum 512 -Maximum 1048576

    $warnings = New-Object 'System.Collections.Generic.List[string]'
    $hostCpus = [Environment]::ProcessorCount
    if ($hostCpus -gt 0 -and $resolvedCpus -gt $hostCpus) {
        $warnings.Add("Requested $resolvedCpus vCPU exceeds the host-visible logical processor count $hostCpus; start may be slow or refused by the accelerator.")
    }
    if ($resolvedMemory -gt 262144) {
        $warnings.Add("Requested memory is $resolvedMemory MiB. This is unusually large; verify host capacity before start.")
    }

    return [pscustomobject][ordered]@{
        profile = $profileName
        cpus = $resolvedCpus
        memoryMiB = $resolvedMemory
        warnings = [string[]]$warnings.ToArray()
    }
}

function Get-EzDarkFactoryPreparedBaseSelection {
    [CmdletBinding()]
    param(
        [string]$Root = $script:EzDarkFactoryDefaultRoot,
        [AllowEmptyString()][string]$BaseId = '',
        [scriptblock]$QemuImgRunner
    )

    if (-not [string]::IsNullOrWhiteSpace($BaseId)) {
        $validated = Test-EzDarkFactoryPreparedBase -Root $Root -BaseId $BaseId -QemuImgRunner $QemuImgRunner
        return [pscustomobject][ordered]@{ BaseId = [string]$validated.BaseId; SelectedBy = 'explicit' }
    }

    $paths = Get-EzDarkFactoryPaths -Root $Root
    if (-not (Test-Path -LiteralPath $paths.Bases -PathType Container)) {
        throw "No prepared base exists. Run '.\ezdarkfactory.ps1 base build' before creating an instance, or supply -BaseId."
    }

    $candidates = New-Object 'System.Collections.Generic.List[object]'
    foreach ($directory in @(Get-ChildItem -LiteralPath $paths.Bases -Directory -Force -ErrorAction Stop | Sort-Object Name)) {
        if ($directory.Name -cnotmatch '^base-[a-f0-9]{64}$') { continue }
        $manifestPath = Join-Path $directory.FullName 'manifest.json'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            throw "Prepared-base directory '$($directory.Name)' has no manifest.json. Repair or remove the incomplete managed base before relying on implicit base selection."
        }
        $null = Assert-EzDarkFactoryStorageManagedPath -Path $manifestPath -ContainmentRoot $paths.Bases -SafetyRoot $paths.Root -Description 'Base selection manifest' -RequireFile
        $manifest = Read-EzDarkFactoryPreparedBaseManifest -Path $manifestPath
        if ([string]$manifest.baseId -cne $directory.Name) { throw 'Base directory disagrees with its manifest identity.' }
        if ($manifest.schemaVersion -eq 2) {
            # Sensitive snapshots are selected explicitly by ID or lifecycle
            # operations; never make an ordinary create inherit authentication.
            continue
        }
        Assert-EzDarkFactoryPreparedBaseManifest -Manifest $manifest
        if ([string]$manifest.baseId -cne $directory.Name) {
            throw "Prepared-base directory '$($directory.Name)' disagrees with its manifest identity '$($manifest.baseId)'. Repair the managed base before creating instances."
        }
        $builtAt = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse(
            [string]$manifest.builtAt,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$builtAt)) {
            throw "Prepared-base '$($directory.Name)' has an invalid builtAt timestamp."
        }
        $candidates.Add([pscustomobject]@{
            BaseId = [string]$manifest.baseId
            BuiltAt = $builtAt
        })
    }
    if ($candidates.Count -eq 0) {
        throw "No published prepared base exists. Run '.\ezdarkfactory.ps1 base build' before creating an instance."
    }

    $selected = @($candidates.ToArray() | Sort-Object -Property @{ Expression = { $_.BuiltAt }; Descending = $true }, @{ Expression = { $_.BaseId }; Descending = $true } | Select-Object -First 1)[0]
    $null = Test-EzDarkFactoryPreparedBase -Root $Root -BaseId $selected.BaseId -QemuImgRunner $QemuImgRunner
    return [pscustomobject][ordered]@{ BaseId = [string]$selected.BaseId; SelectedBy = 'latest-built' }
}

function Get-EzDarkFactoryInstanceRegistry {
    [CmdletBinding()]
    param([string]$Root = $script:EzDarkFactoryDefaultRoot)

    $paths = Get-EzDarkFactoryPaths -Root $Root
    $null = Assert-EzDarkFactoryStorageManagedPath -Path $paths.Instances -ContainmentRoot $paths.Runtime -SafetyRoot $paths.Root -Description 'Managed instance registry'
    if (-not (Test-Path -LiteralPath $paths.Instances -PathType Container)) { return @() }

    $instances = New-Object 'System.Collections.Generic.List[object]'
    $portableNames = @{}
    $portOwners = @{}
    foreach ($directory in @(Get-ChildItem -LiteralPath $paths.Instances -Directory -Force -ErrorAction Stop | Sort-Object Name)) {
        try { Assert-EzDarkFactoryStorageInstanceName -Name $directory.Name }
        catch {
            throw "Managed instances directory contains unsafe entry '$($directory.Name)'. $($_.Exception.Message) Reconcile the directory before registry operations."
        }

        $folded = $directory.Name.ToUpperInvariant()
        if ($portableNames.ContainsKey($folded)) {
            throw "Managed instance names '$($portableNames[$folded])' and '$($directory.Name)' collide on case-insensitive Windows filesystems. Rename one before continuing."
        }
        $portableNames[$folded] = $directory.Name

        $intentPath = Join-Path $directory.FullName 'instance.json'
        if (-not (Test-Path -LiteralPath $intentPath -PathType Leaf)) {
            throw "Managed instance directory '$($directory.Name)' has no durable instance.json. Reconcile or remove the incomplete directory before registry operations."
        }
        $intent = Get-EzDarkFactoryInstanceIntent -Root $Root -InstanceName $directory.Name
        $portKey = [string][int]$intent.sshPort
        if ($portOwners.ContainsKey($portKey)) {
            throw "Managed instances '$($portOwners[$portKey])' and '$($intent.name)' both reserve SSH port $portKey. Reconcile the conflicting instance.json files before registry operations."
        }
        $portOwners[$portKey] = [string]$intent.name
        $instances.Add($intent)
    }
    return @($instances.ToArray())
}

function Get-EzDarkFactoryAllocatedSshPorts {
    [CmdletBinding()]
    param(
        [string]$Root = $script:EzDarkFactoryDefaultRoot,
        [AllowEmptyString()][string]$ExcludeInstanceName = ''
    )

    $ports = New-Object 'System.Collections.Generic.List[int]'
    foreach ($intent in @(Get-EzDarkFactoryInstanceRegistry -Root $Root)) {
        if (-not [string]::IsNullOrWhiteSpace($ExcludeInstanceName) -and
            [string]$intent.name -ceq $ExcludeInstanceName) {
            continue
        }
        $ports.Add([int]$intent.sshPort)
    }
    return [int[]]$ports.ToArray()
}

function Assert-EzDarkFactoryInstanceSshPortReservation {
    [CmdletBinding()]
    param(
        [string]$Root = $script:EzDarkFactoryDefaultRoot,
        [Parameter(Mandatory = $true)][object]$Intent,
        [scriptblock]$PortProbe
    )

    Assert-EzDarkFactoryInstanceIntent -Intent $Intent -ExpectedName ([string]$Intent.name)
    $port = [int]$Intent.sshPort
    $usedBy = @(
        Get-EzDarkFactoryInstanceRegistry -Root $Root |
            Where-Object { [string]$_.name -cne [string]$Intent.name -and [int]$_.sshPort -eq $port }
    )
    if ($usedBy.Count -gt 0) {
        throw "SSH port $port assigned to instance '$($Intent.name)' is also reserved by '$($usedBy[0].name)'. Reconcile instance.json allocations before start."
    }

    $available = if ($null -ne $PortProbe) {
        [bool](& $PortProbe $port)
    } else {
        Test-EzDarkFactoryLoopbackPortAvailable -Port $port
    }
    if (-not $available) {
        throw "SSH port $port reserved for instance '$($Intent.name)' is already in use on 127.0.0.1. Stop the unrelated listener or deliberately recreate/reassign the instance before start."
    }
    return $port
}

function New-EzDarkFactoryManagedInstance {
    [CmdletBinding()]
    param(
        [string]$Root = $script:EzDarkFactoryDefaultRoot,
        [Parameter(Mandatory = $true)][string]$InstanceName,
        [AllowEmptyString()][string]$BaseId = '',
        [AllowEmptyString()][string]$Profile = '',
        [AllowNull()][Nullable[int]]$Cpus = $null,
        [AllowNull()][Nullable[int]]$MemoryMiB = $null,
        [AllowNull()][object]$Origin = $null,
        [scriptblock]$QemuImgRunner,
        [scriptblock]$PortProbe
    )

    Assert-EzDarkFactoryStorageInstanceName -Name $InstanceName
    $paths = Get-EzDarkFactoryPaths -Root $Root
    $runtimePaths = Get-EzDarkFactoryInstanceRuntimePaths -Root $Root -InstanceName $InstanceName
    $resources = Resolve-EzDarkFactoryInstanceResources -Root $Root -Profile $Profile -Cpus $Cpus -MemoryMiB $MemoryMiB
    $base = Get-EzDarkFactoryPreparedBaseSelection -Root $Root -BaseId $BaseId -QemuImgRunner $QemuImgRunner
    if ($null -ne $Origin) { Assert-EzDarkFactoryInstanceOrigin -Origin $Origin -ExpectedBaseId $base.BaseId }

    # EDF-004: ordinary create and explicit fresh-clone start from the EDF-owned
    # empty-workspace profile. Stateful clone/import are explicit preservation
    # operations; they retain the state-compatible historical coding contract
    # instead of falsely classifying preserved workspace state as a fresh project.
    $provisioningProfileName = 'fresh-project'
    if ($null -ne $Origin -and @('stateful-clone', 'import') -ccontains [string]$Origin.operation) {
        $provisioningProfileName = 'coding-default'
    }
    $codingProfile = Get-EzDarkFactoryCodingProfile -Root $Root -Name $provisioningProfileName -Version 1

    $null = Assert-EzDarkFactoryStorageManagedPath -Path $paths.Instances -ContainmentRoot $paths.Runtime -SafetyRoot $paths.Root -Description 'Managed instance root'
    $null = Assert-EzDarkFactorySafePath -Path $paths.Instances -Description 'Managed directory'
    [void][IO.Directory]::CreateDirectory($paths.Instances)
    $lock = Enter-EzDarkFactorySshAllocationLock -Root $Root
    $instanceLock = $null
    $createdDirectory = $false
    try {
        # Reconstruct all allocation authority while holding the same lock used
        # to publish the new durable reservation. A malformed peer instance fails
        # closed instead of being silently skipped and allowing a collision.
        $registry = @(Get-EzDarkFactoryInstanceRegistry -Root $Root)
        foreach ($existing in $registry) {
            if ([string]::Equals([string]$existing.name, $InstanceName, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Instance '$InstanceName' already exists as '$($existing.name)'. Choose a unique portable name."
            }
        }
        if (Test-Path -LiteralPath $runtimePaths.Directory) {
            throw "Managed instance directory '$($runtimePaths.Directory)' already exists without a registry entry. Reconcile or remove the incomplete directory before create."
        }
        $instanceLock = Enter-EzDarkFactoryInstanceLifecycleLock -Root $Root -InstanceName $InstanceName

        $reserved = [int[]]@($registry | ForEach-Object { [int]$_.sshPort })
        $sshPort = Get-EzDarkFactoryAvailableSshPort -Root $Root -PortProbe $PortProbe -ReservedPorts $reserved

        $null = Assert-EzDarkFactorySafePath -Path $runtimePaths.Directory -Description 'Managed directory'

        [void][IO.Directory]::CreateDirectory($runtimePaths.Directory)
        $createdDirectory = $true
        $null = Assert-EzDarkFactoryStorageManagedPath -Path $runtimePaths.Directory -ContainmentRoot $paths.Instances -SafetyRoot $paths.Root -Description 'Instance directory' -RequireDirectory
        if ($null -ne $Origin) { Write-EzDarkFactoryJson -Path $runtimePaths.Origin -Value $Origin -SchemaVersion 1 }

        $intent = New-EzDarkFactoryInstanceIntent -Root $Root -InstanceName $InstanceName -BaseId $base.BaseId -Profile $resources.profile -Cpus $resources.cpus -MemoryMiB $resources.memoryMiB -SshPort $sshPort -ProvisioningProfile $codingProfile.Name -ProvisioningVersion $codingProfile.Version -QemuImgRunner $QemuImgRunner
        $guard = New-EzDarkFactoryStorageLifecycleGuard -State 'proven-safe' -Source 'new EDF-008 instance has no QEMU owner'
        $overlay = New-EzDarkFactoryInstanceOverlay -Root $Root -InstanceName $InstanceName -BaseId $base.BaseId -LifecycleGuard $guard -QemuImgRunner $QemuImgRunner

        return [pscustomobject][ordered]@{
            name = [string]$intent.name
            baseId = [string]$intent.baseId
            profile = [string]$intent.profile
            cpus = [int]$intent.cpus
            memoryMiB = [int]$intent.memoryMiB
            sshPort = [int]$intent.sshPort
            provisioningProfile = [string]$intent.provisioningProfile
            provisioningVersion = [int]$intent.provisioningVersion
            identityGeneration = [string]$intent.identityGeneration
            createdAt = [string]$intent.createdAt
            baseSelection = [string]$base.SelectedBy
            warnings = [string[]]$resources.warnings
            chainDepth = [int]$overlay.ChainDepth
        }
    }
    catch {
        if ($createdDirectory -and (Test-Path -LiteralPath $runtimePaths.Directory -PathType Container)) {
            try {
                $null = Assert-EzDarkFactoryStorageManagedPath -Path $runtimePaths.Directory -ContainmentRoot $paths.Instances -SafetyRoot $paths.Root -Description 'Failed create cleanup directory' -RequireDirectory
                Remove-EzDarkFactorySafeTree -Path $runtimePaths.Directory
            }
            catch {
                throw [InvalidOperationException]::new(
                    "Instance create failed and cleanup of the new managed directory also failed. Reconcile '$($runtimePaths.Directory)' before retrying. $($_.Exception.Message)",
                    $_.Exception)
            }
        }
        throw
    }
    finally {
        if ($null -ne $instanceLock) { $instanceLock.Dispose() }
        $lock.Dispose()
    }
}

function Get-EzDarkFactoryManagedInstanceStatus {
    [CmdletBinding()]
    param(
        [string]$Root = $script:EzDarkFactoryDefaultRoot,
        [Parameter(Mandatory = $true)][string]$InstanceName,
        [scriptblock]$ProcessProvider
    )

    $lifecycle = Get-EzDarkFactoryInstanceStatus -Root $Root -InstanceName $InstanceName -ProcessProvider $ProcessProvider
    if ($lifecycle.state -ceq 'ABSENT') { return $lifecycle }
    $intent = Get-EzDarkFactoryInstanceIntent -Root $Root -InstanceName $InstanceName
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        name = [string]$intent.name
        state = [string]$lifecycle.state
        reason = [string]$lifecycle.reason
        profile = [string]$intent.profile
        cpus = [int]$intent.cpus
        memoryMiB = [int]$intent.memoryMiB
        sshPort = [int]$intent.sshPort
        baseId = [string]$intent.baseId
        provisioningProfile = [string]$intent.provisioningProfile
        provisioningVersion = [int]$intent.provisioningVersion
        createdAt = [string]$intent.createdAt
        pid = $lifecycle.pid
        accelerator = $lifecycle.accelerator
        startedAt = $lifecycle.startedAt
        stoppedAt = $lifecycle.stoppedAt
    }
}

function Get-EzDarkFactoryManagedInstanceList {
    [CmdletBinding()]
    param(
        [string]$Root = $script:EzDarkFactoryDefaultRoot,
        [scriptblock]$ProcessProvider
    )

    $result = New-Object 'System.Collections.Generic.List[object]'
    foreach ($intent in @(Get-EzDarkFactoryInstanceRegistry -Root $Root)) {
        $result.Add((Get-EzDarkFactoryManagedInstanceStatus -Root $Root -InstanceName ([string]$intent.name) -ProcessProvider $ProcessProvider))
    }
    return @($result.ToArray())
}
