function Write-EzDarkFactoryPortabilityStoppedState {
    param([object]$Fixture)
    $paths = Get-EzDarkFactoryInstanceRuntimePaths -Root $Fixture.Root -InstanceName $Fixture.Intent.name
    $now = [DateTime]::UtcNow.ToString('o')
    $runtime = [pscustomobject][ordered]@{
        schemaVersion = 1; instanceName = $Fixture.Intent.name; state = 'STOPPED'; pid = 49999
        processStartTimeUtc = $now; qemuExecutable = Join-Path $Fixture.Paths.Qemu 'qemu-system-x86_64.exe'
        argumentFingerprint = 'a' * 64; launchId = 'b' * 32; qmpHost = '127.0.0.1'; qmpPort = 32111
        accelerator = 'tcg'; startedAt = $now; lastObservedAt = $now; stoppedAt = $now
        qemuLog = Join-Path $paths.Logs 'qemu.log'; serialLog = Join-Path $paths.Logs 'serial.log'
    }
    Write-EzDarkFactoryJson -Path $paths.Runtime -Value $runtime -SchemaVersion 1
    return $runtime
}

Add-EzDarkFactoryTest -Name 'Portability: explicit fresh and stateful clones have independent intent resources ports and provenance' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    try {
        $paths = Get-EzDarkFactoryInstanceRuntimePaths -Root $fixture.Root -InstanceName $fixture.Intent.name
        $fixture.Intent.profile = 'custom'; $fixture.Intent.cpus = 3; $fixture.Intent.memoryMiB = 2560
        Write-EzDarkFactoryJson -Path $paths.Intent -Value $fixture.Intent -SchemaVersion 2
        $sourceDigest = Get-EzDarkFactoryFileDigest -Path $fixture.Disk -Algorithm SHA256
        $fresh = Copy-EzDarkFactoryManagedInstance -Root $fixture.Root -SourceInstanceName $fixture.Intent.name -DestinationInstanceName 'fresh-destination' -Mode FRESH -QemuImgRunner $fixture.Runner -ProcessProvider { @() } -PortProbe { $true }
        $stateful = Copy-EzDarkFactoryManagedInstance -Root $fixture.Root -SourceInstanceName $fixture.Intent.name -DestinationInstanceName 'stateful-destination' -Mode STATEFUL -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider -ProcessProvider { @() } -PortProbe { $true }
        Assert-EzDarkFactoryEqual $fresh.mode 'fresh'
        Assert-EzDarkFactoryEqual $stateful.mode 'stateful'
        Assert-EzDarkFactoryEqual $fresh.baseId $fixture.Intent.baseId
        Assert-EzDarkFactoryTrue ($stateful.baseId -cne $fixture.Intent.baseId)
        Assert-EzDarkFactoryEqual @($fresh.sshPort, $stateful.sshPort) @(22001, 22002)
        foreach ($copy in @($fresh, $stateful)) {
            Assert-EzDarkFactoryEqual $copy.profile 'custom'
            Assert-EzDarkFactoryEqual $copy.cpus 3
            Assert-EzDarkFactoryEqual $copy.memoryMiB 2560
            Assert-EzDarkFactoryEqual $copy.chainDepth 1
            Assert-EzDarkFactoryTrue ($copy.identityGeneration -cne $fixture.Intent.identityGeneration)
            $copyPaths = Get-EzDarkFactoryInstanceRuntimePaths -Root $fixture.Root -InstanceName $copy.name
            $origin = Read-EzDarkFactoryJson -Path $copyPaths.Origin -SchemaVersion 1
            Assert-EzDarkFactoryEqual $origin.sourceInstance.name $fixture.Intent.name
            Assert-EzDarkFactoryEqual $origin.baseId $copy.baseId
            Assert-EzDarkFactoryTrue ([IO.File]::ReadAllText($copyPaths.Origin) -notmatch [regex]::Escape($fixture.Root))
            Assert-EzDarkFactoryEqual (Get-EzDarkFactorySnapshotFixturePayload $copyPaths.Disk).data ''
        }
        $derived = Test-EzDarkFactoryPreparedBase -Root $fixture.Root -BaseId $stateful.baseId -QemuImgRunner $fixture.Runner
        Assert-EzDarkFactoryEqual $derived.Manifest.kind 'derived'
        Assert-EzDarkFactoryEqual (Get-EzDarkFactorySnapshotFixturePayload $derived.Image).data 'source workspace sentinel and synthetic auth state'
        Assert-EzDarkFactoryEqual (Get-EzDarkFactorySnapshotFixturePayload $fixture.Base.Image).data 'baseline guest bytes'
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $fixture.Disk -Algorithm SHA256) $sourceDigest
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Portability: reset keeps baseline resources reservation and prior SSH trust while rotating identity and clearing stale state' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    try {
        $paths = Get-EzDarkFactoryInstanceRuntimePaths -Root $fixture.Root -InstanceName $fixture.Intent.name
        $ssh = Get-EzDarkFactorySshPaths -Root $fixture.Root -InstanceName $fixture.Intent.name
        $null = Write-EzDarkFactoryPortabilityStoppedState $fixture
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($ssh.InstanceKnownHosts))
        [IO.File]::WriteAllText($ssh.InstanceKnownHosts, 'previous promoted host identity')
        [IO.File]::WriteAllText($ssh.AccessState, '{"oldAccess":true}')
        [IO.File]::WriteAllText($paths.FirmwareVariables, 'old mutable UEFI')
        $baseHash = Get-EzDarkFactoryFileDigest -Path $fixture.Base.Image -Algorithm SHA256
        $observed = [pscustomobject]@{ JournalBeforeMove = $false }
        $state = $observed; $operation = $paths.Operation
        $mover = {
            param($source, $destination)
            if ($source.EndsWith('disk.qcow2')) {
                $journal = Read-EzDarkFactoryJson -Path $operation -SchemaVersion 1
                $state.JournalBeforeMove = $journal.phase -ceq 'prepared' -and $journal.targetIntent.identityGeneration -cne $journal.originalIntent.identityGeneration
            }
            [IO.File]::Move($source, $destination)
        }.GetNewClosure()
        $reset = Reset-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName $fixture.Intent.name -QemuImgRunner $fixture.Runner -ProcessProvider { @() } -FileMover $mover
        $intent = Get-EzDarkFactoryInstanceIntent -Root $fixture.Root -InstanceName $fixture.Intent.name
        Assert-EzDarkFactoryTrue $observed.JournalBeforeMove
        Assert-EzDarkFactoryEqual $reset.state 'CREATED'
        Assert-EzDarkFactoryEqual $reset.resetBaseline 'imported'
        Assert-EzDarkFactoryEqual $reset.sensitiveState $true
        Assert-EzDarkFactoryEqual @($reset.recoveryArtifact).Count 0
        foreach ($field in @('name', 'baseId', 'profile', 'cpus', 'memoryMiB', 'sshPort', 'createdAt', 'provisioningProfile', 'provisioningVersion')) {
            Assert-EzDarkFactoryEqual $intent.$field $fixture.Intent.$field
        }
        Assert-EzDarkFactoryTrue ($intent.identityGeneration -cne $fixture.Intent.identityGeneration)
        foreach ($path in @($paths.Runtime, $paths.FirmwareVariables, $ssh.AccessState, $paths.Operation)) { Assert-EzDarkFactoryEqual (Test-Path -LiteralPath $path) $false }
        Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText($ssh.InstanceKnownHosts)) 'previous promoted host identity'
        Assert-EzDarkFactoryEqual (Get-EzDarkFactorySnapshotFixturePayload $paths.Disk).data ''
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $fixture.Base.Image -Algorithm SHA256) $baseHash
        Assert-EzDarkFactoryEqual (@(Get-ChildItem -LiteralPath $paths.Directory -Force | Where-Object { $_.Name -match '^\.(disk-backup|reset)-' }).Count) 0
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Portability: failed reset disk promotion restores source and retains a startup recovery barrier' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    try {
        $before = Get-EzDarkFactoryFileDigest -Path $fixture.Disk -Algorithm SHA256
        $mover = {
            param($source, $destination)
            if ([IO.Path]::GetFileName($source).StartsWith('.disk-replacement-')) { throw 'injected replacement publication failure' }
            [IO.File]::Move($source, $destination)
        }
        Assert-EzDarkFactoryThrows {
            Reset-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName $fixture.Intent.name -QemuImgRunner $fixture.Runner -ProcessProvider { @() } -FileMover $mover
        } -MessagePattern 'Startup is blocked.*injected replacement' | Out-Null
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $fixture.Disk -Algorithm SHA256) $before
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryInstanceIntent -Root $fixture.Root -InstanceName $fixture.Intent.name).identityGeneration $fixture.Intent.identityGeneration
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryInstanceStatus -Root $fixture.Root -InstanceName $fixture.Intent.name -ProcessProvider { @() }).state 'UNKNOWN'
        $fixture.State.Calls.Clear()
        Assert-EzDarkFactoryThrows { Start-EzDarkFactoryInstance -Root $fixture.Root -InstanceName $fixture.Intent.name -QemuImgRunner $fixture.Runner -ProcessProvider { @() } } -MessagePattern 'cannot start.*UNKNOWN' | Out-Null
        Assert-EzDarkFactoryEqual $fixture.State.Calls.Count 0
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Portability: interrupted reset metadata preserves original disk intent and archived state and refuses repeat mutations' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    try {
        $paths = Get-EzDarkFactoryInstanceRuntimePaths -Root $fixture.Root -InstanceName $fixture.Intent.name
        $ssh = Get-EzDarkFactorySshPaths -Root $fixture.Root -InstanceName $fixture.Intent.name
        $null = Write-EzDarkFactoryPortabilityStoppedState $fixture
        [IO.File]::WriteAllText($ssh.AccessState, 'old access evidence')
        $original = Get-EzDarkFactoryFileDigest -Path $fixture.Disk -Algorithm SHA256
        $mover = {
            param($source, $destination)
            if ([IO.Path]::GetFileName($source) -ceq 'access.json') { throw 'injected metadata archive failure' }
            [IO.File]::Move($source, $destination)
        }
        Assert-EzDarkFactoryThrows { Reset-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName $fixture.Intent.name -QemuImgRunner $fixture.Runner -ProcessProvider { @() } -FileMover $mover } -MessagePattern 'Startup is blocked.*injected metadata' | Out-Null
        $journal = Read-EzDarkFactoryJson -Path $paths.Operation -SchemaVersion 1
        Assert-EzDarkFactoryEqual $journal.phase 'disk-replaced'
        Assert-EzDarkFactoryEqual $journal.originalIntent.identityGeneration $fixture.Intent.identityGeneration
        Assert-EzDarkFactoryTrue ($journal.targetIntent.identityGeneration -cne $fixture.Intent.identityGeneration)
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path (Join-Path $paths.Directory $journal.originalDisk) -Algorithm SHA256) $original
        Assert-EzDarkFactoryTrue (Test-Path -LiteralPath (Join-Path (Join-Path $paths.Directory $journal.archivedState) 'runtime.json'))
        $fixture.State.Calls.Clear()
        foreach ($operation in @(
            { Reset-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName $fixture.Intent.name -QemuImgRunner $fixture.Runner -ProcessProvider { @() } },
            { Copy-EzDarkFactoryManagedInstance -Root $fixture.Root -SourceInstanceName $fixture.Intent.name -DestinationInstanceName 'recovery-clone' -Mode fresh -QemuImgRunner $fixture.Runner -ProcessProvider { @() } },
            { Export-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName $fixture.Intent.name -DestinationDirectory (Join-Path $fixture.Root 'recovery-export') -QemuImgRunner $fixture.Runner -ProcessProvider { @() } },
            { Test-EzDarkFactoryPortableBundle -Root $fixture.Root -QemuImgRunner $fixture.Runner -ProcessProvider { @() } }
        )) { Assert-EzDarkFactoryThrows $operation -MessagePattern 'lifecycle state is.*unknown' | Out-Null }
        Assert-EzDarkFactoryEqual $fixture.State.Calls.Count 0
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Portability: schema1 intent reads preserve bytes and explicit reset upgrades identity once' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    try {
        $paths = Get-EzDarkFactoryInstanceRuntimePaths -Root $fixture.Root -InstanceName $fixture.Intent.name
        $legacy = $fixture.Intent | Select-Object -Property * -ExcludeProperty identityGeneration
        $legacy.schemaVersion = 1
        Write-EzDarkFactoryJson -Path $paths.Intent -Value $legacy -SchemaVersion 1
        $before = Get-EzDarkFactoryFileDigest -Path $paths.Intent -Algorithm SHA256
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryInstanceIntent -Root $fixture.Root -InstanceName $fixture.Intent.name).schemaVersion 1
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $paths.Intent -Algorithm SHA256) $before
        $reset = Reset-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName $fixture.Intent.name -QemuImgRunner $fixture.Runner -ProcessProvider { @() }
        Assert-EzDarkFactoryTrue ($reset.identityGeneration -cmatch '^[a-f0-9]{32}$')
        $current = Get-EzDarkFactoryInstanceIntent -Root $fixture.Root -InstanceName $fixture.Intent.name
        Assert-EzDarkFactoryEqual $current.schemaVersion 2
        Assert-EzDarkFactoryEqual $current.createdAt $legacy.createdAt
        Assert-EzDarkFactoryEqual $current.identityGeneration $reset.identityGeneration
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Portability: running stale and ambiguous sources refuse all storage operations without changing source bytes' -ScriptBlock {
    foreach ($kind in @('running', 'stale', 'unknown')) {
        $fixture = New-EzDarkFactoryRuntimeFixture
        try {
            $null = Start-EzDarkFactoryRuntimeFixtureInstance $fixture
            $provider = $fixture.ProcessProvider
            if ($kind -ceq 'stale') { $fixture.State.Processes.Clear() }
            if ($kind -ceq 'unknown') { $provider = { throw 'process evidence unavailable' } }
            $before = Get-EzDarkFactoryFileDigest -Path $fixture.Overlay -Algorithm SHA256
            $neverImage = { throw 'unexpected qemu-img invocation' }
            foreach ($operation in @(
                { Reset-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName $fixture.InstanceName -QemuImgRunner $neverImage -ProcessProvider $provider },
                { Copy-EzDarkFactoryManagedInstance -Root $fixture.Root -SourceInstanceName $fixture.InstanceName -DestinationInstanceName 'fresh-refused' -Mode fresh -QemuImgRunner $neverImage -ProcessProvider $provider },
                { Copy-EzDarkFactoryManagedInstance -Root $fixture.Root -SourceInstanceName $fixture.InstanceName -DestinationInstanceName 'stateful-refused' -Mode stateful -QemuImgRunner $neverImage -ProcessProvider $provider },
                { Export-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName $fixture.InstanceName -DestinationDirectory (Join-Path $fixture.Root 'refused-export') -QemuImgRunner $neverImage -ProcessProvider $provider }
            )) { Assert-EzDarkFactoryThrows $operation -MessagePattern 'requires positively proven stopped' | Out-Null }
            Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $fixture.Overlay -Algorithm SHA256) $before
        }
        finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
    }
}

Add-EzDarkFactoryTest -Name 'Portability: external backing refuses every new public source operation before qemu-img traversal' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    try {
        Write-EzDarkFactorySnapshotFixtureImage -Path $fixture.Disk -Backing '../../outside.qcow2' -Data 'preserve me'
        $before = Get-EzDarkFactoryFileDigest -Path $fixture.Disk -Algorithm SHA256
        foreach ($operation in @(
            { Reset-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName $fixture.Intent.name -QemuImgRunner $fixture.Runner -ProcessProvider { @() } },
            { Copy-EzDarkFactoryManagedInstance -Root $fixture.Root -SourceInstanceName $fixture.Intent.name -DestinationInstanceName 'bad-fresh' -Mode fresh -QemuImgRunner $fixture.Runner -ProcessProvider { @() } },
            { Copy-EzDarkFactoryManagedInstance -Root $fixture.Root -SourceInstanceName $fixture.Intent.name -DestinationInstanceName 'bad-stateful' -Mode stateful -QemuImgRunner $fixture.Runner -ProcessProvider { @() } },
            { Export-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName $fixture.Intent.name -DestinationDirectory (Join-Path $fixture.Root 'bad-export') -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider -ProcessProvider { @() } },
            { Test-EzDarkFactoryPortableBundle -Root $fixture.Root -QemuImgRunner $fixture.Runner -ProcessProvider { @() } }
        )) { Assert-EzDarkFactoryThrows $operation -MessagePattern 'does not exactly match' | Out-Null }
        Assert-EzDarkFactoryEqual $fixture.State.Calls.Count 0
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $fixture.Disk -Algorithm SHA256) $before
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Portability: public import consumes discovered export sidecar and preserves source on corrupt sidecar refusal' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    try {
        $export = Export-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName $fixture.Intent.name -DestinationDirectory (Join-Path $fixture.Root 'portable export') -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider -ProcessProvider { @() }
        $import = Import-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName 'import-destination' -ImagePath $export.Image -Profile light -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider -PortProbe { $true }
        $origin = Read-EzDarkFactoryJson -Path (Get-EzDarkFactoryInstanceRuntimePaths -Root $fixture.Root -InstanceName $import.name).Origin -SchemaVersion 1
        Assert-EzDarkFactoryEqual $origin.operation 'import'
        Assert-EzDarkFactoryEqual $origin.sourceInstance $null
        Assert-EzDarkFactoryEqual $origin.snapshot.source.exportManifest.source.instance.name $fixture.Intent.name
        Assert-EzDarkFactoryEqual $origin.snapshot.source.exportManifestSha256 (Get-EzDarkFactoryFileDigest -Path $export.ManifestPath -Algorithm SHA256)
        Assert-EzDarkFactoryEqual $import.sourceKind 'imported'
        Assert-EzDarkFactoryTrue ($import.identityGeneration -cne $fixture.Intent.identityGeneration)
        $before = Get-EzDarkFactoryFileDigest -Path $export.Image -Algorithm SHA256
        [IO.File]::WriteAllText($export.ManifestPath, '{"schemaVersion":1,"invalid":true}')
        $fixture.State.Calls.Clear()
        Assert-EzDarkFactoryThrows { Import-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName 'corrupt-import' -ImagePath $export.Image -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider } -MessagePattern 'field' | Out-Null
        Assert-EzDarkFactoryEqual $fixture.State.Calls.Count 0
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $export.Image -Algorithm SHA256) $before
        Assert-EzDarkFactoryEqual (Test-Path -LiteralPath (Get-EzDarkFactoryInstanceRuntimePaths -Root $fixture.Root -InstanceName 'corrupt-import').Directory) $false
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Portability: duplicate destinations refuse before copy import or source inspection' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    try {
        $before = Get-EzDarkFactoryFileDigest -Path $fixture.Disk -Algorithm SHA256
        $fixture.State.Calls.Clear()
        Assert-EzDarkFactoryThrows { Copy-EzDarkFactoryManagedInstance -Root $fixture.Root -SourceInstanceName 'missing-source' -DestinationInstanceName $fixture.Intent.name.ToUpperInvariant() -Mode stateful -QemuImgRunner $fixture.Runner } -MessagePattern 'already exists' | Out-Null
        Assert-EzDarkFactoryThrows { Import-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName $fixture.Intent.name -ImagePath 'does-not-exist.qcow2' -QemuImgRunner $fixture.Runner } -MessagePattern 'already exists' | Out-Null
        Assert-EzDarkFactoryEqual $fixture.State.Calls.Count 0
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $fixture.Disk -Algorithm SHA256) $before
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Portability: sensitive snapshots never become the implicit prepared baseline' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    try {
        Assert-EzDarkFactoryThrows { New-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName 'implicit-sensitive' -QemuImgRunner $fixture.Runner -PortProbe { $true } } -MessagePattern 'No published prepared base' | Out-Null
        $explicit = New-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName 'explicit-sensitive' -BaseId $fixture.Base.BaseId -QemuImgRunner $fixture.Runner -PortProbe { $true }
        Assert-EzDarkFactoryEqual $explicit.baseId $fixture.Base.BaseId
        Assert-EzDarkFactoryEqual $explicit.baseSelection 'explicit'
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Portability: complete cold root relocation retains intent relative backing stopped history and scoped keys' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    $moved = New-EzDarkFactoryTestDirectory -Prefix 'relocated complete root'
    try {
        $null = Write-EzDarkFactoryPortabilityStoppedState $fixture
        $ssh = Get-EzDarkFactorySshPaths -Root $fixture.Root -InstanceName $fixture.Intent.name
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($ssh.InstanceKnownHosts))
        [IO.File]::WriteAllText($ssh.InstanceKnownHosts, 'complete root scoped trust')
        $before = Test-EzDarkFactoryPortableBundle -Root $fixture.Root -QemuImgRunner $fixture.Runner -ProcessProvider { @() }
        Assert-EzDarkFactoryEqual $before.Valid $true
        foreach ($entry in @(Get-ChildItem -LiteralPath $fixture.Root -Force)) { Copy-Item -LiteralPath $entry.FullName -Destination $moved -Recurse -Force }
        $after = Test-EzDarkFactoryPortableBundle -Root $moved -QemuImgRunner $fixture.Runner -ProcessProvider { @() }
        Assert-EzDarkFactoryEqual $after.InstanceCount 1
        Assert-EzDarkFactoryEqual $after.Instances[0].state 'STOPPED'
        Assert-EzDarkFactoryEqual $after.Instances[0].chainDepth 1
        $originalPaths = Get-EzDarkFactoryInstanceRuntimePaths -Root $fixture.Root -InstanceName $fixture.Intent.name
        $movedPaths = Get-EzDarkFactoryInstanceRuntimePaths -Root $moved -InstanceName $fixture.Intent.name
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $movedPaths.Intent -Algorithm SHA256) (Get-EzDarkFactoryFileDigest -Path $originalPaths.Intent -Algorithm SHA256)
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $movedPaths.Runtime -Algorithm SHA256) (Get-EzDarkFactoryFileDigest -Path $originalPaths.Runtime -Algorithm SHA256)
        $chain = Test-EzDarkFactoryInstanceStorage -Root $moved -InstanceName $fixture.Intent.name -BaseId $fixture.Intent.baseId -QemuImgRunner $fixture.Runner
        Assert-EzDarkFactoryTrue ($chain.ResolvedBackingPath.StartsWith($moved, [StringComparison]::Ordinal))
        Assert-EzDarkFactoryEqual (Get-EzDarkFactorySnapshotFixturePayload $movedPaths.Disk).backing (Get-EzDarkFactorySnapshotFixturePayload $originalPaths.Disk).backing
        Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText((Get-EzDarkFactorySshPaths -Root $moved -InstanceName $fixture.Intent.name).InstanceKnownHosts)) 'complete root scoped trust'
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture; Remove-EzDarkFactoryTestDirectory -Path $moved }
}

Add-EzDarkFactoryTest -Name 'Portability: cold bundle refuses an active base builder and unreadable QEMU ownership' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    try {
        foreach ($executable in @((Join-Path $fixture.Paths.Qemu 'qemu-system-x86_64.exe'), '')) {
            $process = [pscustomobject]@{ Pid = 40999; ExecutablePath = $executable; Arguments = @('-name', 'ezdarkfactory-base-builder'); StartTimeUtc = [DateTime]::UtcNow.ToString('o') }
            $provider = { @($process) }.GetNewClosure()
            Assert-EzDarkFactoryThrows { Test-EzDarkFactoryPortableBundle -Root $fixture.Root -QemuImgRunner $fixture.Runner -ProcessProvider $provider } -MessagePattern 'requires every managed QEMU|ownership is unavailable' | Out-Null
        }
        Assert-EzDarkFactoryEqual $fixture.State.Calls.Count 0
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Portability: stale seed intent cannot launch after reset changed generation' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        $expected = Get-EzDarkFactoryInstanceIntent -Root $fixture.Root -InstanceName $fixture.InstanceName
        $current = Get-EzDarkFactoryInstanceIntent -Root $fixture.Root -InstanceName $fixture.InstanceName
        $current.identityGeneration = [Guid]::NewGuid().ToString('N')
        Write-EzDarkFactoryJson -Path (Get-EzDarkFactoryInstanceRuntimePaths -Root $fixture.Root -InstanceName $fixture.InstanceName).Intent -Value $current -SchemaVersion 2
        Assert-EzDarkFactoryThrows { Start-EzDarkFactoryInstance -Root $fixture.Root -InstanceName $fixture.InstanceName -ExpectedIntent $expected -QemuImgRunner $fixture.StorageRunner -QemuStatusProvider $fixture.QemuStatusProvider -ProcessProvider $fixture.ProcessProvider -ProcessLauncher $fixture.ProcessLauncher -QmpInvoker $fixture.QmpInvoker } -MessagePattern 'intent changed while preparing' | Out-Null
        Assert-EzDarkFactoryEqual $fixture.State.LaunchCount 0
    }
    finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Portability: relocated metadata cannot hide original-root active stale or unrecorded owners' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    $moved = New-EzDarkFactoryTestDirectory -Prefix 'relocated ownership'
    try {
        $null = Start-EzDarkFactoryRuntimeFixtureInstance $fixture
        $owner = $fixture.State.Processes[0]
        foreach ($entry in @(Get-ChildItem -LiteralPath $fixture.Root -Force)) { Copy-Item -LiteralPath $entry.FullName -Destination $moved -Recurse -Force }
        $movedPaths = Get-EzDarkFactoryInstanceRuntimePaths -Root $moved -InstanceName $fixture.InstanceName
        foreach ($state in @('RUNNING', 'STALE', 'UNKNOWN')) {
            if ($state -ceq 'STALE') { $fixture.State.Processes.Clear() }
            if ($state -ceq 'UNKNOWN') {
                $fixture.State.Processes.Add($owner)
                $runtime = Read-EzDarkFactoryJson -Path $movedPaths.Runtime -SchemaVersion 1
                $runtime.state = 'STOPPED'; $runtime.stoppedAt = [DateTime]::UtcNow.ToString('o')
                Write-EzDarkFactoryJson -Path $movedPaths.Runtime -Value $runtime -SchemaVersion 1
            }
            Assert-EzDarkFactoryEqual (Get-EzDarkFactoryInstanceStatus -Root $moved -InstanceName $fixture.InstanceName -ProcessProvider $fixture.ProcessProvider).state $state
            $neverImage = { throw 'unexpected qemu-img traversal of owned storage' }
            Assert-EzDarkFactoryThrows { Test-EzDarkFactoryPortableBundle -Root $moved -QemuImgRunner $neverImage -ProcessProvider $fixture.ProcessProvider } -MessagePattern 'requires positively proven stopped' | Out-Null
            Assert-EzDarkFactoryThrows { Reset-EzDarkFactoryManagedInstance -Root $moved -InstanceName $fixture.InstanceName -QemuImgRunner $neverImage -ProcessProvider $fixture.ProcessProvider } -MessagePattern 'requires positively proven stopped' | Out-Null
        }
    }
    finally { Remove-EzDarkFactoryRuntimeFixture $fixture; Remove-EzDarkFactoryTestDirectory -Path $moved }
}

Add-EzDarkFactoryTest -Name 'Portability: lifecycle guards reject coerced schema and redirected lock directories before any outside write' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'portability lock guard'
    $outside = New-EzDarkFactoryTestDirectory -Prefix 'portability outside'
    $link = $null
    try {
        $module = Get-Module EzDarkFactory
        foreach ($schema in @('1', $true, 1.0)) {
            $guard = [pscustomobject]@{ schemaVersion = $schema; state = 'proven-safe'; source = 'invalid typed schema' }
            Assert-EzDarkFactoryThrows { & $module { param($g) Assert-EzDarkFactoryStorageLifecycleGuard -LifecycleGuard $g -Operation 'test mutation' } $guard } -MessagePattern 'unsupported lifecycle-guard schema' | Out-Null
        }
        $paths = Get-EzDarkFactoryPaths -Root $root
        [void][IO.Directory]::CreateDirectory($paths.Runtime)
        $link = $paths.Locks
        $linkType = if ($script:EzDarkFactoryIsWindowsHost) { 'Junction' } else { 'SymbolicLink' }
        $null = New-Item -ItemType $linkType -Path $link -Target $outside -ErrorAction Stop
        foreach ($function in @('Enter-EzDarkFactoryInstanceLifecycleLock', 'Enter-EzDarkFactoryQmpAllocationLock')) {
            Assert-EzDarkFactoryThrows { & $module { param($r, $f) if ($f -ceq 'Enter-EzDarkFactoryInstanceLifecycleLock') { $lock = & $f -Root $r -InstanceName 'safe-name' } else { $lock = & $f -Root $r }; $lock.Dispose() } $root $function } -MessagePattern 'reparse point' | Out-Null
        }
        Assert-EzDarkFactoryEqual (@(Get-ChildItem -LiteralPath $outside -Force).Count) 0
    }
    finally {
        if ($null -ne $link -and (Test-Path -LiteralPath $link)) { [IO.Directory]::Delete($link) }
        Remove-EzDarkFactoryTestDirectory -Path $root
        Remove-EzDarkFactoryTestDirectory -Path $outside
    }
}
