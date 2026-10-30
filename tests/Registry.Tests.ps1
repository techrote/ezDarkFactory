function New-EzDarkFactoryRegistryFixture {
    $baseFixture = New-EzDarkFactoryBaseBuildFixture
    $base = Invoke-EzDarkFactoryBaseBuild -Root $baseFixture.Root -Accelerator tcg -BuildTimeoutSeconds 60 -QemuStatusProvider $baseFixture.QemuStatusProvider -SourceProvider $baseFixture.SourceProvider -QemuImgRunner $baseFixture.QemuImgRunner -GuestRunner $baseFixture.GuestRunner
    $baseRunner = $baseFixture.QemuImgRunner

    $storageRunner = {
        param($argumentList)
        $arguments = @($argumentList)
        $command = $arguments[0]
        if ($command -ceq 'create' -and $arguments -ccontains '-b') {
            $destination = [IO.Path]::GetFullPath($arguments[$arguments.Count - 1])
            $backingIndex = [Array]::IndexOf($arguments, '-b')
            $backing = [string]$arguments[$backingIndex + 1]
            $payload = [pscustomobject][ordered]@{ kind = 'registry-overlay'; backing = $backing }
            [IO.File]::WriteAllText($destination, ($payload | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
            return [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
        }
        if ($command -ceq 'info') {
            $path = [IO.Path]::GetFullPath($arguments[$arguments.Count - 1])
            $payload = $null
            try {
                $text = [IO.File]::ReadAllText($path)
                if ($text.StartsWith('{', [StringComparison]::Ordinal)) { $payload = $text | ConvertFrom-Json -ErrorAction Stop }
            } catch { $payload = $null }
            if ($null -ne $payload -and $payload.kind -ceq 'registry-overlay') {
                $resolved = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($path)) ([string]$payload.backing)))
                $top = [pscustomobject][ordered]@{
                    filename = $path
                    format = 'qcow2'
                    'virtual-size' = [long]17179869184
                    'backing-filename' = [string]$payload.backing
                    'backing-filename-format' = 'qcow2'
                }
                $baseInfo = [pscustomobject][ordered]@{
                    filename = $resolved
                    format = 'qcow2'
                    'virtual-size' = [long]17179869184
                }
                if ($arguments -ccontains '--backing-chain') {
                    return [pscustomobject]@{ ExitCode = 0; StdOut = (@($top, $baseInfo) | ConvertTo-Json -Compress); StdErr = '' }
                }
                return [pscustomobject]@{ ExitCode = 0; StdOut = ($top | ConvertTo-Json -Compress); StdErr = '' }
            }
        }
        return & $baseRunner $arguments
    }.GetNewClosure()

    return [pscustomobject]@{
        BaseFixture = $baseFixture
        Root = $baseFixture.Root
        Paths = $baseFixture.Paths
        BaseId = $base.baseId
        StorageRunner = $storageRunner
        QemuStatusProvider = $baseFixture.QemuStatusProvider
    }
}

function Remove-EzDarkFactoryRegistryFixture {
    param([object]$Fixture)
    if ($null -ne $Fixture) { Remove-EzDarkFactoryBaseBuildFixture $Fixture.BaseFixture }
}

Add-EzDarkFactoryTest -Name 'Registry: portable instance names accept conservative values and reject traversal and Windows devices' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'registry names'
    try {
        foreach ($name in @('agent1', 'agent.one', 'AGENT_two-3')) {
            $paths = Get-EzDarkFactoryInstanceStoragePaths -Root $root -InstanceName $name
            Assert-EzDarkFactoryTrue -Condition ($paths.Directory.EndsWith($name, [StringComparison]::Ordinal))
        }
        foreach ($name in @('.', '..', '../escape', 'C:escape', 'bad/name', 'bad\name', 'NUL', 'con.txt', 'COM1', 'LPT9.log')) {
            Assert-EzDarkFactoryThrows -ScriptBlock {
                Get-EzDarkFactoryInstanceStoragePaths -Root $root -InstanceName $name
            } -MessagePattern 'invalid|reserved|unsafe' | Out-Null
        }
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Registry: profiles and explicit resource overrides resolve predictably' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'registry profiles'
    try {
        $light = Resolve-EzDarkFactoryInstanceResources -Root $root -Profile light
        Assert-EzDarkFactoryEqual -Actual $light.cpus -Expected 2
        Assert-EzDarkFactoryEqual -Actual $light.memoryMiB -Expected 4096

        $normal = Resolve-EzDarkFactoryInstanceResources -Root $root
        Assert-EzDarkFactoryEqual -Actual $normal.profile -Expected 'normal'
        Assert-EzDarkFactoryEqual -Actual $normal.cpus -Expected 4
        Assert-EzDarkFactoryEqual -Actual $normal.memoryMiB -Expected 8192

        $override = Resolve-EzDarkFactoryInstanceResources -Root $root -Profile heavy -Cpus 6 -MemoryMiB 12288
        Assert-EzDarkFactoryEqual -Actual $override.profile -Expected 'heavy'
        Assert-EzDarkFactoryEqual -Actual $override.cpus -Expected 6
        Assert-EzDarkFactoryEqual -Actual $override.memoryMiB -Expected 12288

        Assert-EzDarkFactoryThrows -ScriptBlock { Resolve-EzDarkFactoryInstanceResources -Root $root -Profile enormous } -MessagePattern 'invalid' | Out-Null
        Assert-EzDarkFactoryThrows -ScriptBlock { Resolve-EzDarkFactoryInstanceResources -Root $root -Profile normal -Cpus 0 } -MessagePattern 'integer from 1' | Out-Null
        Assert-EzDarkFactoryThrows -ScriptBlock { Resolve-EzDarkFactoryInstanceResources -Root $root -Profile normal -MemoryMiB 256 } -MessagePattern 'integer from 512' | Out-Null
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Registry: managed create persists complete relocatable intent and one-level overlay' -ScriptBlock {
    $fixture = New-EzDarkFactoryRegistryFixture
    try {
        $created = New-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName 'agent-one' -BaseId $fixture.BaseId -Profile light -Cpus 3 -MemoryMiB 6144 -QemuImgRunner $fixture.StorageRunner -PortProbe { param($port) return $true }
        Assert-EzDarkFactoryEqual -Actual $created.profile -Expected 'light'
        Assert-EzDarkFactoryEqual -Actual $created.cpus -Expected 3
        Assert-EzDarkFactoryEqual -Actual $created.memoryMiB -Expected 6144
        Assert-EzDarkFactoryEqual -Actual $created.sshPort -Expected 22000
        Assert-EzDarkFactoryEqual -Actual $created.chainDepth -Expected 1

        $intent = Get-EzDarkFactoryInstanceIntent -Root $fixture.Root -InstanceName 'agent-one'
        Assert-EzDarkFactoryEqual -Actual $intent.profile -Expected 'light'
        Assert-EzDarkFactoryEqual -Actual $intent.sshPort -Expected 22000
        Assert-EzDarkFactoryEqual -Actual $intent.provisioningProfile -Expected 'fresh-project'
        Assert-EzDarkFactoryEqual -Actual $intent.provisioningVersion -Expected 1
        $intentPath = (Get-EzDarkFactoryInstanceRuntimePaths -Root $fixture.Root -InstanceName 'agent-one').Intent
        $json = [IO.File]::ReadAllText($intentPath)
        Assert-EzDarkFactoryTrue -Condition ($json -notmatch [regex]::Escape([IO.Path]::GetFullPath($fixture.Root))) -Message 'Durable instance intent must not persist the checkout root.'
    }
    finally { Remove-EzDarkFactoryRegistryFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Registry: several instances receive unique persistent ports from one allocation authority' -ScriptBlock {
    $fixture = New-EzDarkFactoryRegistryFixture
    try {
        $created = @()
        foreach ($name in @('agent-a', 'agent-b', 'agent-c', 'agent-d')) {
            $created += New-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName $name -BaseId $fixture.BaseId -Profile light -QemuImgRunner $fixture.StorageRunner -PortProbe { param($port) return $true }
        }
        Assert-EzDarkFactoryEqual -Actual @($created | ForEach-Object { $_.sshPort }) -Expected @(22000, 22001, 22002, 22003)
        Assert-EzDarkFactoryEqual -Actual @(Get-EzDarkFactoryAllocatedSshPorts -Root $fixture.Root | Sort-Object) -Expected @(22000, 22001, 22002, 22003)
        Assert-EzDarkFactoryEqual -Actual @(Get-EzDarkFactoryInstanceRegistry -Root $fixture.Root).Count -Expected 4
    }
    finally { Remove-EzDarkFactoryRegistryFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Registry: allocation skips a real unrelated loopback listener' -ScriptBlock {
    $fixture = New-EzDarkFactoryRegistryFixture
    $listener = $null
    try {
        $firstPort = $null
        for ($candidate = 30000; $candidate -lt 50000; $candidate += 2) {
            $a = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $candidate)
            $b = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, ($candidate + 1))
            try {
                $a.Server.ExclusiveAddressUse = $true
                $b.Server.ExclusiveAddressUse = $true
                $a.Start()
                $b.Start()
                $firstPort = $candidate
                $listener = $a
                $a = $null
                $b.Stop()
                $b = $null
                break
            }
            catch { }
            finally {
                if ($null -ne $a) { try { $a.Stop() } catch { } }
                if ($null -ne $b) { try { $b.Stop() } catch { } }
            }
        }
        Assert-EzDarkFactoryTrue -Condition ($null -ne $firstPort) -Message 'Fixture could not reserve a consecutive loopback port pair.'

        [void][IO.Directory]::CreateDirectory($fixture.Paths.Runtime)
        $override = [pscustomobject][ordered]@{
            schemaVersion = 1
            ssh = [pscustomobject][ordered]@{ portRangeStart = $firstPort; portRangeEnd = ($firstPort + 1) }
        }
        Write-EzDarkFactoryJson -Path $fixture.Paths.UserConfig -Value $override -SchemaVersion 1

        $created = New-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName 'collision-safe' -BaseId $fixture.BaseId -Profile light -QemuImgRunner $fixture.StorageRunner
        Assert-EzDarkFactoryEqual -Actual $created.sshPort -Expected ($firstPort + 1)
    }
    finally {
        if ($null -ne $listener) { try { $listener.Stop() } catch { } }
        Remove-EzDarkFactoryRegistryFixture $fixture
    }
}

Add-EzDarkFactoryTest -Name 'Registry: allocation lock serializes competing creators and stale lock files are reusable' -ScriptBlock {
    $fixture = New-EzDarkFactoryRegistryFixture
    try {
        $module = Get-Module EzDarkFactory
        $held = & $module { param($root) Enter-EzDarkFactorySshAllocationLock -Root $root -TimeoutMilliseconds 500 } $fixture.Root
        try {
            Assert-EzDarkFactoryThrows -ScriptBlock {
                & $module { param($root) Enter-EzDarkFactorySshAllocationLock -Root $root -TimeoutMilliseconds 100 } $fixture.Root
            } -MessagePattern 'Timed out waiting for the ezdarkfactory SSH port-allocation lock' | Out-Null
        }
        finally { $held.Dispose() }

        $again = & $module { param($root) Enter-EzDarkFactorySshAllocationLock -Root $root -TimeoutMilliseconds 500 } $fixture.Root
        try { Assert-EzDarkFactoryTrue -Condition ($null -ne $again) }
        finally { $again.Dispose() }

        $created = New-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName 'after-stale-lock' -BaseId $fixture.BaseId -Profile light -QemuImgRunner $fixture.StorageRunner -PortProbe { param($port) return $true }
        Assert-EzDarkFactoryEqual -Actual $created.sshPort -Expected 22000
    }
    finally { Remove-EzDarkFactoryRegistryFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Registry: reconstruction survives root relocation and fails on directory-intent disagreement' -ScriptBlock {
    $fixture = New-EzDarkFactoryRegistryFixture
    $relocated = $null
    try {
        $null = New-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName 'portable-agent' -BaseId $fixture.BaseId -Profile normal -QemuImgRunner $fixture.StorageRunner -PortProbe { param($port) return $true }

        $relocated = New-EzDarkFactoryTestDirectory -Prefix 'registry relocated'
        Remove-Item -LiteralPath $relocated -Recurse -Force
        Copy-Item -LiteralPath $fixture.Root -Destination $relocated -Recurse -Force
        $rebuilt = @(Get-EzDarkFactoryInstanceRegistry -Root $relocated)
        Assert-EzDarkFactoryEqual -Actual $rebuilt.Count -Expected 1
        Assert-EzDarkFactoryEqual -Actual $rebuilt[0].name -Expected 'portable-agent'
        Assert-EzDarkFactoryEqual -Actual $rebuilt[0].sshPort -Expected 22000

        $intentPath = (Get-EzDarkFactoryInstanceRuntimePaths -Root $relocated -InstanceName 'portable-agent').Intent
        $intent = Read-EzDarkFactoryJson -Path $intentPath -SchemaVersion 2
        $intent.name = 'other-agent'
        Write-EzDarkFactoryJson -Path $intentPath -Value $intent -SchemaVersion 2
        Assert-EzDarkFactoryThrows -ScriptBlock { Get-EzDarkFactoryInstanceRegistry -Root $relocated } -MessagePattern 'does not match managed instance' | Out-Null
    }
    finally {
        if ($null -ne $relocated) { Remove-EzDarkFactoryTestDirectory -Path $relocated }
        Remove-EzDarkFactoryRegistryFixture $fixture
    }
}

Add-EzDarkFactoryTest -Name 'Registry: duplicate durable SSH reservations fail reconstruction instead of colliding silently' -ScriptBlock {
    $fixture = New-EzDarkFactoryRegistryFixture
    try {
        $null = New-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName 'dup-one' -BaseId $fixture.BaseId -Profile light -QemuImgRunner $fixture.StorageRunner -PortProbe { param($port) return $true }
        $null = New-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName 'dup-two' -BaseId $fixture.BaseId -Profile light -QemuImgRunner $fixture.StorageRunner -PortProbe { param($port) return $true }
        $secondPath = (Get-EzDarkFactoryInstanceRuntimePaths -Root $fixture.Root -InstanceName 'dup-two').Intent
        $second = Read-EzDarkFactoryJson -Path $secondPath -SchemaVersion 2
        $second.sshPort = 22000
        Write-EzDarkFactoryJson -Path $secondPath -Value $second -SchemaVersion 2
        Assert-EzDarkFactoryThrows -ScriptBlock { Get-EzDarkFactoryInstanceRegistry -Root $fixture.Root } -MessagePattern 'both reserve SSH port 22000' | Out-Null
    }
    finally { Remove-EzDarkFactoryRegistryFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Registry: legacy EDF-006 intent is refused with explicit migration guidance' -ScriptBlock {
    $fixture = New-EzDarkFactoryRegistryFixture
    try {
        $runtimePaths = Get-EzDarkFactoryInstanceRuntimePaths -Root $fixture.Root -InstanceName 'legacy-agent'
        [void][IO.Directory]::CreateDirectory($runtimePaths.Directory)
        $legacy = [pscustomobject][ordered]@{
            schemaVersion = 1
            name = 'legacy-agent'
            baseId = $fixture.BaseId
            cpus = 2
            memoryMiB = 4096
            createdAt = [DateTime]::UtcNow.ToString('o')
        }
        Write-EzDarkFactoryJson -Path $runtimePaths.Intent -Value $legacy -SchemaVersion 1
        Assert-EzDarkFactoryThrows -ScriptBlock { Get-EzDarkFactoryInstanceIntent -Root $fixture.Root -InstanceName 'legacy-agent' } -MessagePattern 'legacy EDF-006 schema.*recreate or deliberately migrate' | Out-Null
    }
    finally { Remove-EzDarkFactoryRegistryFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Registry: multiple named instances can enter RUNNING independently with distinct durable SSH resources' -ScriptBlock {
    $fixture = New-EzDarkFactoryRegistryFixture
    try {
        $one = New-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName 'run-one' -BaseId $fixture.BaseId -Profile light -QemuImgRunner $fixture.StorageRunner -PortProbe { param($port) return $true }
        $two = New-EzDarkFactoryManagedInstance -Root $fixture.Root -InstanceName 'run-two' -BaseId $fixture.BaseId -Profile light -QemuImgRunner $fixture.StorageRunner -PortProbe { param($port) return $true }

        $state = [pscustomobject]@{
            Processes = New-Object 'System.Collections.Generic.List[object]'
            NextPid = 47000
        }
        $processState = $state
        $launcher = {
            param($filePath, $arguments, $workingDirectory)
            $pidValue = $processState.NextPid
            $processState.NextPid++
            $started = [DateTime]::UtcNow.ToString('o')
            $processState.Processes.Add([pscustomobject]@{
                Pid = $pidValue
                ExecutablePath = [IO.Path]::GetFullPath($filePath)
                Arguments = [string[]]@($arguments)
                StartTimeUtc = $started
            })
            return [pscustomobject]@{ Pid = $pidValue; StartTimeUtc = $started }
        }.GetNewClosure()
        $provider = {
            param($processId)
            if ($null -eq $processId) { return @($processState.Processes.ToArray()) }
            return @($processState.Processes.ToArray() | Where-Object { $_.Pid -eq [int]$processId })
        }.GetNewClosure()
        $qmp = {
            param($hostAddress, $port, $command, $timeoutMilliseconds)
            if ($command -ceq 'query-status') { return [pscustomobject]@{ status = 'running'; running = $true } }
            if ($command -ceq 'system_powerdown') { return [pscustomobject]@{} }
            throw "unexpected QMP command $command"
        }

        $s1 = Start-EzDarkFactoryInstance -Root $fixture.Root -InstanceName 'run-one' -Accelerator tcg -StartupTimeoutSeconds 3 -QemuImgRunner $fixture.StorageRunner -QemuStatusProvider $fixture.QemuStatusProvider -ProcessProvider $provider -ProcessLauncher $launcher -QmpInvoker $qmp -SshPort $one.sshPort
        $s2 = Start-EzDarkFactoryInstance -Root $fixture.Root -InstanceName 'run-two' -Accelerator tcg -StartupTimeoutSeconds 3 -QemuImgRunner $fixture.StorageRunner -QemuStatusProvider $fixture.QemuStatusProvider -ProcessProvider $provider -ProcessLauncher $launcher -QmpInvoker $qmp -SshPort $two.sshPort

        Assert-EzDarkFactoryTrue -Condition ($s1.pid -ne $s2.pid)
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryInstanceStatus -Root $fixture.Root -InstanceName 'run-one' -ProcessProvider $provider).state -Expected 'RUNNING'
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryInstanceStatus -Root $fixture.Root -InstanceName 'run-two' -ProcessProvider $provider).state -Expected 'RUNNING'
        Assert-EzDarkFactoryTrue -Condition ($one.sshPort -ne $two.sshPort)
        Assert-EzDarkFactoryTrue -Condition ((@($state.Processes[0].Arguments) -join ' ') -match ('hostfwd=tcp:127\.0\.0\.1:' + $one.sshPort + '-:22'))
        Assert-EzDarkFactoryTrue -Condition ((@($state.Processes[1].Arguments) -join ' ') -match ('hostfwd=tcp:127\.0\.0\.1:' + $two.sshPort + '-:22'))
    }
    finally { Remove-EzDarkFactoryRegistryFixture $fixture }
}
