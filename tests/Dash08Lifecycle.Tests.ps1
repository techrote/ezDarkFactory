. (Join-Path $PSScriptRoot 'fixtures/Dash08ProcessScenario.ps1')
$dash08WindowsSkip = $null
if (-not $script:EzDarkFactoryIsWindowsHost) { $dash08WindowsSkip = 'Requires real Windows process handles; PS5.1 and pinned PS7 CI execute this case.' }

Add-EzDarkFactoryTest -Name 'DASH-08-T01: retained legacy launch reproduces inherited capture lifetime' -SkipReason $dash08WindowsSkip -ScriptBlock {
    $result = Invoke-EzDarkFactoryDash08ProcessScenario -Mode Legacy
    Assert-EzDarkFactoryTrue ($result.ParentExited -and $result.FixtureSurvivedParent -and $result.HeartbeatContinued -and $result.FixtureStopped)
    Assert-EzDarkFactoryEqual $result.CapturedOutputDrained $false
    # Unused inherited pipe handles can delay EOF without becoming the child's
    # active console stdout. Pipe lifetime, not child-byte contamination, is the oracle.
    Assert-EzDarkFactoryTrue ($result.CallerOutput.Contains('{"callerReturned":true}'))
    Write-Host ('DASH08_MEASUREMENT legacyMilliseconds=' + $result.ElapsedMilliseconds)
}

Add-EzDarkFactoryTest -Name 'DASH-08-T01: captured caller exits while native output files and VM lifetime remain independent' -SkipReason $dash08WindowsSkip -ScriptBlock {
    $tokens = @('--flood', '--read-stdin', '', 'two words', 'embedded"quote', 'trailing\', 'slashes\\"quoted', ('unicode-' + [char]0x03bb + [char]0x65e5), "tab`tline`nend", '& | < > %PATH% $(no-shell)')
    $result = Invoke-EzDarkFactoryDash08ProcessScenario -Tokens $tokens
    Assert-EzDarkFactoryTrue ($result.ParentExited -and $result.CapturedOutputDrained -and $result.FixtureSurvivedParent -and $result.HeartbeatContinued -and $result.FixtureStopped)
    Assert-EzDarkFactoryTrue $result.UnrelatedHandleReleased -Message 'A long-lived child must not retain an unrelated inheritable caller handle.'
    Assert-EzDarkFactoryEqual $result.FixtureExitCode 0
    Assert-EzDarkFactoryEqual $result.CallerOutput.Trim() '{"callerReturned":true}'
    Assert-EzDarkFactoryEqual $result.CallerError ''
    Assert-EzDarkFactoryTrue ($result.NativeStdout.Length -gt 131072 -and $result.NativeStdout.Contains('fixture-stdout'))
    Assert-EzDarkFactoryTrue ($result.NativeStderr.Length -gt 131072 -and $result.NativeStderr.Contains('fixture-stderr'))
    Assert-EzDarkFactoryEqual $result.StdinFirstByte -1 -Message 'NUL input must provide EOF without a BOM or input byte.'
    Assert-EzDarkFactoryEqual $result.DeclaredTokenCount $tokens.Count
    Assert-EzDarkFactoryEqual $result.Tokens $tokens
    Write-Host ('DASH08_MEASUREMENT currentMilliseconds=' + $result.ElapsedMilliseconds)
}

Add-EzDarkFactoryTest -Name 'DASH-08-T01: terminating only the caller leaves its launched fixture alive and logs writable' -SkipReason $dash08WindowsSkip -ScriptBlock {
    $result = Invoke-EzDarkFactoryDash08ProcessScenario -Mode Interrupted
    Assert-EzDarkFactoryTrue ($result.ParentExited -and $result.CapturedOutputDrained -and $result.FixtureSurvivedParent -and $result.HeartbeatContinued -and $result.FixtureStopped)
    Assert-EzDarkFactoryTrue $result.UnrelatedHandleReleased
    Assert-EzDarkFactoryTrue ($result.NativeStdout.Contains('fixture-stdout') -and $result.NativeStderr.Contains('fixture-stderr'))
    Assert-EzDarkFactoryEqual $result.FixtureExitCode 0
    Write-Host ('DASH08_MEASUREMENT interruptedMilliseconds=' + $result.ElapsedMilliseconds)
}

Add-EzDarkFactoryTest -Name 'DASH-08-T01: log preimages and invalid launch paths fail before a child is created' -SkipReason $dash08WindowsSkip -ScriptBlock {
    $directory = New-EzDarkFactoryTestDirectory -Prefix 'dash08 launch refusal'
    try {
        $fixture = New-EzDarkFactoryDash08NativeFixture $directory
        $out = Join-Path $directory 'stdout.log'; $err = Join-Path $directory 'stderr.log'
        [IO.File]::WriteAllText($out, 'existing diagnostic preimage')
        $invoke = {
            param($exe, $dir, $stdout, $stderr, $tokens)
            & (Get-Module EzDarkFactory) { param($exe, $dir, $stdout, $stderr, $tokens)
                Start-EzDarkFactoryRuntimeProcess -FilePath $exe -ArgumentList $tokens -WorkingDirectory $dir -StandardOutputPath $stdout -StandardErrorPath $stderr
            } $exe $dir $stdout $stderr $tokens
        }
        Assert-EzDarkFactoryThrows { & $invoke $fixture $directory $out $err @($directory) } 'already exists' | Out-Null
        Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText($out)) 'existing diagnostic preimage'
        Assert-EzDarkFactoryTrue (-not [IO.File]::Exists((Join-Path $directory 'child.identity')))
        [IO.File]::Delete($out)
        Assert-EzDarkFactoryThrows { & $invoke (Join-Path $directory 'absent.exe') $directory $out $err @($directory) } 'does not exist' | Out-Null
        Assert-EzDarkFactoryThrows { & $invoke $fixture $directory $out $out @($directory) } 'distinct' | Out-Null
        Assert-EzDarkFactoryThrows { & $invoke $fixture $directory $out $err @($directory, ('bad' + [char]0 + 'token')) } 'NUL' | Out-Null
        Assert-EzDarkFactoryTrue (-not [IO.File]::Exists((Join-Path $directory 'child.identity')))
        Assert-EzDarkFactoryTrue (-not [IO.File]::Exists($out) -and -not [IO.File]::Exists($err))
    } finally { Remove-EzDarkFactoryTestDirectory $directory }
}

Add-EzDarkFactoryTest -Name 'DASH-08-T02: late positive QMP startup result cannot publish RUNNING' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        $fixture.QmpInvoker = { param($hostAddress, $port, $command, $timeout) Start-Sleep -Milliseconds 1200; [pscustomobject]@{running = $true; status = 'running'} }
        Assert-EzDarkFactoryThrows { Start-EzDarkFactoryRuntimeFixtureInstance -Fixture $fixture -Timeout 1 } 'startup timeout' | Out-Null
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryRuntimeFixtureState $fixture).state 'STARTING'
        Assert-EzDarkFactoryEqual $fixture.State.Processes.Count 1
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryInstanceStorageLifecycleGuard -Root $fixture.Root -InstanceName $fixture.InstanceName -ProcessProvider $fixture.ProcessProvider).state 'starting'
    } finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'DASH-08-T03: process identity change during QMP query cannot publish RUNNING or kill the changed process' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        $state = $fixture.State
        $fixture.QmpInvoker = { param($hostAddress, $port, $command, $timeout)
            $state.Processes[0].StartTimeUtc = [DateTime]::UtcNow.AddMinutes(-5).ToString('o')
            [pscustomobject]@{running = $true; status = 'running'}
        }.GetNewClosure()
        Assert-EzDarkFactoryThrows { Start-EzDarkFactoryRuntimeFixtureInstance -Fixture $fixture -Timeout 2 } 'identity' | Out-Null
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryRuntimeFixtureState $fixture).state 'STARTING'
        Assert-EzDarkFactoryEqual $fixture.State.Processes.Count 1
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryInstanceStorageLifecycleGuard -Root $fixture.Root -InstanceName $fixture.InstanceName -ProcessProvider $fixture.ProcessProvider).state 'unknown'
    } finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'DASH-08-T02: powerdown command consumes the stop budget and late success stays STOPPING' -ScriptBlock {
    $fixture = New-EzDarkFactoryRuntimeFixture
    try {
        $null = Start-EzDarkFactoryRuntimeFixtureInstance $fixture
        $state = $fixture.State
        $slow = { param($hostAddress, $port, $command, $timeout)
            Start-Sleep -Milliseconds 1200
            $state.Processes.Clear()
            [pscustomobject]@{}
        }.GetNewClosure()
        Assert-EzDarkFactoryThrows { Stop-EzDarkFactoryInstance -Root $fixture.Root -InstanceName $fixture.InstanceName -ShutdownTimeoutSeconds 1 -ProcessProvider $fixture.ProcessProvider -QmpInvoker $slow } 'not killed.*STOPPING' | Out-Null
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryRuntimeFixtureState $fixture).state 'STOPPING'
    } finally { Remove-EzDarkFactoryRuntimeFixture $fixture }
}

foreach ($delay in @(0, 600)) {
    Add-EzDarkFactoryTest -Name ('DASH-08-T02: real QMP socket shares one connect greeting capability command deadline delay=' + $delay) -Data $delay -SkipReason $dash08WindowsSkip -ScriptBlock {
        param($delay)
        $directory = New-EzDarkFactoryTestDirectory -Prefix 'dash08 qmp budget'
        $launch = $null
        try {
            $fixture = New-EzDarkFactoryDash08NativeFixture -Directory $directory -Name Dash08QmpServer
            $launch = & (Get-Module EzDarkFactory) { param($fixture, $directory, $delay)
                Start-EzDarkFactoryRuntimeProcess -FilePath $fixture -ArgumentList @($directory, [string]$delay) -WorkingDirectory $directory -StandardOutputPath (Join-Path $directory 'stdout.log') -StandardErrorPath (Join-Path $directory 'stderr.log')
            } $fixture $directory $delay
            $wait = [Diagnostics.Stopwatch]::StartNew()
            $portFile = Join-Path $directory 'port'
            while (-not [IO.File]::Exists($portFile) -and $wait.ElapsedMilliseconds -lt 5000) { Start-Sleep -Milliseconds 20 }
            $port = [int]([IO.File]::ReadAllText($portFile))
            $clock = [Diagnostics.Stopwatch]::StartNew()
            $invoke = { & (Get-Module EzDarkFactory) { param($port) Invoke-EzDarkFactoryQmpCommand -HostAddress '127.0.0.1' -Port $port -Command 'query-status' -TimeoutMilliseconds 1500 } $port }
            if ($delay -eq 0) { Assert-EzDarkFactoryEqual (& $invoke).status 'running' }
            else { Assert-EzDarkFactoryThrows $invoke 'Timed out|deadline' | Out-Null }
            Assert-EzDarkFactoryTrue ($clock.ElapsedMilliseconds -lt 3000) -Message 'One 1500 ms QMP operation must not receive four independent 1500 ms budgets.'
            Write-Host ('DASH08_MEASUREMENT qmpDelay=' + $delay + ';elapsedMilliseconds=' + $clock.ElapsedMilliseconds)
            Assert-EzDarkFactoryTrue ($launch.Process.WaitForExit(5000))
        }
        finally {
            if ($null -ne $launch) {
                if (-not $launch.Process.HasExited) { $launch.Process.Kill(); [void]$launch.Process.WaitForExit(2000) }
                $launch.Process.Dispose()
            }
            Remove-EzDarkFactoryTestDirectory $directory
        }
    }
}

foreach ($failPublication in @($false, $true)) {
    Add-EzDarkFactoryTest -Name ('DASH-08-T03: real owned child cleanup follows runtime publication boundary failure=' + $failPublication) -Data $failPublication -SkipReason $dash08WindowsSkip -ScriptBlock {
        param($failPublication)
        $fixture = New-EzDarkFactoryRuntimeFixture
        $native = [pscustomobject]@{ Observer = $null; Directory = $null; FailPublication = $failPublication }
        try {
            $native.Directory = Join-Path $fixture.Root 'native child'
            [void][IO.Directory]::CreateDirectory($native.Directory)
            $executable = New-EzDarkFactoryDash08NativeFixture $native.Directory
            $qemuImg = Join-Path $fixture.Paths.Qemu 'qemu-img.exe'
            $fixture.QemuStatusProvider = { param($root)
                [pscustomobject]@{ Valid = $true; Reason = 'source-only native fixture'; QemuSystem = $executable; QemuImg = $qemuImg }
            }.GetNewClosure()
            $state = $fixture.State
            $runtimePath = (Get-EzDarkFactoryInstanceRuntimePaths -Root $fixture.Root -InstanceName $fixture.InstanceName).Runtime
            $fixture.ProcessLauncher = { param($filePath, $arguments, $workingDirectory)
                $launch = & (Get-Module EzDarkFactory) { param($exe, $dir, $arguments)
                    Start-EzDarkFactoryRuntimeProcess -FilePath $exe -ArgumentList (@($dir) + @($arguments)) -WorkingDirectory $dir -StandardOutputPath (Join-Path $dir 'stdout.log') -StandardErrorPath (Join-Path $dir 'stderr.log')
                } $filePath $native.Directory $arguments
                $native.Observer = [Diagnostics.Process]::GetProcessById($launch.Pid)
                $null = $native.Observer.Handle
                $state.Processes.Add([pscustomobject]@{ Pid = $launch.Pid; ExecutablePath = $filePath; Arguments = [string[]]$arguments; StartTimeUtc = $launch.StartTimeUtc })
                if ($native.FailPublication) { [void][IO.Directory]::CreateDirectory($runtimePath) }
                return $launch
            }.GetNewClosure()
            $fixture.State.QmpReady = $false
            Assert-EzDarkFactoryThrows { Start-EzDarkFactoryRuntimeFixtureInstance -Fixture $fixture -Timeout 1 } | Out-Null
            Assert-EzDarkFactoryTrue ($null -ne $native.Observer) -Message 'The test must cross actual native process creation, not fail in preflight.'
            if ($failPublication) {
                Assert-EzDarkFactoryTrue ($native.Observer.WaitForExit(5000)) -Message 'An unpublishable newly created child must be terminated by its exact owned handle.'
                Assert-EzDarkFactoryTrue (-not [IO.File]::Exists($runtimePath))
            } else {
                Assert-EzDarkFactoryEqual (Get-EzDarkFactoryRuntimeFixtureState $fixture).state 'STARTING'
                Assert-EzDarkFactoryTrue (-not $native.Observer.HasExited) -Message 'Startup timeout after publication must not abort a VM that owns its disk.'
                Assert-EzDarkFactoryTrue (Test-Path -LiteralPath $fixture.Overlay)
            }
        }
        finally {
            if ($null -ne $native.Directory) { [IO.File]::WriteAllText((Join-Path $native.Directory 'stop'), 'owned fixture stop') }
            if ($null -ne $native.Observer) {
                if (-not $native.Observer.WaitForExit(5000)) { $native.Observer.Kill(); [void]$native.Observer.WaitForExit(2000) }
                $native.Observer.Dispose()
            }
            Remove-EzDarkFactoryRuntimeFixture $fixture
        }
    }
}
