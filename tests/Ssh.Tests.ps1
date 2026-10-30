function New-EzDarkFactorySshTestIntent {
    param(
        [string]$Name = 'ssh-agent',
        [string]$BaseId = ('base-' + ('a' * 64)),
        [int]$Cpus = 4,
        [int]$MemoryMiB = 8192
    )
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        name = $Name
        baseId = $BaseId
        profile = $(if ($Cpus -eq 4 -and $MemoryMiB -eq 8192) { 'normal' } elseif ($Cpus -eq 2 -and $MemoryMiB -eq 4096) { 'light' } else { 'custom' })
        cpus = $Cpus
        memoryMiB = $MemoryMiB
        sshPort = 22001
        createdAt = '2026-10-12T00:00:00.0000000Z'
        provisioningProfile = 'coding-default'
        provisioningVersion = 1
    }
}

function ConvertTo-EzDarkFactorySshTestBase64 {
    param([AllowEmptyString()][string]$Text = '')
    return [Convert]::ToBase64String((New-Object Text.UTF8Encoding($false)).GetBytes($Text))
}


function Get-EzDarkFactorySshTestCloudId {
    param([object]$Intent)
    $module = Get-Module EzDarkFactory
    return & $module { param($i) Get-EzDarkFactoryGuestCloudInstanceId -Intent $i } $Intent
}

function New-EzDarkFactorySshTestAccess {
    param([string]$Root, [object]$Intent, [int]$Port = 22001, [string]$LaunchId = ('a' * 32))
    $coding = Get-EzDarkFactoryCodingProfile -Root $Root
    $Intent.sshPort = $Port
    $path = (Get-EzDarkFactorySshPaths -Root $Root -InstanceName $Intent.name).AccessState
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    return [pscustomobject][ordered]@{
        schemaVersion = 2
        instanceName = $Intent.name
        baseId = $Intent.baseId
        launchId = $LaunchId
        sshHost = '127.0.0.1'
        sshPort = $Port
        sshUser = 'coder'
        state = 'PROVISIONING'
        cloudInstanceId = Get-EzDarkFactorySshTestCloudId -Intent $Intent
        profile = $Intent.profile
        provisioningProfile = $coding.Name
        provisioningVersion = $coding.Version
        provisioningDigest = $coding.Digest
        readyAt = ''
    }
}

function New-EzDarkFactorySshTestLaunch {
    param([string]$Root, [object]$Intent, [object]$Access)
    # Readiness publication reconciles real durable launch records. Only the
    # operating-system process observation is replaced by this test fixture.
    $module = Get-Module EzDarkFactory
    return & $module {
        param($r, $i, $a)
        $paths = Get-EzDarkFactoryInstanceRuntimePaths -Root $r -InstanceName $i.name
        Write-EzDarkFactoryJson -Path $paths.Intent -Value $i -SchemaVersion ([int]$i.schemaVersion)
        $arguments = [string[]]@('-name', ('guest=ezdarkfactory-' + $i.name))
        $now = [DateTime]::UtcNow.ToString('o')
        $executable = Join-Path (Get-EzDarkFactoryPaths -Root $r).Qemu 'qemu-system-x86_64.exe'
        $runtime = [pscustomobject][ordered]@{
            schemaVersion = 1
            instanceName = $i.name
            state = 'RUNNING'
            pid = 41000
            processStartTimeUtc = $now
            qemuExecutable = $executable
            argumentFingerprint = Get-EzDarkFactoryArgumentFingerprint -ArgumentList $arguments
            launchId = $a.launchId
            qmpHost = '127.0.0.1'
            qmpPort = 32001
            accelerator = 'tcg'
            startedAt = $now
            lastObservedAt = $now
            stoppedAt = ''
            qemuLog = Join-Path $paths.Directory 'qemu.log'
            serialLog = Join-Path $paths.Directory 'serial.log'
        }
        Write-EzDarkFactoryRuntimeStateFile -Root $r -InstanceName $i.name -Runtime $runtime
        $state = [pscustomobject]@{ Processes = New-Object 'System.Collections.Generic.List[object]'; Observations = 0 }
        $state.Processes.Add([pscustomobject]@{
            Pid = $runtime.pid
            ExecutablePath = $executable
            Arguments = $arguments
            StartTimeUtc = $now
        })
        $provider = {
            param($processId)
            $state.Observations++
            if ($null -eq $processId) { return @($state.Processes.ToArray()) }
            return @($state.Processes.ToArray() | Where-Object { $_.Pid -eq [int]$processId })
        }.GetNewClosure()
        return [pscustomobject]@{ Paths = $paths; Runtime = $runtime; State = $state; ProcessProvider = $provider }
    } $Root $Intent $Access
}

function New-EzDarkFactorySshTestIdentityJson {
    param([object]$Intent, [string]$InstanceName = '')
    $coding = Get-EzDarkFactoryCodingProfile -Root $script:EzDarkFactoryRepositoryRoot
    if ($InstanceName.Length -eq 0) { $InstanceName = $Intent.name }
    return [pscustomobject][ordered]@{
        schemaVersion = 2
        instanceName = $InstanceName
        baseId = $Intent.baseId
        profile = $Intent.profile
        cloudInstanceId = Get-EzDarkFactorySshTestCloudId -Intent $Intent
        provisioningProfile = $coding.Name
        provisioningVersion = $coding.Version
        provisioningDigest = $coding.Digest
    } | ConvertTo-Json -Compress
}

function New-EzDarkFactorySshTestProbe {
    param(
        [string]$IdentityBase64,
        [string]$CloudStatus = 'status: done',
        [string]$CloudExit = '0',
        [bool]$Ready = $true,
        [string]$ProfileCheck = '',
        [string]$ProfileError = ''
    )
    $marker = ''
    if ($Ready) {
        $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($IdentityBase64)) | ConvertFrom-Json
        $decoded | Add-Member -NotePropertyName provisioningState -NotePropertyValue 'complete'
        $marker = ConvertTo-EzDarkFactorySshTestBase64 ($decoded | ConvertTo-Json -Compress)
    }
    if ($ProfileCheck.Length -eq 0) { $ProfileCheck = if ($Ready) { 'pass' } else { 'pending' } }
    return [string]::Join([Environment]::NewLine, @(
        ('EDF_IDENTITY_B64=' + $IdentityBase64),
        ('EDF_CLOUD_B64=' + (ConvertTo-EzDarkFactorySshTestBase64 $CloudStatus)),
        ('EDF_CLOUD_EXIT=' + $CloudExit),
        ('EDF_READY_B64=' + $marker),
        ('EDF_PROFILE_CHECK=' + $ProfileCheck),
        ('EDF_PROFILE_ERROR_B64=' + (ConvertTo-EzDarkFactorySshTestBase64 $ProfileError))
    )) + [Environment]::NewLine
}

Add-EzDarkFactoryTest -Name 'SSH: QEMU networking binds hostfwd to loopback and constructs guestfwd NoCloud endpoint' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'ssh qemu args [spaces]'
    try {
        $intent = New-EzDarkFactorySshTestIntent
        $dir = Join-Path $root 'runtime args'
        [void][IO.Directory]::CreateDirectory($dir)
        $args = New-EzDarkFactoryRuntimeQemuArguments -InstanceName $intent.name -Intent $intent -Disk (Join-Path $dir 'disk.qcow2') -FirmwareCode (Join-Path $dir 'code.fd') -FirmwareVariables (Join-Path $dir 'vars.fd') -SerialLog (Join-Path $dir 'serial log.txt') -QemuLog (Join-Path $dir 'qemu log.txt') -QmpPort 32123 -Accelerator whpx -SshPort 22017 -SeedHostPort 43111 -SeedGuestAddress '10.0.2.100' -SeedGuestPort 8000
        $netIndex = [Array]::IndexOf($args, '-netdev')
        Assert-EzDarkFactoryTrue -Condition ($netIndex -ge 0)
        $netdev = $args[$netIndex + 1]
        Assert-EzDarkFactoryTrue -Condition ($netdev -match 'hostfwd=tcp:127\.0\.0\.1:22017-:22')
        Assert-EzDarkFactoryTrue -Condition ($netdev -match 'guestfwd=tcp:10\.0\.2\.100:8000-tcp:127\.0\.0\.1:43111')
        Assert-EzDarkFactoryTrue -Condition ($netdev -notmatch 'hostfwd=tcp:(?!127\.0\.0\.1)') -Message 'SSH host forwarding must never omit the loopback bind.'
        $smbiosIndex = [Array]::IndexOf($args, '-smbios')
        Assert-EzDarkFactoryTrue -Condition ($smbiosIndex -ge 0)
        Assert-EzDarkFactoryEqual -Actual $args[$smbiosIndex + 1] -Expected 'type=1,serial=ds=nocloud;s=http://10.0.2.100:8000/'
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'SSH: instance NoCloud seed contains public authorization and exact identity but no private key' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'ssh seed'
    try {
        $intent = New-EzDarkFactorySshTestIntent
        $publicKey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEzvmFixturePublicKey0123456789= ezdarkfactory-controller'
        $seed = New-EzDarkFactoryInstanceSeedData -Root $root -InstanceName $intent.name -Intent $intent -ControllerPublicKey $publicKey
        Assert-EzDarkFactoryEqual -Actual $seed.Profile -Expected 'normal'
        Assert-EzDarkFactoryTrue -Condition ($seed.UserData -match [regex]::Escape(($publicKey -split ' ')[1]))
        Assert-EzDarkFactoryTrue -Condition ($seed.UserData -match '"instanceName":"ssh-agent"')
        Assert-EzDarkFactoryTrue -Condition ($seed.UserData -match [regex]::Escape($intent.baseId))
        Assert-EzDarkFactoryTrue -Condition ($seed.UserData -match '"profile":"normal"')
        Assert-EzDarkFactoryTrue -Condition ($seed.UserData -match '/var/lib/ezdarkfactory/ready\.json')
        Assert-EzDarkFactoryTrue -Condition ($seed.MetaData -match 'instance-id:.*ezdarkfactory-ssh-agent-')
        Assert-EzDarkFactoryTrue -Condition (($seed.UserData + $seed.MetaData) -notmatch '(?i)PRIVATE KEY')
        Assert-EzDarkFactoryThrows -ScriptBlock {
            New-EzDarkFactoryInstanceSeedData -Root $root -InstanceName $intent.name -Intent $intent -ControllerPublicKey ('-----BEGIN ' + 'OPENSSH PRIVATE KEY-----')
        } -MessagePattern 'must never receive private-key material' | Out-Null
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'SSH: command argv uses scoped strict host-key checking and preserves remote argument boundaries' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'ssh argv'
    try {
        $paths = Get-EzDarkFactorySshPaths -Root $root -InstanceName 'ssh-agent'
        $args = New-EzDarkFactorySshCommandArguments -PrivateKey $paths.ControllerPrivateKey -KnownHosts $paths.InstanceKnownHosts -Port 22001 -Batch -RemoteCommand @('printf', 'a b', "x'y", '')
        Assert-EzDarkFactoryTrue -Condition ($args -ccontains 'StrictHostKeyChecking=yes')
        Assert-EzDarkFactoryTrue -Condition ($args -ccontains 'UpdateHostKeys=no')
        Assert-EzDarkFactoryTrue -Condition ($args -ccontains 'HostKeyAlgorithms=ssh-ed25519')
        Assert-EzDarkFactoryTrue -Condition ($args -ccontains 'HashKnownHosts=no')
        Assert-EzDarkFactoryTrue -Condition ($args -notcontains 'StrictHostKeyChecking=no')
        $knownPath = $paths.InstanceKnownHosts
        if ($script:EzDarkFactoryIsWindowsHost) { $knownPath = $knownPath.Replace('\', '/') }
        Assert-EzDarkFactoryTrue -Condition ($args -ccontains ('UserKnownHostsFile="' + $knownPath + '"'))
        Assert-EzDarkFactoryEqual -Actual $args[[Array]::IndexOf($args, '-i') + 1] -Expected $paths.ControllerPrivateKey
        Assert-EzDarkFactoryTrue -Condition ($args -ccontains 'BatchMode=yes')
        Assert-EzDarkFactoryEqual -Actual $args[$args.Count - 2] -Expected 'coder@127.0.0.1'
        $remote = $args[$args.Count - 1]
        $module = Get-Module EzDarkFactory
        $quotedSingle = & $module { ConvertTo-EzDarkFactoryPosixArgument -Value "x'y" }
        Assert-EzDarkFactoryTrue -Condition ($remote -match "'a b'")
        Assert-EzDarkFactoryTrue -Condition ($remote.Contains($quotedSingle)) -Message 'Single quotes must be encoded without losing the argv boundary.'
        Assert-EzDarkFactoryTrue -Condition ($remote.EndsWith("''", [StringComparison]::Ordinal))
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'SSH: launch-local candidate may accept a new key without weakening managed trust' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'ssh candidate argv'
    try {
        $paths = Get-EzDarkFactorySshPaths -Root $root -InstanceName 'ssh-agent'
        $candidate = Join-Path $paths.KnownHostsDirectory '.candidate'
        $args = New-EzDarkFactorySshCommandArguments -PrivateKey $paths.ControllerPrivateKey -KnownHosts $candidate -Port 22009 -Batch -AcceptNewHostKey -RemoteCommand @('true')
        Assert-EzDarkFactoryTrue -Condition ($args -ccontains 'StrictHostKeyChecking=accept-new')
        Assert-EzDarkFactoryTrue -Condition ($args -notcontains 'StrictHostKeyChecking=no')
        Assert-EzDarkFactoryTrue -Condition ($args -ccontains 'UpdateHostKeys=no')
        Assert-EzDarkFactoryTrue -Condition ($args -ccontains 'HostKeyAlgorithms=ssh-ed25519')
        Assert-EzDarkFactoryTrue -Condition ($args -ccontains 'HashKnownHosts=no')
        $knownPath = [IO.Path]::GetFullPath($candidate)
        if ($script:EzDarkFactoryIsWindowsHost) { $knownPath = $knownPath.Replace('\', '/') }
        Assert-EzDarkFactoryTrue -Condition ($args -ccontains ('UserKnownHostsFile="' + $knownPath + '"'))
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'SSH: scp argv preserves host paths containing spaces as one token' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'scp spaces'
    try {
        $paths = Get-EzDarkFactorySshPaths -Root $root -InstanceName 'ssh-agent'
        $hostPath = Join-Path $root 'host file with spaces.txt'
        $remote = 'coder@127.0.0.1:/tmp/guest file.txt'
        $args = New-EzDarkFactoryScpCommandArguments -PrivateKey $paths.ControllerPrivateKey -KnownHosts $paths.InstanceKnownHosts -Port 22002 -Source $hostPath -Destination $remote
        $separator = [Array]::IndexOf($args, '--')
        Assert-EzDarkFactoryTrue -Condition ($separator -ge 0)
        Assert-EzDarkFactoryEqual -Actual $args[$separator + 1] -Expected $hostPath
        Assert-EzDarkFactoryEqual -Actual $args[$separator + 2] -Expected $remote
        Assert-EzDarkFactoryTrue -Condition ($args -ccontains 'StrictHostKeyChecking=yes')
        Assert-EzDarkFactoryTrue -Condition ($args -notcontains 'StrictHostKeyChecking=no')
        Assert-EzDarkFactoryEqual -Actual $args[[Array]::IndexOf($args, '-i') + 1] -Expected $paths.ControllerPrivateKey
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'SSH: known-hosts state is bundle-scoped and one file per managed instance' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'known hosts'
    try {
        $paths = Get-EzDarkFactorySshPaths -Root $root -InstanceName 'agent-one'
        $runtime = Get-EzDarkFactoryPaths -Root $root
        Assert-EzDarkFactoryTrue -Condition ($paths.InstanceKnownHosts.StartsWith($runtime.Keys, [StringComparison]::OrdinalIgnoreCase))
        Assert-EzDarkFactoryTrue -Condition ($paths.InstanceKnownHosts -match 'known-hosts[\\/]+agent-one\.known_hosts$')
        Assert-EzDarkFactoryTrue -Condition ($paths.ControllerPrivateKey.StartsWith($runtime.Keys, [StringComparison]::OrdinalIgnoreCase))
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'SSH: configuration path quoting preserves literal syntax and refuses hidden expansion' -ScriptBlock {
    $module = Get-Module EzDarkFactory
    $path = 'trust "quoted" ; StrictHostKeyChecking=no # %h'
    $encoded = & $module { param($p) ConvertTo-EzDarkFactoryOpenSshConfigPath -Path $p -ExpandTokens } $path
    Assert-EzDarkFactoryEqual -Actual $encoded -Expected '"trust \"quoted\" ; StrictHostKeyChecking=no # %%h"'
    $slashPath = 'trust\literal'
    $encodedSlash = & $module { param($p) ConvertTo-EzDarkFactoryOpenSshConfigPath -Path $p -ExpandTokens } $slashPath
    $expectedSlash = if ($script:EzDarkFactoryIsWindowsHost) { '"trust/literal"' } else { '"trust\\literal"' }
    Assert-EzDarkFactoryEqual -Actual $encodedSlash -Expected $expectedSlash
    foreach ($bad in @("trust`nStrictHostKeyChecking=no", "trust`rnext", ('trust' + [char]0 + 'next'), 'trust${HOME}')) {
        Assert-EzDarkFactoryThrows -ScriptBlock {
            & $module { param($p) ConvertTo-EzDarkFactoryOpenSshConfigPath -Path $p -ExpandTokens } $bad
        } -MessagePattern 'OpenSSH.*paths' | Out-Null
    }
    foreach ($kind in @('ssh', 'scp')) {
        Assert-EzDarkFactoryThrows -ScriptBlock {
            if ($kind -ceq 'ssh') { New-EzDarkFactorySshCommandArguments -PrivateKey 'unused' -KnownHosts 'trust${HOME}' -Port 22001 }
            else { New-EzDarkFactoryScpCommandArguments -PrivateKey 'unused' -KnownHosts 'trust${HOME}' -Port 22001 -Source 'source' -Destination 'destination' }
        } -MessagePattern 'Move the bundle' | Out-Null
    }
}

$sshParserCommand = @(Get-Command -Name 'ssh' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
$sshParserSkip = if ($sshParserCommand.Count -eq 0) { 'The real OpenSSH client is unavailable; configuration-parser regression requires ssh.' } else { '' }
$sshParserPath = if ($sshParserCommand.Count -eq 0) { '' } else { $sshParserCommand[0].Source }
Add-EzDarkFactoryTest -Name 'SSH: real OpenSSH parses SSH and SCP trust paths as one literal filename' -Data $sshParserPath -SkipReason $sshParserSkip -ScriptBlock {
    param($sshPath)
    $root = New-EzDarkFactoryTestDirectory -Prefix 'ssh parser [spaces]'
    $socket = [Net.Sockets.Socket]::new([Net.Sockets.AddressFamily]::InterNetwork, [Net.Sockets.SocketType]::Stream, [Net.Sockets.ProtocolType]::Tcp)
    try {
        # Hold a loopback port without listening. The real client expands its
        # configuration, then receives a refusal or a bounded Windows connect
        # timeout; no SSH server is contacted.
        $socket.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Loopback, 0))
        $port = ([Net.IPEndPoint]$socket.LocalEndPoint).Port
        $config = Join-Path $root 'empty config'
        [IO.File]::WriteAllText($config, '')
        $privateKey = Join-Path $root 'unused private key'
        $knownHosts = Join-Path $root 'known hosts literal %h'
        $expected = [IO.Path]::GetFullPath($knownHosts)
        if ($script:EzDarkFactoryIsWindowsHost) { $expected = $expected.Replace('\', '/') }
        $sshArguments = New-EzDarkFactorySshCommandArguments -PrivateKey $privateKey -KnownHosts $knownHosts -Port $port -Batch -ConnectTimeoutSeconds 1
        $scpArguments = New-EzDarkFactoryScpCommandArguments -PrivateKey $privateKey -KnownHosts $knownHosts -Port $port -Source 'unused source' -Destination 'coder@127.0.0.1:/unused'
        $scpOption = @($scpArguments | Where-Object { $_ -like 'UserKnownHostsFile=*' })
        Assert-EzDarkFactoryEqual -Actual $scpOption.Count -Expected 1
        Assert-EzDarkFactoryTrue -Condition ($sshArguments -ccontains $scpOption[0])
        $common = @('-vvv', '-F', $config, '-p', [string]$port, '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=1')
        $injected = $expected + ' " ; StrictHostKeyChecking=no # extra %h'
        $module = Get-Module EzDarkFactory
        $injectedOption = 'UserKnownHostsFile=' + (& $module { param($p) ConvertTo-EzDarkFactoryOpenSshConfigPath -Path $p -ExpandTokens } $injected)
        $cases = @(
            [pscustomobject]@{ Name = 'SSH'; Arguments = (@('-vvv', '-F', $config) + $sshArguments); Expected = $expected },
            [pscustomobject]@{ Name = 'SCP'; Arguments = ($common + @('-o', $scpOption[0], 'coder@127.0.0.1')); Expected = $expected },
            [pscustomobject]@{ Name = 'quoted config syntax'; Arguments = ($common + @('-o', $injectedOption, 'coder@127.0.0.1')); Expected = $injected }
        )
        foreach ($case in $cases) {
            $result = Invoke-EzDarkFactoryProcess -FilePath $sshPath -ArgumentList $case.Arguments -WorkingDirectory $root -TimeoutSeconds 6
            Assert-EzDarkFactoryEqual -Actual $result.ExitCode -Expected 255 -Message $case.Name
            # ssh -G flattens multiple paths into the same displayed line. A
            # literal percent forces this expansion diagnostic, which reveals
            # each actual parsed filename and catches the original split path.
            $expanded = @($result.StdErr -split '\r?\n' | Where-Object { $_ -match 'expanded UserKnownHostsFile' })
            Assert-EzDarkFactoryEqual -Actual $expanded.Count -Expected 1 -Message "$($case.Name): $($result.StdErr)"
            Assert-EzDarkFactoryTrue -Condition ($expanded[0].EndsWith((" -> '" + $case.Expected + "'"), [StringComparison]::Ordinal)) -Message "$($case.Name) did not preserve the complete literal trust path: $($expanded[0])"
            Assert-EzDarkFactoryTrue -Condition ($result.StdErr -match 'Connection (refused|timed out)') -Message "$($case.Name) must refuse or time out at the reserved, non-listening port: $($result.StdErr)"
        }
    }
    finally {
        $socket.Dispose()
        Remove-EzDarkFactoryTestDirectory -Path $root
    }
}

Add-EzDarkFactoryTest -Name 'SSH: readiness bootstraps trust through ssh accept-new only in the launch-local candidate' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'ssh accept new readiness'
    try {
        $paths = Get-EzDarkFactorySshPaths -Root $root -InstanceName 'ssh-agent'
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($paths.AccessState))
        $intent = New-EzDarkFactorySshTestIntent
        $access = New-EzDarkFactorySshTestAccess -Root $root -Intent $intent -Port 22079 -LaunchId ('d' * 32)
        $launch = New-EzDarkFactorySshTestLaunch -Root $root -Intent $intent -Access $access
        $identity = [pscustomobject]@{ PrivateKey = (Join-Path $root 'unused-key') }
        $tooling = [pscustomobject]@{ Ssh = 'unused-ssh' }
        $identityJson = New-EzDarkFactorySshTestIdentityJson -Intent $intent -InstanceName 'ssh-agent'
        $nl = [Environment]::NewLine
        $readyOutput = New-EzDarkFactorySshTestProbe -IdentityBase64 (ConvertTo-EzDarkFactorySshTestBase64 $identityJson) -CloudStatus 'status: done' -Ready:$true
        $module = Get-Module EzDarkFactory
        $observed = & $module {
            param($r, $i, $a, $id, $tools, $output, $processProvider)
            $state = [pscustomobject]@{ AcceptNew = $false; StrictBypass = $false }
            $sshOutput = $output
            $candidatePath = Join-Path (Get-EzDarkFactorySshPaths -Root $r -InstanceName 'ssh-agent').KnownHostsDirectory ('.ssh-agent.' + $a.launchId + '.candidate')
            $candidateOption = 'UserKnownHostsFile=' + (ConvertTo-EzDarkFactoryOpenSshConfigPath -Path $candidatePath -ExpandTokens)
            $runner = {
                param($exe, $arguments, $timeout)
                $state.AcceptNew = $arguments -ccontains 'StrictHostKeyChecking=accept-new'
                $state.StrictBypass = $arguments -contains 'StrictHostKeyChecking=no'
                if ($arguments -cnotcontains $candidateOption) { throw 'fixture did not receive the expected candidate known-hosts path' }
                [IO.File]::WriteAllText($candidatePath, ('[127.0.0.1]:22079 ssh-ed25519 CCCC' + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
                return [pscustomobject]@{ ExitCode = 0; StdOut = $sshOutput; StdErr = '' }
            }.GetNewClosure()
            $ready = Wait-EzDarkFactorySshReady -Root $r -InstanceName 'ssh-agent' -Intent $i -Access $a -Identity $id -Tooling $tools -TimeoutSeconds 2 -PortProbe { param($hostAddress, $port) return $true } -SshRunner $runner -ProcessProvider $processProvider
            return [pscustomobject]@{ Ready = $ready; AcceptNew = $state.AcceptNew; StrictBypass = $state.StrictBypass }
        } $root $intent $access $identity $tooling $readyOutput $launch.ProcessProvider

        Assert-EzDarkFactoryEqual -Actual $observed.Ready.state -Expected 'READY'
        Assert-EzDarkFactoryEqual -Actual $observed.AcceptNew -Expected $true
        Assert-EzDarkFactoryEqual -Actual $observed.StrictBypass -Expected $false
        $managed = [IO.File]::ReadAllText($paths.InstanceKnownHosts)
        Assert-EzDarkFactoryTrue -Condition ($managed.Contains('[127.0.0.1]:22079 ssh-ed25519 CCCC'))
        $temporary = @(Get-ChildItem -LiteralPath $paths.KnownHostsDirectory -Filter '*.candidate' -File -ErrorAction SilentlyContinue)
        Assert-EzDarkFactoryEqual -Actual $temporary.Count -Expected 0
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'SSH: changed host key remains staged until authenticated identity proof then replaces only scoped trust' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'host key rotation'
    try {
        $paths = Get-EzDarkFactorySshPaths -Root $root -InstanceName 'ssh-agent'
        [void][IO.Directory]::CreateDirectory($paths.KnownHostsDirectory)
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($paths.AccessState))
        $oldLine = '[127.0.0.1]:22001 ssh-ed25519 AAAA'
        $newLine = '[127.0.0.1]:22077 ssh-ed25519 BBBB'
        [IO.File]::WriteAllText($paths.InstanceKnownHosts, ($oldLine + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))

        $intent = New-EzDarkFactorySshTestIntent
        $access = New-EzDarkFactorySshTestAccess -Root $root -Intent $intent -Port 22077 -LaunchId ('a' * 32)
        $launch = New-EzDarkFactorySshTestLaunch -Root $root -Intent $intent -Access $access
        $identity = [pscustomobject]@{ PrivateKey = (Join-Path $root 'unused-key') }
        $tooling = [pscustomobject]@{ Ssh = 'unused-ssh'; Keyscan = 'unused-keyscan' }
        $identityJson = New-EzDarkFactorySshTestIdentityJson -Intent $intent -InstanceName 'ssh-agent'
        $nl = [Environment]::NewLine
        $readyOutput = New-EzDarkFactorySshTestProbe -IdentityBase64 (ConvertTo-EzDarkFactorySshTestBase64 $identityJson) -CloudStatus 'status: done' -Ready:$true

        $module = Get-Module EzDarkFactory
        $candidate = & $module {
            param($r, $line)
            New-EzDarkFactoryCandidateKnownHosts -Root $r -InstanceName 'ssh-agent' -LaunchId ('b' * 32) -Port 22077 -ScannedLine $line
        } $root $newLine
        try {
            Assert-EzDarkFactoryEqual -Actual $candidate.Changed -Expected $true
            Assert-EzDarkFactoryTrue -Condition ([IO.File]::ReadAllText($paths.InstanceKnownHosts).Contains('ssh-ed25519 AAAA')) -Message 'Observed key rotation must not overwrite existing trust before identity proof.'
        }
        finally { Remove-Item -LiteralPath $candidate.Candidate -Force -ErrorAction SilentlyContinue }

        $ready = & $module {
            param($r, $i, $a, $id, $tools, $line, $output, $processProvider)
            $scanLine = $line
            $sshOutput = $output
            $scanner = { param($port, $timeout) return $scanLine }.GetNewClosure()
            $runner = { param($exe, $arguments, $timeout) return [pscustomobject]@{ ExitCode = 0; StdOut = $sshOutput; StdErr = '' } }.GetNewClosure()
            Wait-EzDarkFactorySshReady -Root $r -InstanceName 'ssh-agent' -Intent $i -Access $a -Identity $id -Tooling $tools -TimeoutSeconds 2 -PortProbe { param($hostAddress, $port) return $true } -HostKeyScanner $scanner -SshRunner $runner -ProcessProvider $processProvider
        } $root $intent $access $identity $tooling $newLine $readyOutput $launch.ProcessProvider
        Assert-EzDarkFactoryEqual -Actual $ready.state -Expected 'READY'
        $managed = [IO.File]::ReadAllText($paths.InstanceKnownHosts)
        Assert-EzDarkFactoryTrue -Condition ($managed.Contains('ssh-ed25519 BBBB'))
        Assert-EzDarkFactoryTrue -Condition (-not $managed.Contains('ssh-ed25519 AAAA'))
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'SSH: failed identity proof cannot promote a changed host key' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'host key failed proof'
    try {
        $paths = Get-EzDarkFactorySshPaths -Root $root -InstanceName 'ssh-agent'
        [void][IO.Directory]::CreateDirectory($paths.KnownHostsDirectory)
        [IO.File]::WriteAllText($paths.InstanceKnownHosts, ('[127.0.0.1]:22001 ssh-ed25519 AAAA' + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
        $intent = New-EzDarkFactorySshTestIntent
        $access = New-EzDarkFactorySshTestAccess -Root $root -Intent $intent -Port 22078 -LaunchId ('c' * 32)
        $launch = New-EzDarkFactorySshTestLaunch -Root $root -Intent $intent -Access $access
        $wrong = New-EzDarkFactorySshTestIdentityJson -Intent $intent -InstanceName 'wrong-agent'
        $nl = [Environment]::NewLine
        $wrongOutput = New-EzDarkFactorySshTestProbe -IdentityBase64 (ConvertTo-EzDarkFactorySshTestBase64 $wrong) -CloudStatus 'status: done' -Ready:$true
        $module = Get-Module EzDarkFactory
        Assert-EzDarkFactoryThrows -ScriptBlock {
            & $module {
                param($r, $i, $a, $output, $processProvider)
                $id = [pscustomobject]@{ PrivateKey = (Join-Path $r 'unused-key') }
                $tools = [pscustomobject]@{ Ssh = 'unused-ssh'; Keyscan = 'unused-keyscan' }
                $sshOutput = $output
                $runner = { param($exe, $arguments, $timeout) return [pscustomobject]@{ ExitCode = 0; StdOut = $sshOutput; StdErr = '' } }.GetNewClosure()
                Wait-EzDarkFactorySshReady -Root $r -InstanceName 'ssh-agent' -Intent $i -Access $a -Identity $id -Tooling $tools -TimeoutSeconds 2 -PortProbe { param($hostAddress, $port) return $true } -HostKeyScanner { param($port, $timeout) return '[127.0.0.1]:22078 ssh-ed25519 BBBB' } -SshRunner $runner -ProcessProvider $processProvider
            } $root $intent $access $wrongOutput $launch.ProcessProvider
        } -MessagePattern 'identity mismatch' | Out-Null
        $managed = [IO.File]::ReadAllText($paths.InstanceKnownHosts)
        Assert-EzDarkFactoryTrue -Condition ($managed.Contains('ssh-ed25519 AAAA'))
        Assert-EzDarkFactoryTrue -Condition (-not $managed.Contains('ssh-ed25519 BBBB'))
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'SSH: readiness rejects authenticated identity mismatch' -ScriptBlock {
    $expected = New-EzDarkFactorySshTestIntent
    $wrong = New-EzDarkFactorySshTestIdentityJson -Intent $expected -InstanceName 'other-agent'
    $nl = [Environment]::NewLine
    $output = New-EzDarkFactorySshTestProbe -IdentityBase64 (ConvertTo-EzDarkFactorySshTestBase64 $wrong) -CloudStatus 'status: done' -Ready:$true
    Assert-EzDarkFactoryThrows -ScriptBlock {
        ConvertFrom-EzDarkFactoryReadinessProbe -StdOut $output -ExpectedInstanceName 'ssh-agent' -ExpectedBaseId $expected.baseId -ExpectedProfile 'normal' -ExpectedCloudInstanceId (Get-EzDarkFactorySshTestCloudId -Intent $expected) -ExpectedProvisioningProfile 'coding-default' -ExpectedProvisioningVersion 1 -ExpectedProvisioningDigest (Get-EzDarkFactoryCodingProfile).Digest
    } -MessagePattern 'identity mismatch' | Out-Null
}

Add-EzDarkFactoryTest -Name 'SSH: readiness distinguishes cloud-init incomplete and failed states from READY' -ScriptBlock {
    $intent = New-EzDarkFactorySshTestIntent
    $identity = New-EzDarkFactorySshTestIdentityJson -Intent $intent -InstanceName 'ssh-agent'
    $identity64 = ConvertTo-EzDarkFactorySshTestBase64 $identity
    $nl = [Environment]::NewLine

    $runningOutput = New-EzDarkFactorySshTestProbe -IdentityBase64 $identity64 -CloudStatus 'status: running' -Ready:$false
    $running = ConvertFrom-EzDarkFactoryReadinessProbe -StdOut $runningOutput -ExpectedInstanceName 'ssh-agent' -ExpectedBaseId $intent.baseId -ExpectedProfile 'normal' -ExpectedCloudInstanceId (Get-EzDarkFactorySshTestCloudId -Intent $intent) -ExpectedProvisioningProfile 'coding-default' -ExpectedProvisioningVersion 1 -ExpectedProvisioningDigest (Get-EzDarkFactoryCodingProfile).Digest
    Assert-EzDarkFactoryEqual -Actual $running.Ready -Expected $false
    Assert-EzDarkFactoryEqual -Actual $running.CloudDone -Expected $false

    $failedOutput = New-EzDarkFactorySshTestProbe -IdentityBase64 $identity64 -CloudStatus 'status: error' -Ready:$false
    Assert-EzDarkFactoryThrows -ScriptBlock {
        ConvertFrom-EzDarkFactoryReadinessProbe -StdOut $failedOutput -ExpectedInstanceName 'ssh-agent' -ExpectedBaseId $intent.baseId -ExpectedProfile 'normal' -ExpectedCloudInstanceId (Get-EzDarkFactorySshTestCloudId -Intent $intent) -ExpectedProvisioningProfile 'coding-default' -ExpectedProvisioningVersion 1 -ExpectedProvisioningDigest (Get-EzDarkFactoryCodingProfile).Digest
    } -MessagePattern 'cloud-init reports failed' | Out-Null

    $readyOutput = New-EzDarkFactorySshTestProbe -IdentityBase64 $identity64 -CloudStatus 'status: done' -Ready:$true
    $ready = ConvertFrom-EzDarkFactoryReadinessProbe -StdOut $readyOutput -ExpectedInstanceName 'ssh-agent' -ExpectedBaseId $intent.baseId -ExpectedProfile 'normal' -ExpectedCloudInstanceId (Get-EzDarkFactorySshTestCloudId -Intent $intent) -ExpectedProvisioningProfile 'coding-default' -ExpectedProvisioningVersion 1 -ExpectedProvisioningDigest (Get-EzDarkFactoryCodingProfile).Digest
    Assert-EzDarkFactoryEqual -Actual $ready.Ready -Expected $true
}

Add-EzDarkFactoryTest -Name 'SSH: readiness wait has a bounded total timeout when TCP never opens' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'ssh readiness timeout'
    try {
        $intent = New-EzDarkFactorySshTestIntent
        $access = New-EzDarkFactorySshTestAccess -Root $root -Intent $intent -Port 22001 -LaunchId ('a' * 32)
        $launch = New-EzDarkFactorySshTestLaunch -Root $root -Intent $intent -Access $access
        $identity = [pscustomobject]@{ PrivateKey = (Join-Path $root 'unused-key') }
        $tooling = [pscustomobject]@{ Ssh = 'unused-ssh'; Keyscan = 'unused-keyscan' }
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $module = Get-Module EzDarkFactory
        Assert-EzDarkFactoryThrows -ScriptBlock {
            & $module {
                param($r, $i, $a, $id, $tools, $processProvider)
                Wait-EzDarkFactorySshReady -Root $r -InstanceName 'ssh-agent' -Intent $i -Access $a -Identity $id -Tooling $tools -TimeoutSeconds 1 -PortProbe { param($hostAddress, $port) return $false } -ProcessProvider $processProvider
            } $root $intent $access $identity $tooling $launch.ProcessProvider
        } -MessagePattern 'did not reach authenticated SSH READY within 1 seconds' | Out-Null
        $clock.Stop()
        Assert-EzDarkFactoryTrue -Condition ($clock.Elapsed.TotalSeconds -lt 4) -Message 'Readiness timeout must remain bounded.'
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'SSH: exec process result preserves remote non-zero exit and reserves 255 for transport failure' -ScriptBlock {
    $module = Get-Module EzDarkFactory
    $resolved = & $module {
        Resolve-EzDarkFactoryExecProcessResult -Result ([pscustomobject]@{ ExitCode = 37; StdOut = 'partial output'; StdErr = 'remote error' })
    }
    Assert-EzDarkFactoryEqual -Actual $resolved.exitCode -Expected 37
    Assert-EzDarkFactoryEqual -Actual $resolved.stdout -Expected 'partial output'
    Assert-EzDarkFactoryEqual -Actual $resolved.stderr -Expected 'remote error'
    Assert-EzDarkFactoryThrows -ScriptBlock {
        & $module {
            Resolve-EzDarkFactoryExecProcessResult -Result ([pscustomobject]@{ ExitCode = 255; StdOut = ''; StdErr = 'host key failure' })
        }
    } -MessagePattern 'transport/authentication failed' | Out-Null
}

Add-EzDarkFactoryTest -Name 'SSH: configured port allocation skips collisions and stays inside the reviewed range' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'ssh ports'
    try {
        $port = Get-EzDarkFactoryAvailableSshPort -Root $root -PortProbe { param($candidate) return $candidate -eq 22003 }
        Assert-EzDarkFactoryEqual -Actual $port -Expected 22003
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Get-EzDarkFactoryAvailableSshPort -Root $root -PortProbe { param($candidate) return $false }
        } -MessagePattern 'No (?:unreserved )?loopback SSH port is available.*22000-22999' | Out-Null
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'SSH: missing OpenSSH tools produce concrete remediation' -ScriptBlock {
    $module = Get-Module EzDarkFactory
    Assert-EzDarkFactoryThrows -ScriptBlock {
        & $module {
            Assert-EzDarkFactoryOpenSshTools -Tooling ([pscustomobject]@{
                Valid = $false
                Missing = @('ssh.exe', 'scp.exe')
                Reason = 'Missing required OpenSSH application(s): ssh.exe, scp.exe.'
            })
        }
    } -MessagePattern 'Install the Windows OpenSSH Client.*ssh\.exe.*scp\.exe.*ssh-keygen\.exe' | Out-Null
}

Add-EzDarkFactoryTest -Name 'SSH: implementation never disables strict host-key checking' -ScriptBlock {
    $source = [IO.File]::ReadAllText((Join-Path $script:EzDarkFactoryRepositoryRoot 'src/EzDarkFactory/Ssh.ps1'))
    Assert-EzDarkFactoryTrue -Condition ($source -notmatch 'StrictHostKeyChecking=no') -Message 'Managed SSH must never use the global host-key bypass.'
    Assert-EzDarkFactoryTrue -Condition ($source -match 'StrictHostKeyChecking=yes')
    Assert-EzDarkFactoryTrue -Condition ($source -match 'UpdateHostKeys=no')
    Assert-EzDarkFactoryTrue -Condition ($source -match 'UserKnownHostsFile=')
    Assert-EzDarkFactoryTrue -Condition ($source -match "'accept-new'") -Message 'Launch-local candidate bootstrap must use OpenSSH accept-new rather than disabling verification.'
    Assert-EzDarkFactoryTrue -Condition ($source -notmatch 'ssh-keyscan') -Message 'Windows ssh-keyscan is not a supported trust bootstrap because affected Win32 builds can negotiate an unavailable KEX.'
}


Add-EzDarkFactoryTest -Name 'SSH: a newly generated controller key is removed if Windows ACL hardening fails' -ScriptBlock {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return }
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'controller key acl failure'
    try {
        $tooling = [pscustomobject]@{
            Valid = $true
            Ssh = 'fake-ssh'
            Scp = 'fake-scp'
            Keygen = 'fake-keygen'
            Missing = @()
            Reason = 'fixture'
        }
        $runner = {
            param($exe, $arguments, $timeout)
            if ($exe -ceq 'fake-keygen') {
                $index = [Array]::IndexOf([object[]]$arguments, '-f')
                if ($index -lt 0) { throw 'fixture did not receive key destination' }
                $private = [string]$arguments[$index + 1]
                [IO.File]::WriteAllText($private, 'fixture-private', (New-Object Text.UTF8Encoding($false)))
                [IO.File]::WriteAllText(($private + '.pub'), 'ssh-ed25519 AAAA fixture', (New-Object Text.UTF8Encoding($false)))
                return [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
            }
            return [pscustomobject]@{ ExitCode = 5; StdOut = ''; StdErr = 'fixture ACL failure' }
        }
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Get-EzDarkFactoryControllerSshIdentity -Root $root -Tooling $tooling -ProcessRunner $runner
        } -MessagePattern 'Failed to restrict.*private-key ACL' | Out-Null
        $paths = Get-EzDarkFactorySshPaths -Root $root
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath $paths.ControllerPrivateKey)) -Message 'Unsafe freshly generated private key must be removed.'
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath $paths.ControllerPublicKey)) -Message 'Orphan public half from failed fresh generation must also be removed.'
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}


Add-EzDarkFactoryTest -Name 'SSH: seed server lifetime cannot pre-empt READY deadline' -ScriptBlock {
    $module = Get-Module EzDarkFactory
    $short = & $module { Get-EzDarkFactorySeedServerLifetimeSeconds -ReadyTimeoutSeconds 1 }
    $normal = & $module { Get-EzDarkFactorySeedServerLifetimeSeconds -ReadyTimeoutSeconds 60 }
    $maximum = & $module { Get-EzDarkFactorySeedServerLifetimeSeconds -ReadyTimeoutSeconds 3600 }

    Assert-EzDarkFactoryEqual -Actual $short -Expected 31
    Assert-EzDarkFactoryEqual -Actual $normal -Expected 90
    Assert-EzDarkFactoryEqual -Actual $maximum -Expected 3630
    Assert-EzDarkFactoryTrue -Condition ($short -gt 1 -and $normal -gt 60 -and $maximum -gt 3600) -Message 'The subordinate seed server deadline must outlive the enclosing READY deadline.'
}


Add-EzDarkFactoryTest -Name 'SSH: readiness grants slow TCG SSH probes a bounded per-attempt budget' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'ssh slow readiness'
    try {
        $paths = Get-EzDarkFactorySshPaths -Root $root -InstanceName 'ssh-agent'
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($paths.AccessState))
        $intent = New-EzDarkFactorySshTestIntent
        $access = New-EzDarkFactorySshTestAccess -Root $root -Intent $intent -Port 22080 -LaunchId ('d' * 32)
        $launch = New-EzDarkFactorySshTestLaunch -Root $root -Intent $intent -Access $access
        $identity = [pscustomobject]@{ PrivateKey = (Join-Path $root 'unused-key') }
        $tooling = [pscustomobject]@{ Ssh = 'unused-ssh' }
        $identityJson = New-EzDarkFactorySshTestIdentityJson -Intent $intent -InstanceName 'ssh-agent'
        $nl = [Environment]::NewLine
        $readyOutput = New-EzDarkFactorySshTestProbe -IdentityBase64 (ConvertTo-EzDarkFactorySshTestBase64 $identityJson) -CloudStatus 'status: done' -Ready:$true
        $module = Get-Module EzDarkFactory
        $observed = & $module {
            param($r, $i, $a, $id, $tools, $output, $processProvider)
            $state = [pscustomobject]@{ ProcessTimeout = 0; ConnectTimeout = '' }
            $sshOutput = $output
            $candidatePath = Join-Path (Get-EzDarkFactorySshPaths -Root $r -InstanceName 'ssh-agent').KnownHostsDirectory ('.ssh-agent.' + $a.launchId + '.candidate')
            $candidateOption = 'UserKnownHostsFile=' + (ConvertTo-EzDarkFactoryOpenSshConfigPath -Path $candidatePath -ExpandTokens)
            $runner = {
                param($exe, $arguments, $timeout)
                $state.ProcessTimeout = $timeout
                $state.ConnectTimeout = @($arguments | Where-Object { $_ -like 'ConnectTimeout=*' } | Select-Object -First 1)[0]
                if ($arguments -cnotcontains $candidateOption) { throw 'fixture did not receive the expected candidate known-hosts path' }
                [IO.File]::WriteAllText($candidatePath, ('[127.0.0.1]:22080 ssh-ed25519 DDDD' + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
                return [pscustomobject]@{ ExitCode = 0; StdOut = $sshOutput; StdErr = '' }
            }.GetNewClosure()
            $ready = Wait-EzDarkFactorySshReady -Root $r -InstanceName 'ssh-agent' -Intent $i -Access $a -Identity $id -Tooling $tools -TimeoutSeconds 120 -PortProbe { param($hostAddress, $port) return $true } -SshRunner $runner -ProcessProvider $processProvider
            return [pscustomobject]@{ Ready = $ready; ProcessTimeout = $state.ProcessTimeout; ConnectTimeout = $state.ConnectTimeout }
        } $root $intent $access $identity $tooling $readyOutput $launch.ProcessProvider

        Assert-EzDarkFactoryEqual -Actual $observed.Ready.state -Expected 'READY'
        Assert-EzDarkFactoryTrue -Condition ($observed.ProcessTimeout -ge 118 -and $observed.ProcessTimeout -le 120) -Message 'The live profile check must fit within the caller total deadline.'
        Assert-EzDarkFactoryEqual -Actual $observed.ConnectTimeout -Expected 'ConnectTimeout=15'
        Assert-EzDarkFactoryTrue -Condition ([IO.File]::ReadAllText($paths.InstanceKnownHosts).Contains('[127.0.0.1]:22080 ssh-ed25519 DDDD'))
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}
