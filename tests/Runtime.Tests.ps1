function New-EzDarkFactoryRuntimeFixture {
    $baseFixture = New-EzDarkFactoryBaseBuildFixture
    $baseResult = Invoke-EzDarkFactoryBaseBuild -Root $baseFixture.Root -Accelerator tcg -BuildTimeoutSeconds 60 -QemuStatusProvider $baseFixture.QemuStatusProvider -SourceProvider $baseFixture.SourceProvider -QemuImgRunner $baseFixture.QemuImgRunner -GuestRunner $baseFixture.GuestRunner
    $state = [pscustomobject]@{
        Processes = New-Object 'System.Collections.Generic.List[object]'
        QmpCalls = New-Object 'System.Collections.Generic.List[string]'
        LaunchCount = 0
        NextPid = 41000
        QmpReady = $true
        QmpRunning = $true
        PowerdownExits = $true
        QmpFailure = $null
    }
    $baseRunner = $baseFixture.QemuImgRunner

    $storageRunner = {
        param($argumentList)
        $arguments = @($argumentList)
        $command = $arguments[0]
        if ($command -ceq 'create') {
            $destination = [IO.Path]::GetFullPath($arguments[$arguments.Count - 1])
            $backingIndex = [Array]::IndexOf($arguments, '-b')
            $backing = $arguments[$backingIndex + 1]
            $payload = [pscustomobject][ordered]@{ kind = 'runtime-overlay'; backing = $backing }
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
            if ($null -ne $payload -and $payload.kind -ceq 'runtime-overlay') {
                $resolved = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($path)) ([string]$payload.backing)))
                $top = [pscustomobject][ordered]@{
                    filename = $path
                    format = 'qcow2'
                    'virtual-size' = [long]17179869184
                    'backing-filename' = [string]$payload.backing
                    'backing-filename-format' = 'qcow2'
                }
                $base = [pscustomobject][ordered]@{
                    filename = $resolved
                    format = 'qcow2'
                    'virtual-size' = [long]17179869184
                }
                if ($arguments -ccontains '--backing-chain') {
                    return [pscustomobject]@{ ExitCode = 0; StdOut = (@($top, $base) | ConvertTo-Json -Compress); StdErr = '' }
                }
                return [pscustomobject]@{ ExitCode = 0; StdOut = ($top | ConvertTo-Json -Compress); StdErr = '' }
            }
        }
        return & $baseRunner $arguments
    }.GetNewClosure()

    $instanceName = 'runtime-agent'
    $null = New-EzDarkFactoryInstanceIntent -Root $baseFixture.Root -InstanceName $instanceName -BaseId $baseResult.baseId -Cpus 2 -MemoryMiB 2048 -QemuImgRunner $storageRunner
    $guard = New-EzDarkFactoryStorageLifecycleGuard -State 'proven-safe' -Source 'runtime fixture has no QEMU owner'
    $overlay = New-EzDarkFactoryInstanceOverlay -Root $baseFixture.Root -InstanceName $instanceName -BaseId $baseResult.baseId -LifecycleGuard $guard -QemuImgRunner $storageRunner

    $qemuStatusProvider = {
        param($fixtureRoot)
        $paths = Get-EzDarkFactoryPaths -Root $fixtureRoot
        [pscustomobject]@{
            Valid = $true
            Reason = 'runtime fixture managed QEMU'
            QemuSystem = Join-Path $paths.Qemu 'qemu-system-x86_64.exe'
            QemuImg = Join-Path $paths.Qemu 'qemu-img.exe'
        }
    }

    $processState = $state
    $launcher = {
        param($filePath, $arguments, $workingDirectory)
        $processState.LaunchCount++
        $pidValue = $processState.NextPid
        $processState.NextPid++
        $started = [DateTime]::UtcNow.ToString('o')
        $processState.Processes.Add([pscustomobject]@{
            Pid = $pidValue
            ExecutablePath = [IO.Path]::GetFullPath($filePath)
            Arguments = [string[]]@($arguments)
            StartTimeUtc = $started
        })
        [pscustomobject]@{ Pid = $pidValue; StartTimeUtc = $started }
    }.GetNewClosure()

    $provider = {
        param($processId)
        if ($null -eq $processId) { return @($processState.Processes.ToArray()) }
        return @($processState.Processes.ToArray() | Where-Object { $_.Pid -eq [int]$processId })
    }.GetNewClosure()

    $qmp = {
        param($hostAddress, $port, $command, $timeoutMilliseconds)
        $processState.QmpCalls.Add($command)
        if ($null -ne $processState.QmpFailure) { throw [InvalidOperationException]::new([string]$processState.QmpFailure) }
        if ($command -ceq 'query-status') {
            if (-not $processState.QmpReady) { throw 'synthetic QMP not ready' }
            if ($processState.QmpRunning) { return [pscustomobject]@{ status = 'running'; running = $true } }
            return [pscustomobject]@{ status = 'paused'; running = $false }
        }
        if ($command -ceq 'system_powerdown') {
            if ($processState.PowerdownExits) { $processState.Processes.Clear() }
            return [pscustomobject]@{}
        }
        throw "unexpected fixture QMP command $command"
    }.GetNewClosure()

    return [pscustomobject]@{
        BaseFixture = $baseFixture
        Root = $baseFixture.Root
        Paths = $baseFixture.Paths
        BaseId = $baseResult.baseId
        InstanceName = $instanceName
        Overlay = $overlay.Disk
        StorageRunner = $storageRunner
        QemuStatusProvider = $qemuStatusProvider
        ProcessLauncher = $launcher
        ProcessProvider = $provider
        QmpInvoker = $qmp
        State = $state
    }
}

function Remove-EzDarkFactoryRuntimeFixture {
    param([object]$Fixture)
    if ($null -ne $Fixture) { Remove-EzDarkFactoryBaseBuildFixture $Fixture.BaseFixture }
}

function Start-EzDarkFactoryRuntimeFixtureInstance {
    param([object]$Fixture, [string]$Accelerator = 'whpx', [int]$Timeout = 3)
    return Start-EzDarkFactoryInstance -Root $Fixture.Root -InstanceName $Fixture.InstanceName -Accelerator $Accelerator -StartupTimeoutSeconds $Timeout -QemuImgRunner $Fixture.StorageRunner -QemuStatusProvider $Fixture.QemuStatusProvider -ProcessProvider $Fixture.ProcessProvider -ProcessLauncher $Fixture.ProcessLauncher -QmpInvoker $Fixture.QmpInvoker
}

function Get-EzDarkFactoryRuntimeFixtureState {
    param([object]$Fixture)
    $path = (Get-EzDarkFactoryInstanceRuntimePaths -Root $Fixture.Root -InstanceName $Fixture.InstanceName).Runtime
    return Read-EzDarkFactoryJson -Path $path -SchemaVersion 1
}

function Set-EzDarkFactoryRuntimeFixtureBacking {
    param([object]$Fixture, [string]$Backing)
    $payload = [IO.File]::ReadAllText($Fixture.Overlay) | ConvertFrom-Json -ErrorAction Stop
    $payload.backing = $Backing
    [IO.File]::WriteAllText($Fixture.Overlay, ($payload | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
}

Add-EzDarkFactoryTest -Name 'Runtime: QEMU arguments are explicit headless WHPX with loopback-only QMP' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        $intent = Get-EzDarkFactoryInstanceIntent -Root $fixture.Root -InstanceName $fixture.InstanceName
        $runtimePaths = Get-EzDarkFactoryInstanceRuntimePaths -Root $fixture.Root -InstanceName $fixture.InstanceName
        [void][IO.Directory]::CreateDirectory($runtimePaths.Logs)
        $firmware = Get-EzDarkFactoryRuntimeFirmwarePaths -Root $fixture.Root -InstanceName $fixture.InstanceName
        $port = 32123
        $args = New-EzDarkFactoryRuntimeQemuArguments -InstanceName $fixture.InstanceName -Intent $intent -Disk $fixture.Overlay -FirmwareCode $firmware.Code -FirmwareVariables $firmware.Variables -SerialLog (Join-Path $runtimePaths.Logs 'serial with spaces.log') -QemuLog (Join-Path $runtimePaths.Logs 'qemu with spaces.log') -QmpPort $port -Accelerator whpx
        $joined = ' ' + ($args -join ' ') + ' '
        Assert-EzDarkFactoryTrue -Condition ($joined -match ' -machine q35 ')
        Assert-EzDarkFactoryTrue -Condition ($joined -match ' -accel whpx ')
        Assert-EzDarkFactoryTrue -Condition ($joined -match ' -display none ')
        Assert-EzDarkFactoryTrue -Condition ($joined -match 'virtio-blk-pci,drive=osdisk')
        Assert-EzDarkFactoryTrue -Condition ($joined -match 'virtio-net-pci,netdev=net0')
        Assert-EzDarkFactoryTrue -Condition ($joined -match (' -qmp tcp:127\.0\.0\.1:' + $port + ',server=on,wait=off,nodelay=on '))
        Assert-EzDarkFactoryTrue -Condition ($joined -notmatch 'qmp tcp:(?!127\.0\.0\.1)') -Message 'QMP TCP must bind only to loopback.'
        Assert-EzDarkFactoryTrue -Condition ($joined -notmatch 'tcg') -Message 'Normal WHPX arguments must not silently degrade to TCG.'
        $diskToken = @($args | Where-Object { $_ -match '^if=none,id=osdisk' })[0]
        Assert-EzDarkFactoryTrue -Condition ($diskToken -match 'file=.*runtime-agent\\disk\.qcow2$')
        Assert-EzDarkFactoryTrue -Condition ($joined -match 'readonly=on.*edk2-x86_64-code\.fd')
    }
    finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Runtime: explicit TCG is visible and does not alter WHPX default' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        $intent = Get-EzDarkFactoryInstanceIntent -Root $fixture.Root -InstanceName $fixture.InstanceName
        $runtimePaths = Get-EzDarkFactoryInstanceRuntimePaths -Root $fixture.Root -InstanceName $fixture.InstanceName
        [void][IO.Directory]::CreateDirectory($runtimePaths.Logs)
        $firmware = Get-EzDarkFactoryRuntimeFirmwarePaths -Root $fixture.Root -InstanceName $fixture.InstanceName
        $port = 32124
        $args = New-EzDarkFactoryRuntimeQemuArguments -InstanceName $fixture.InstanceName -Intent $intent -Disk $fixture.Overlay -FirmwareCode $firmware.Code -FirmwareVariables $firmware.Variables -SerialLog (Join-Path $runtimePaths.Logs 'serial.log') -QemuLog (Join-Path $runtimePaths.Logs 'qemu.log') -QmpPort $port -Accelerator tcg
        $joined = ' ' + ($args -join ' ') + ' '
        Assert-EzDarkFactoryTrue -Condition ($joined -match ' -accel tcg,thread=multi ')
        Assert-EzDarkFactoryTrue -Condition ($joined -match ' -cpu max ')
        Assert-EzDarkFactoryTrue -Condition ($joined -notmatch ' -accel whpx ')
    }
    finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Runtime: valid start transitions CREATED to RUNNING with durable process evidence' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        $before = Get-EzDarkFactoryInstanceStatus -Root $fixture.Root -InstanceName $fixture.InstanceName -ProcessProvider $fixture.ProcessProvider
        Assert-EzDarkFactoryEqual -Actual $before.state -Expected 'CREATED'
        $started = Start-EzDarkFactoryRuntimeFixtureInstance -Fixture $fixture
        Assert-EzDarkFactoryEqual -Actual $started.state -Expected 'RUNNING'
        Assert-EzDarkFactoryEqual -Actual $started.accelerator -Expected 'whpx'
        Assert-EzDarkFactoryEqual -Actual $fixture.State.LaunchCount -Expected 1
        $runtime = Get-EzDarkFactoryRuntimeFixtureState -Fixture $fixture
        Assert-EzDarkFactoryEqual -Actual $runtime.state -Expected 'RUNNING'
        Assert-EzDarkFactoryTrue -Condition ($runtime.argumentFingerprint -match '^[a-f0-9]{64}$')
        Assert-EzDarkFactoryTrue -Condition ($runtime.qemuExecutable -match 'qemu-system-x86_64\.exe$')
        Assert-EzDarkFactoryEqual -Actual $runtime.qmpHost -Expected '127.0.0.1'
        Assert-EzDarkFactoryTrue -Condition ([int]$runtime.qmpPort -ge 1024 -and [int]$runtime.qmpPort -le 65535)
        Assert-EzDarkFactoryTrue -Condition ([IO.Path]::IsPathRooted($runtime.serialLog))
        Assert-EzDarkFactoryTrue -Condition ([IO.Path]::IsPathRooted($runtime.qemuLog))
        $status = Get-EzDarkFactoryInstanceStatus -Root $fixture.Root -InstanceName $fixture.InstanceName -ProcessProvider $fixture.ProcessProvider
        Assert-EzDarkFactoryEqual -Actual $status.state -Expected 'RUNNING'
        Assert-EzDarkFactoryEqual -Actual $status.pid -Expected $started.pid
    }
    finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Runtime: duplicate start refuses before launching another QEMU' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        $null = Start-EzDarkFactoryRuntimeFixtureInstance -Fixture $fixture
        Assert-EzDarkFactoryThrows -ScriptBlock { Start-EzDarkFactoryRuntimeFixtureInstance -Fixture $fixture } -MessagePattern "cannot start from lifecycle state 'RUNNING'" | Out-Null
        Assert-EzDarkFactoryEqual -Actual $fixture.State.LaunchCount -Expected 1
    }
    finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Runtime: backing-chain failure prevents QEMU launch' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        Set-EzDarkFactoryRuntimeFixtureBacking -Fixture $fixture -Backing '..\..\..\outside.qcow2'
        Assert-EzDarkFactoryThrows -ScriptBlock { Start-EzDarkFactoryRuntimeFixtureInstance -Fixture $fixture } -MessagePattern 'outside|escapes|missing' | Out-Null
        Assert-EzDarkFactoryEqual -Actual $fixture.State.LaunchCount -Expected 0
        Assert-EzDarkFactoryEqual -Actual $fixture.State.Processes.Count -Expected 0
    }
    finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Runtime: graceful stop sends system_powerdown and records STOPPED' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        $null = Start-EzDarkFactoryRuntimeFixtureInstance -Fixture $fixture
        $stopped = Stop-EzDarkFactoryInstance -Root $fixture.Root -InstanceName $fixture.InstanceName -ShutdownTimeoutSeconds 3 -ProcessProvider $fixture.ProcessProvider -QmpInvoker $fixture.QmpInvoker
        Assert-EzDarkFactoryEqual -Actual $stopped.state -Expected 'STOPPED'
        Assert-EzDarkFactoryTrue -Condition (-not $stopped.alreadyStopped)
        Assert-EzDarkFactoryTrue -Condition ($fixture.State.QmpCalls -ccontains 'system_powerdown')
        $runtime = Get-EzDarkFactoryRuntimeFixtureState -Fixture $fixture
        Assert-EzDarkFactoryEqual -Actual $runtime.state -Expected 'STOPPED'
        Assert-EzDarkFactoryTrue -Condition (-not [string]::IsNullOrWhiteSpace($runtime.stoppedAt))
        $status = Get-EzDarkFactoryInstanceStatus -Root $fixture.Root -InstanceName $fixture.InstanceName -ProcessProvider $fixture.ProcessProvider
        Assert-EzDarkFactoryEqual -Actual $status.state -Expected 'STOPPED'
        $guard = Get-EzDarkFactoryInstanceStorageLifecycleGuard -Root $fixture.Root -InstanceName $fixture.InstanceName -ProcessProvider $fixture.ProcessProvider
        Assert-EzDarkFactoryEqual -Actual $guard.state -Expected 'proven-safe'
    }
    finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Runtime: graceful stop tolerates terminating PID observation races without weakening ownership' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        $null = Start-EzDarkFactoryRuntimeFixtureInstance -Fixture $fixture
        $shutdown = [pscustomobject]@{ AfterPowerdown = $false; Polls = 0 }
        $baseProvider = $fixture.ProcessProvider
        $baseQmp = $fixture.QmpInvoker
        $state = $fixture.State

        $provider = {
            param($processId)
            if ($shutdown.AfterPowerdown -and $null -ne $processId) {
                $shutdown.Polls++
                if ($shutdown.Polls -eq 1) {
                    throw 'Windows process identity could not be queried safely: Observed process has no readable command line; process identity is ambiguous.'
                }
                if ($shutdown.Polls -eq 3) {
                    $state.Processes.Clear()
                    return @()
                }
            }
            return @(& $baseProvider $processId)
        }.GetNewClosure()

        $qmp = {
            param($hostAddress, $port, $command, $timeoutMilliseconds)
            if ($command -ceq 'system_powerdown') {
                $shutdown.AfterPowerdown = $true
                return [pscustomobject]@{}
            }
            return & $baseQmp $hostAddress $port $command $timeoutMilliseconds
        }.GetNewClosure()

        $stopped = Stop-EzDarkFactoryInstance -Root $fixture.Root -InstanceName $fixture.InstanceName -ShutdownTimeoutSeconds 3 -ProcessProvider $provider -QmpInvoker $qmp
        Assert-EzDarkFactoryEqual -Actual $stopped.state -Expected 'STOPPED'
        Assert-EzDarkFactoryTrue -Condition ($shutdown.Polls -ge 3) -Message 'Fixture must exercise unreadable-command-line retry and disappearance between identity observations.'
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryRuntimeFixtureState -Fixture $fixture).state -Expected 'STOPPED'
    }
    finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Runtime: graceful stop retries a terminating PID during the second identity observation' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        $null = Start-EzDarkFactoryRuntimeFixtureInstance -Fixture $fixture
        $shutdown = [pscustomobject]@{ AfterPowerdown = $false; Polls = 0 }
        $baseProvider = $fixture.ProcessProvider
        $baseQmp = $fixture.QmpInvoker
        $state = $fixture.State

        $provider = {
            param($processId)
            if ($shutdown.AfterPowerdown -and $null -ne $processId) {
                $shutdown.Polls++
                if ($shutdown.Polls -eq 2) {
                    throw 'Windows process identity could not be queried safely: terminating PID lost its command line between observations.'
                }
                if ($shutdown.Polls -eq 3) {
                    $state.Processes.Clear()
                    return @()
                }
            }
            return @(& $baseProvider $processId)
        }.GetNewClosure()

        $qmp = {
            param($hostAddress, $port, $command, $timeoutMilliseconds)
            if ($command -ceq 'system_powerdown') {
                $shutdown.AfterPowerdown = $true
                return [pscustomobject]@{}
            }
            return & $baseQmp $hostAddress $port $command $timeoutMilliseconds
        }.GetNewClosure()

        $stopped = Stop-EzDarkFactoryInstance -Root $fixture.Root -InstanceName $fixture.InstanceName -ShutdownTimeoutSeconds 3 -ProcessProvider $provider -QmpInvoker $qmp
        Assert-EzDarkFactoryEqual -Actual $stopped.state -Expected 'STOPPED'
        Assert-EzDarkFactoryEqual -Actual $shutdown.Polls -Expected 3 -Message 'Stop must retry the second-query error and obtain affirmative evidence that the PID exited.'
        Assert-EzDarkFactoryEqual -Actual $fixture.State.Processes.Count -Expected 0
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryRuntimeFixtureState -Fixture $fixture).state -Expected 'STOPPED'
    }
    finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Runtime: repeated second-observation shutdown errors remain bounded and fail-closed' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        $null = Start-EzDarkFactoryRuntimeFixtureInstance -Fixture $fixture
        $shutdown = [pscustomobject]@{ AfterPowerdown = $false; Polls = 0 }
        $baseProvider = $fixture.ProcessProvider
        $baseQmp = $fixture.QmpInvoker

        $provider = {
            param($processId)
            if ($shutdown.AfterPowerdown -and $null -ne $processId) {
                $shutdown.Polls++
                if (($shutdown.Polls % 2) -eq 0) {
                    throw 'Windows process identity could not be queried safely: persistent second-observation ambiguity.'
                }
            }
            return @(& $baseProvider $processId)
        }.GetNewClosure()

        $qmp = {
            param($hostAddress, $port, $command, $timeoutMilliseconds)
            if ($command -ceq 'system_powerdown') {
                $shutdown.AfterPowerdown = $true
                return [pscustomobject]@{}
            }
            return & $baseQmp $hostAddress $port $command $timeoutMilliseconds
        }.GetNewClosure()

        Assert-EzDarkFactoryThrows -ScriptBlock {
            Stop-EzDarkFactoryInstance -Root $fixture.Root -InstanceName $fixture.InstanceName -ShutdownTimeoutSeconds 1 -ProcessProvider $provider -QmpInvoker $qmp
        } -MessagePattern 'was not killed.*STOPPING.*Last process-identity observation error.*persistent second-observation ambiguity' | Out-Null
        Assert-EzDarkFactoryTrue -Condition ($shutdown.Polls -gt 2) -Message 'Stop must make bounded retries after a second-observation query failure.'
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryRuntimeFixtureState -Fixture $fixture).state -Expected 'STOPPING'
        Assert-EzDarkFactoryEqual -Actual $fixture.State.Processes.Count -Expected 1
    }
    finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Runtime: persistent shutdown identity-query ambiguity remains bounded and fail-closed' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        $null = Start-EzDarkFactoryRuntimeFixtureInstance -Fixture $fixture
        $shutdown = [pscustomobject]@{ AfterPowerdown = $false }
        $baseProvider = $fixture.ProcessProvider
        $baseQmp = $fixture.QmpInvoker

        $provider = {
            param($processId)
            if ($shutdown.AfterPowerdown -and $null -ne $processId) {
                throw 'Windows process identity could not be queried safely: persistent fixture ambiguity.'
            }
            return @(& $baseProvider $processId)
        }.GetNewClosure()

        $qmp = {
            param($hostAddress, $port, $command, $timeoutMilliseconds)
            if ($command -ceq 'system_powerdown') {
                $shutdown.AfterPowerdown = $true
                return [pscustomobject]@{}
            }
            return & $baseQmp $hostAddress $port $command $timeoutMilliseconds
        }.GetNewClosure()

        Assert-EzDarkFactoryThrows -ScriptBlock {
            Stop-EzDarkFactoryInstance -Root $fixture.Root -InstanceName $fixture.InstanceName -ShutdownTimeoutSeconds 1 -ProcessProvider $provider -QmpInvoker $qmp
        } -MessagePattern 'was not killed.*STOPPING.*Last process-identity observation error.*persistent fixture ambiguity' | Out-Null
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryRuntimeFixtureState -Fixture $fixture).state -Expected 'STOPPING'
        Assert-EzDarkFactoryEqual -Actual $fixture.State.Processes.Count -Expected 1
    }
    finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Runtime: stop timeout never silently kills QEMU' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        $null = Start-EzDarkFactoryRuntimeFixtureInstance -Fixture $fixture
        $fixture.State.PowerdownExits = $false
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Stop-EzDarkFactoryInstance -Root $fixture.Root -InstanceName $fixture.InstanceName -ShutdownTimeoutSeconds 1 -ProcessProvider $fixture.ProcessProvider -QmpInvoker $fixture.QmpInvoker
        } -MessagePattern 'was not killed.*STOPPING' | Out-Null
        Assert-EzDarkFactoryEqual -Actual $fixture.State.Processes.Count -Expected 1
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryRuntimeFixtureState -Fixture $fixture).state -Expected 'STOPPING'
    }
    finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Runtime: stale PID and reused unrelated executable are not treated as the VM' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        $started = Start-EzDarkFactoryRuntimeFixtureInstance -Fixture $fixture
        $fixture.State.Processes.Clear()
        $stale = Get-EzDarkFactoryInstanceStatus -Root $fixture.Root -InstanceName $fixture.InstanceName -ProcessProvider $fixture.ProcessProvider
        Assert-EzDarkFactoryEqual -Actual $stale.state -Expected 'STALE'
        Assert-EzDarkFactoryTrue -Condition ($stale.reason -match 'no longer exists')

        $runtime = Get-EzDarkFactoryRuntimeFixtureState -Fixture $fixture
        $fixture.State.Processes.Add([pscustomobject]@{
            Pid = [int]$runtime.pid
            ExecutablePath = 'C:\Windows\System32\notepad.exe'
            Arguments = @('unrelated')
            StartTimeUtc = [string]$runtime.processStartTimeUtc
        })
        $reused = Get-EzDarkFactoryInstanceStatus -Root $fixture.Root -InstanceName $fixture.InstanceName -ProcessProvider $fixture.ProcessProvider
        Assert-EzDarkFactoryEqual -Actual $reused.state -Expected 'STALE'
        Assert-EzDarkFactoryTrue -Condition ($reused.reason -match 'not the recorded QEMU executable')
        $guard = Get-EzDarkFactoryInstanceStorageLifecycleGuard -Root $fixture.Root -InstanceName $fixture.InstanceName -ProcessProvider $fixture.ProcessProvider
        Assert-EzDarkFactoryEqual -Actual $guard.state -Expected 'unknown'
    }
    finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Runtime: mismatched launch fingerprint is STALE and storage remains fail-closed' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        $null = Start-EzDarkFactoryRuntimeFixtureInstance -Fixture $fixture
        $process = $fixture.State.Processes[0]
        $process.Arguments = [string[]](@($process.Arguments) + @('-unexpected-token'))
        $status = Get-EzDarkFactoryInstanceStatus -Root $fixture.Root -InstanceName $fixture.InstanceName -ProcessProvider $fixture.ProcessProvider
        Assert-EzDarkFactoryEqual -Actual $status.state -Expected 'STALE'
        Assert-EzDarkFactoryTrue -Condition ($status.reason -match 'fingerprint')
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryInstanceStorageLifecycleGuard -Root $fixture.Root -InstanceName $fixture.InstanceName -ProcessProvider $fixture.ProcessProvider).state -Expected 'unknown'
    }
    finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Runtime: corrupted runtime.json returns UNKNOWN instead of trusting process metadata' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        $null = Start-EzDarkFactoryRuntimeFixtureInstance -Fixture $fixture
        $runtimePath = (Get-EzDarkFactoryInstanceRuntimePaths -Root $fixture.Root -InstanceName $fixture.InstanceName).Runtime
        [IO.File]::WriteAllText($runtimePath, '{"schemaVersion":1,"broken":', (New-Object Text.UTF8Encoding($false)))
        $status = Get-EzDarkFactoryInstanceStatus -Root $fixture.Root -InstanceName $fixture.InstanceName -ProcessProvider $fixture.ProcessProvider
        Assert-EzDarkFactoryEqual -Actual $status.state -Expected 'UNKNOWN'
        Assert-EzDarkFactoryTrue -Condition ($status.reason -match 'runtime.json is corrupt')
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Stop-EzDarkFactoryInstance -Root $fixture.Root -InstanceName $fixture.InstanceName -ShutdownTimeoutSeconds 1 -ProcessProvider $fixture.ProcessProvider -QmpInvoker $fixture.QmpInvoker
        } -MessagePattern "cannot be stopped safely from lifecycle state 'UNKNOWN'" | Out-Null
        Assert-EzDarkFactoryEqual -Actual $fixture.State.Processes.Count -Expected 1
    }
    finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Runtime: untracked QEMU owner makes missing runtime evidence UNKNOWN' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        $runtimePaths = Get-EzDarkFactoryInstanceRuntimePaths -Root $fixture.Root -InstanceName $fixture.InstanceName
        $intent = Get-EzDarkFactoryInstanceIntent -Root $fixture.Root -InstanceName $fixture.InstanceName
        [void][IO.Directory]::CreateDirectory($runtimePaths.Logs)
        $firmware = Get-EzDarkFactoryRuntimeFirmwarePaths -Root $fixture.Root -InstanceName $fixture.InstanceName
        $args = New-EzDarkFactoryRuntimeQemuArguments -InstanceName $fixture.InstanceName -Intent $intent -Disk $fixture.Overlay -FirmwareCode $firmware.Code -FirmwareVariables $firmware.Variables -SerialLog (Join-Path $runtimePaths.Logs 'serial-untracked.log') -QemuLog (Join-Path $runtimePaths.Logs 'qemu-untracked.log') -QmpPort 32125 -Accelerator whpx
        $fixture.State.Processes.Add([pscustomobject]@{
            Pid = 49999
            ExecutablePath = Join-Path $fixture.Paths.Qemu 'qemu-system-x86_64.exe'
            Arguments = [string[]]$args
            StartTimeUtc = [DateTime]::UtcNow.ToString('o')
        })
        $status = Get-EzDarkFactoryInstanceStatus -Root $fixture.Root -InstanceName $fixture.InstanceName -ProcessProvider $fixture.ProcessProvider
        Assert-EzDarkFactoryEqual -Actual $status.state -Expected 'UNKNOWN'
        Assert-EzDarkFactoryTrue -Condition ($status.reason -match 'without matching active runtime ownership evidence')
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryInstanceStorageLifecycleGuard -Root $fixture.Root -InstanceName $fixture.InstanceName -ProcessProvider $fixture.ProcessProvider).state -Expected 'unknown'
    }
    finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Runtime: reachable but non-running QMP never becomes RUNNING' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        $fixture.State.QmpRunning = $false
        Assert-EzDarkFactoryThrows -ScriptBlock { Start-EzDarkFactoryRuntimeFixtureInstance -Fixture $fixture -Timeout 3 } -MessagePattern "startup timeout.*QMP is reachable but reports status 'paused'" | Out-Null
        Assert-EzDarkFactoryEqual -Actual $fixture.State.Processes.Count -Expected 1
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryRuntimeFixtureState -Fixture $fixture).state -Expected 'STARTING'
    }
    finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

# CI-RUNTIME-001: the first QMP response is valid and non-running; the next
# response consumes the remaining total budget. A generic late failure must
# not erase the first within-budget semantic diagnosis or publish RUNNING.
Add-EzDarkFactoryTest -Name 'Runtime: within-deadline paused observation survives later expired QMP query' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        $trace = [pscustomobject]@{ Calls = 0 }
        $fixture.QmpInvoker = {
            param($hostAddress, $port, $command, $timeout)
            $trace.Calls++
            if ($trace.Calls -eq 1) {
                return [pscustomobject]@{ running = $false; status = 'paused' }
            }
            Start-Sleep -Milliseconds 3500
            return [pscustomobject]@{ running = $true; status = 'running' }
        }.GetNewClosure()
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Start-EzDarkFactoryRuntimeFixtureInstance -Fixture $fixture -Timeout 3
        } -MessagePattern "startup timeout.*Last within-deadline QMP observation: QMP is reachable but reports status 'paused'" | Out-Null
        Assert-EzDarkFactoryTrue ($trace.Calls -ge 2) -Message 'Must reach the later expired QMP query.'
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryRuntimeFixtureState $fixture).state 'STARTING'
        Assert-EzDarkFactoryEqual $fixture.State.Processes.Count 1
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryInstanceStorageLifecycleGuard -Root $fixture.Root -InstanceName $fixture.InstanceName -ProcessProvider $fixture.ProcessProvider).state 'starting'
    }
    finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Runtime: startup timeout leaves STARTING ownership evidence and does not kill QEMU' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        $fixture.State.QmpReady = $false
        Assert-EzDarkFactoryThrows -ScriptBlock { Start-EzDarkFactoryRuntimeFixtureInstance -Fixture $fixture -Timeout 1 } -MessagePattern 'startup timeout.*still owns the disk.*STARTING' | Out-Null
        Assert-EzDarkFactoryEqual -Actual $fixture.State.Processes.Count -Expected 1
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryRuntimeFixtureState -Fixture $fixture).state -Expected 'STARTING'
    }
    finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Runtime: lifecycle lock refuses concurrent mutation and stale lock file is reusable' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        $module = Get-Module EzDarkFactory
        $held = & $module { param($root, $name) Enter-EzDarkFactoryInstanceLifecycleLock -Root $root -InstanceName $name -TimeoutMilliseconds 500 } $fixture.Root $fixture.InstanceName
        try {
            Assert-EzDarkFactoryThrows -ScriptBlock {
                & $module { param($root, $name) Enter-EzDarkFactoryInstanceLifecycleLock -Root $root -InstanceName $name -TimeoutMilliseconds 100 } $fixture.Root $fixture.InstanceName
            } -MessagePattern 'Timed out waiting for lifecycle lock' | Out-Null
        }
        finally { $held.Dispose() }

        $again = & $module { param($root, $name) Enter-EzDarkFactoryInstanceLifecycleLock -Root $root -InstanceName $name -TimeoutMilliseconds 500 } $fixture.Root $fixture.InstanceName
        try { Assert-EzDarkFactoryTrue -Condition ($null -ne $again) }
        finally { $again.Dispose() }
    }
    finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Runtime: argument fingerprint changes on launch-affecting token changes' -ScriptBlock {
    $a = Get-EzDarkFactoryArgumentFingerprint -ArgumentList @('-machine', 'q35', '-accel', 'whpx')
    $b = Get-EzDarkFactoryArgumentFingerprint -ArgumentList @('-machine', 'q35', '-accel', 'tcg,thread=multi')
    Assert-EzDarkFactoryTrue -Condition ($a -match '^[a-f0-9]{64}$')
    Assert-EzDarkFactoryTrue -Condition ($b -match '^[a-f0-9]{64}$')
    Assert-EzDarkFactoryTrue -Condition ($a -cne $b)
}

Add-EzDarkFactoryTest -Name 'Runtime: production QMP transport exposes no force-quit command' -ScriptBlock {
    $source = [IO.File]::ReadAllText((Join-Path $script:EzDarkFactoryRepositoryRoot 'src/EzDarkFactory/Runtime.ps1'))
    Assert-EzDarkFactoryTrue -Condition ($source -notmatch "'quit'") -Message 'Production runtime transport must not contain a QMP quit command.'
    Assert-EzDarkFactoryTrue -Condition ($source -match 'system_powerdown') -Message 'Graceful QMP powerdown must remain the normal stop mechanism.'
}
