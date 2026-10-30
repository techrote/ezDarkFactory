function New-EzDarkFactoryPortabilityIdentityTestIntent {
    param([string]$Name = 'ssh-agent', [string]$Generation = ('b' * 32))
    $intent = New-EzDarkFactorySshTestIntent -Name $Name
    $intent.schemaVersion = 2
    $intent | Add-Member -NotePropertyName identityGeneration -NotePropertyValue $Generation
    return $intent
}

function Get-EzDarkFactoryPortabilitySeedFile {
    param([string]$UserData, [string]$Path)
    $pattern = '(?m)^  - path: ' + [regex]::Escape($Path) + '\n    owner: root:root\n    permissions: ''[0-7]+''\n    encoding: b64\n    content: (?<data>[A-Za-z0-9+/=]+)$'
    $match = [regex]::Match($UserData, $pattern)
    if (-not $match.Success) { throw "Seed lacks encoded file '$Path'." }
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($match.Groups['data'].Value))
}

function Invoke-EzDarkFactoryPortabilityIdentityWaitFixture {
    param([string]$Root, [object]$Intent, [object[]]$Outputs)
    $access = New-EzDarkFactorySshTestAccess -Root $Root -Intent $Intent
    $launch = New-EzDarkFactorySshTestLaunch -Root $Root -Intent $Intent -Access $access
    $access.state = 'READY'
    $access.readyAt = [DateTime]::UtcNow.ToString('o')
    $paths = Get-EzDarkFactorySshPaths -Root $Root -InstanceName $Intent.name
    [void][IO.Directory]::CreateDirectory($paths.KnownHostsDirectory)
    $managedText = '[127.0.0.1]:22001 ssh-ed25519 AAAA' + [Environment]::NewLine
    [IO.File]::WriteAllText($paths.InstanceKnownHosts, $managedText)
    $module = Get-Module EzDarkFactory
    return & $module {
        param($r, $i, $a, $responses, $managed, $old, $processProvider)
        $observed = [pscustomobject]@{ Calls = 0; Scans = 0; PrematurePromotion = $false; StrictBypass = $false; Ready = $null; Error = '' }
        $scanner = {
            param($port, $timeout)
            $observed.Scans++
            return '[127.0.0.1]:22001 ssh-ed25519 ' + $(if ($observed.Scans -eq 1) { 'BBBB' } else { 'CCCC' })
        }.GetNewClosure()
        $runner = {
            param($exe, $arguments, $timeout)
            if ([IO.File]::ReadAllText($managed) -cne $old) { $observed.PrematurePromotion = $true }
            if ($arguments -contains 'StrictHostKeyChecking=no') { $observed.StrictBypass = $true }
            $index = [Math]::Min($observed.Calls, $responses.Count - 1)
            $observed.Calls++
            return $responses[$index]
        }.GetNewClosure()
        try {
            $observed.Ready = Wait-EzDarkFactorySshReady -Root $r -InstanceName $i.name -Intent $i -Access $a -Identity ([pscustomobject]@{ PrivateKey = (Join-Path $r 'unused-key') }) -Tooling ([pscustomobject]@{ Ssh = 'unused-ssh' }) -TimeoutSeconds 2 -PortProbe { $true } -HostKeyScanner $scanner -SshRunner $runner -ProcessProvider $processProvider
        }
        catch { $observed.Error = $_.Exception.Message }
        return $observed
    } $Root $Intent $access $Outputs $paths.InstanceKnownHosts $managedText $launch.ProcessProvider
}

function Invoke-EzDarkFactoryPortabilityPublicationRaceFixture {
    param([string]$Root, [string]$Change, [switch]$BeforeWait)
    $intent = New-EzDarkFactoryPortabilityIdentityTestIntent
    $access = New-EzDarkFactorySshTestAccess -Root $Root -Intent $intent
    $launch = New-EzDarkFactorySshTestLaunch -Root $Root -Intent $intent -Access $access
    $proof = New-EzDarkFactorySshTestProbe -IdentityBase64 (ConvertTo-EzDarkFactorySshTestBase64 (New-EzDarkFactorySshTestIdentityJson -Intent $intent))
    $module = Get-Module EzDarkFactory
    return & $module {
        param($r, $i, $a, $fixture, $output, $change, $beforeWait)
        $paths = Get-EzDarkFactorySshPaths -Root $r -InstanceName $i.name
        [void][IO.Directory]::CreateDirectory($paths.KnownHostsDirectory)
        [IO.File]::WriteAllText($paths.InstanceKnownHosts, "[127.0.0.1]:22001 ssh-ed25519 AAAA`n")
        $observed = [pscustomobject]@{ Calls = 0; Changed = $false; Ready = $null; Error = ''; Intent = ''; Runtime = ''; Access = ''; Trust = '' }
        $runtimeModule = Get-Module EzDarkFactory
        $interleave = {
            & $runtimeModule {
                param($r, $i, $a, $fixture, $paths, $observed, $change)
                # A concurrent lifecycle operation must be able to obtain this lock
                # while SSH is outstanding, then publish its own durable state.
                $lock = Enter-EzDarkFactoryInstanceLifecycleLock -Root $r -InstanceName $i.name -TimeoutMilliseconds 200
                try {
                    $currentIntent = Get-EzDarkFactoryInstanceIntent -Root $r -InstanceName $i.name
                    $currentRuntime = Get-EzDarkFactoryRuntimeStateFile -Root $r -InstanceName $i.name
                    $currentAccess = $a | ConvertTo-Json -Depth 8 | ConvertFrom-Json
                    if ($change -ceq 'reset') { $currentIntent.identityGeneration = 'c' * 32 }
                    if ($change -ceq 'intent') { $currentIntent.cpus = 3; $currentIntent.profile = 'custom' }
                    if (@('reset', 'restart') -ccontains $change) {
                        $currentRuntime.launchId = 'd' * 32
                        $currentRuntime.pid++
                        $fixture.State.Processes[0].Pid = $currentRuntime.pid
                        $currentAccess.launchId = $currentRuntime.launchId
                    }
                    if ($change -ceq 'stopped') {
                        $currentRuntime.state = 'STOPPED'
                        $currentRuntime.stoppedAt = [DateTime]::UtcNow.ToString('o')
                    }
                    if (@('stopped', 'missing') -ccontains $change) { $fixture.State.Processes.Clear() }
                    if ($change -ceq 'journal') { [IO.File]::WriteAllText($fixture.Paths.Operation, '{"schemaVersion":1}') }
                    $currentAccess.cloudInstanceId = Get-EzDarkFactoryGuestCloudInstanceId -Intent $currentIntent
                    $currentAccess.profile = $currentIntent.profile
                    $currentAccess.state = 'READY'
                    $currentAccess.readyAt = [DateTime]::UtcNow.ToString('o')
                    Write-EzDarkFactoryJson -Path $fixture.Paths.Intent -Value $currentIntent -SchemaVersion 2
                    Write-EzDarkFactoryRuntimeStateFile -Root $r -InstanceName $i.name -Runtime $currentRuntime
                    Write-EzDarkFactorySshAccessState -Root $r -InstanceName $i.name -Access $currentAccess
                    [IO.File]::WriteAllText($paths.InstanceKnownHosts, "[127.0.0.1]:22001 ssh-ed25519 CCCC`n")
                    $observed.Intent = [IO.File]::ReadAllText($fixture.Paths.Intent)
                    $observed.Runtime = [IO.File]::ReadAllText($fixture.Paths.Runtime)
                    $observed.Access = [IO.File]::ReadAllText($paths.AccessState)
                    $observed.Trust = [IO.File]::ReadAllText($paths.InstanceKnownHosts)
                    $observed.Changed = $true
                }
                finally { $lock.Dispose() }
            } $r $i $a $fixture $paths $observed $change
        }.GetNewClosure()
        $runner = {
            param($exe, $arguments, $timeout)
            $observed.Calls++
            & $interleave
            return [pscustomobject]@{ ExitCode = 0; StdOut = $output; StdErr = '' }
        }.GetNewClosure()
        if ($beforeWait) { & $interleave }
        try {
            $observed.Ready = Wait-EzDarkFactorySshReady -Root $r -InstanceName $i.name -Intent $i -Access $a -Identity ([pscustomobject]@{ PrivateKey = 'unused' }) -Tooling ([pscustomobject]@{ Ssh = 'unused' }) -TimeoutSeconds 3 -PortProbe { $true } -HostKeyScanner { '[127.0.0.1]:22001 ssh-ed25519 BBBB' } -SshRunner $runner -ProcessProvider $fixture.ProcessProvider
        }
        catch { $observed.Error = $_.Exception.Message }
        return [pscustomobject]@{
            Observed = $observed
            Intent = [IO.File]::ReadAllText($fixture.Paths.Intent)
            Runtime = [IO.File]::ReadAllText($fixture.Paths.Runtime)
            Access = [IO.File]::ReadAllText($paths.AccessState)
            Trust = [IO.File]::ReadAllText($paths.InstanceKnownHosts)
            Candidates = @(Get-ChildItem -LiteralPath $paths.KnownHostsDirectory -Filter '*.candidate' -File -Force).Count
        }
    } $Root $intent $access $launch $proof $Change ([bool]$BeforeWait)
}

Add-EzDarkFactoryTest -Name 'Portability identity: successful stale SSH proof cannot overwrite concurrent lifecycle state or trust' -ScriptBlock {
    foreach ($change in @('reset', 'restart', 'intent', 'stopped', 'missing', 'journal')) {
        $root = New-EzDarkFactoryCheckoutFixture -Prefix ('readiness publication ' + $change)
        try {
            $result = Invoke-EzDarkFactoryPortabilityPublicationRaceFixture -Root $root -Change $change
            Assert-EzDarkFactoryEqual -Actual $result.Observed.Calls -Expected 1 -Message $change
            Assert-EzDarkFactoryTrue -Condition $result.Observed.Changed -Message "The $change interleaving must complete while the SSH proof is outstanding."
            Assert-EzDarkFactoryEqual -Actual $result.Observed.Ready -Expected $null -Message $change
            Assert-EzDarkFactoryTrue -Condition ($result.Observed.Error -match 'before SSH access publication.*Refusing stale readiness') -Message "$change must reject publication: $($result.Observed.Error)"
            Assert-EzDarkFactoryEqual -Actual $result.Intent -Expected $result.Observed.Intent -Message "$change must preserve current intent."
            Assert-EzDarkFactoryEqual -Actual $result.Runtime -Expected $result.Observed.Runtime -Message "$change must preserve current runtime."
            Assert-EzDarkFactoryEqual -Actual $result.Access -Expected $result.Observed.Access -Message "$change must preserve current access."
            Assert-EzDarkFactoryEqual -Actual $result.Trust -Expected $result.Observed.Trust -Message "$change must preserve current trust."
            Assert-EzDarkFactoryEqual -Actual $result.Candidates -Expected 0 -Message $change
        }
        finally { Remove-EzDarkFactoryTestDirectory -Path $root }
    }
}

Add-EzDarkFactoryTest -Name 'Portability identity: stale initial PROVISIONING cannot invalidate a replacement launch READY' -ScriptBlock {
    foreach ($change in @('reset', 'restart')) {
        $root = New-EzDarkFactoryCheckoutFixture -Prefix ('readiness initial publication ' + $change)
        try {
            $result = Invoke-EzDarkFactoryPortabilityPublicationRaceFixture -Root $root -Change $change -BeforeWait
            Assert-EzDarkFactoryEqual -Actual $result.Observed.Calls -Expected 0
            Assert-EzDarkFactoryEqual -Actual $result.Observed.Ready -Expected $null
            Assert-EzDarkFactoryTrue -Condition ($result.Observed.Error -match 'changed before SSH access publication.*Refusing stale readiness') -Message "$change must reject stale initial publication: $($result.Observed.Error)"
            Assert-EzDarkFactoryEqual -Actual $result.Intent -Expected $result.Observed.Intent
            Assert-EzDarkFactoryEqual -Actual $result.Runtime -Expected $result.Observed.Runtime
            Assert-EzDarkFactoryEqual -Actual $result.Access -Expected $result.Observed.Access
            Assert-EzDarkFactoryEqual -Actual $result.Trust -Expected $result.Observed.Trust
            Assert-EzDarkFactoryEqual -Actual ($result.Access | ConvertFrom-Json).state -Expected 'READY'
            Assert-EzDarkFactoryEqual -Actual $result.Candidates -Expected 0
        }
        finally { Remove-EzDarkFactoryTestDirectory -Path $root }
    }
}

Add-EzDarkFactoryTest -Name 'Portability identity: schema 1 cloud identity remains unchanged and schema 2 generation separates reset identity' -ScriptBlock {
    $module = Get-Module EzDarkFactory
    $legacy = New-EzDarkFactorySshTestIntent
    $legacyId = & $module { param($i) Get-EzDarkFactoryGuestCloudInstanceId -Intent $i } $legacy
    Assert-EzDarkFactoryEqual -Actual $legacyId -Expected 'ezdarkfactory-ssh-agent-de80abc68f36'
    $first = New-EzDarkFactoryPortabilityIdentityTestIntent
    $reset = New-EzDarkFactoryPortabilityIdentityTestIntent -Generation ('c' * 32)
    $other = New-EzDarkFactoryPortabilityIdentityTestIntent -Name 'other-agent'
    $identities = @($legacy, $first, $reset, $other | ForEach-Object {
        & $module { param($i) Get-EzDarkFactoryGuestCloudInstanceId -Intent $i } $_
    })
    Assert-EzDarkFactoryEqual -Actual (@($identities | Select-Object -Unique).Count) -Expected 4
    Assert-EzDarkFactoryEqual -Actual $first.createdAt -Expected $reset.createdAt
    Assert-EzDarkFactoryEqual -Actual $first.baseId -Expected $reset.baseId
    $uuid = & $module { param($i) Get-EzDarkFactoryGuestMachineUuid -Intent $i } $first
    Assert-EzDarkFactoryTrue -Condition ($uuid -cmatch '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')
    Assert-EzDarkFactoryEqual -Actual (& $module { param($i) Get-EzDarkFactoryGuestMachineUuid -Intent $i } $first) -Expected $uuid
    Assert-EzDarkFactoryTrue -Condition ((& $module { param($i) Get-EzDarkFactoryGuestMachineUuid -Intent $i } $reset) -cne $uuid)
}

Add-EzDarkFactoryTest -Name 'Portability identity: malformed identity generations refuse before seed generation' -ScriptBlock {
    foreach ($generation in @('', ('a' * 31), ('a' * 33), ('A' * 32), ('x' * 32), 'abc;reboot', $null, 123)) {
        $intent = New-EzDarkFactoryPortabilityIdentityTestIntent
        $intent.identityGeneration = $generation
        Assert-EzDarkFactoryThrows -ScriptBlock {
            New-EzDarkFactoryInstanceSeedData -Root $script:EzDarkFactoryRepositoryRoot -InstanceName $intent.name -Intent $intent -ControllerPublicKey 'ssh-ed25519 AAAA'
        } -MessagePattern 'identityGeneration.*32 lowercase' | Out-Null
    }
}

Add-EzDarkFactoryTest -Name 'Portability identity: cache policy uses system configuration without degrading cloud-config user data' -ScriptBlock {
    # cloud-init 26.1 schema-cloud-config-v1.json rejects unknown top-level
    # properties. manual_cache_clean is a system setting, not a user-data key.
    foreach ($intent in @((New-EzDarkFactorySshTestIntent), (New-EzDarkFactoryPortabilityIdentityTestIntent))) {
        $seed = New-EzDarkFactoryInstanceSeedData -Root $script:EzDarkFactoryRepositoryRoot -InstanceName $intent.name -Intent $intent -ControllerPublicKey 'ssh-ed25519 AAAA'
        Assert-EzDarkFactoryTrue -Condition ($seed.UserData -cnotmatch '(?m)^manual_cache_clean:') -Message 'Unsupported user-data keys cause cloud-init status 2 before identity initialization.'
        $policy = Get-EzDarkFactoryPortabilitySeedFile -UserData $seed.UserData -Path '/etc/cloud/cloud.cfg.d/99-ezdarkfactory-identity.cfg'
        Assert-EzDarkFactoryEqual -Actual $policy -Expected "manual_cache_clean: false`n"
        if ($intent.schemaVersion -eq 2) {
            $finalizer = Get-EzDarkFactoryPortabilitySeedFile -UserData $seed.UserData -Path '/usr/local/sbin/ezdarkfactory-instance-finalize'
            Assert-EzDarkFactoryTrue -Condition ($finalizer.Contains('EDF_GUEST_CLOUD_INIT_EXIT=%s') -and $finalizer.Contains('EDF_GUEST_FINALIZE_FAILED=stage=%s;exit=%s'))
            Assert-EzDarkFactoryTrue -Condition ($finalizer.IndexOf('stage=cloud-init') -lt $finalizer.IndexOf('cloud-init status --wait'))
            Assert-EzDarkFactoryTrue -Condition ($finalizer.IndexOf('stage=identity') -lt $finalizer.IndexOf('/usr/local/sbin/ezdarkfactory-instance-identity'))
            Assert-EzDarkFactoryTrue -Condition ($finalizer.IndexOf('stage=reboot') -lt $finalizer.IndexOf('systemctl reboot'))
            Assert-EzDarkFactoryTrue -Condition (-not $finalizer.Contains('cat /var/log/ezdarkfactory-cloud-init-status.log')) -Message 'Diagnostics must not dump cloud-init output or user-data.'
            $unit = Get-EzDarkFactoryPortabilitySeedFile -UserData $seed.UserData -Path '/etc/systemd/system/ezdarkfactory-instance-finalize.service'
            Assert-EzDarkFactoryTrue -Condition ($unit.Contains('StandardOutput=journal+console') -and $unit.Contains('StandardError=journal+console'))
        }
    }
}

Add-EzDarkFactoryTest -Name 'Portability identity: source relocation preserves seed identity and persistent first-boot finalization' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'identity relocated root [spaces]'
    try {
        $intent = New-EzDarkFactoryPortabilityIdentityTestIntent
        $original = New-EzDarkFactoryInstanceSeedData -Root $script:EzDarkFactoryRepositoryRoot -InstanceName $intent.name -Intent $intent -ControllerPublicKey 'ssh-ed25519 AAAA omitted-comment'
        $moved = New-EzDarkFactoryInstanceSeedData -Root $root -InstanceName $intent.name -Intent $intent -ControllerPublicKey 'ssh-ed25519 AAAA omitted-comment'
        Assert-EzDarkFactoryEqual -Actual $moved.UserData -Expected $original.UserData
        Assert-EzDarkFactoryEqual -Actual $moved.MetaData -Expected $original.MetaData
        Assert-EzDarkFactoryTrue -Condition ($moved.UserData.Contains('ssh_deletekeys: true'))
        Assert-EzDarkFactoryTrue -Condition ($moved.UserData.Contains('systemctl, start, --no-block, ezdarkfactory-instance-finalize.service'))
        $unit = Get-EzDarkFactoryPortabilitySeedFile -UserData $moved.UserData -Path '/etc/systemd/system/ezdarkfactory-instance-finalize.service'
        Assert-EzDarkFactoryTrue -Condition ($unit.Contains('After=cloud-final.service') -and $unit.Contains('Wants=cloud-final.service'))
        Assert-EzDarkFactoryTrue -Condition ($unit -cmatch '(?m)^Type=oneshot$' -and $unit -cmatch '(?m)^RemainAfterExit=yes$') -Message 'Successful current-boot completion must remain observable and repeated start requests must not rerun the finalizer.'
        # cloud-init 26.1 cloud-final.service is After=multi-user.target.
        # Target Wants adds an implicit After edge to its member: installing
        # finalization under multi-user would close a cycle on every reboot.
        Assert-EzDarkFactoryTrue -Condition ($unit -cmatch '(?m)^WantedBy=cloud-init\.target$')
        Assert-EzDarkFactoryTrue -Condition ($unit -cnotmatch '(?m)^(After|Before|WantedBy|RequiredBy)=.*multi-user\.target')
        Assert-EzDarkFactoryTrue -Condition ($unit -cnotmatch '(?m)^After=.*cloud-init\.target') -Message 'A member of cloud-init.target must not wait for that target itself.'
        $finalizer = Get-EzDarkFactoryPortabilitySeedFile -UserData $moved.UserData -Path '/usr/local/sbin/ezdarkfactory-instance-finalize'
        Assert-EzDarkFactoryTrue -Condition ($finalizer.IndexOf('systemctl reboot') -lt $finalizer.IndexOf('ezdarkfactory-coding-profile provision'))
        Assert-EzDarkFactoryTrue -Condition ($finalizer.Contains('cloud-init status --wait'))
        $initializer = Get-EzDarkFactoryPortabilitySeedFile -UserData $moved.UserData -Path '/usr/local/sbin/ezdarkfactory-instance-identity'
        $config64 = [regex]::Match($initializer, "base64.b64decode\('(?<data>[A-Za-z0-9+/=]+)'\)").Groups['data'].Value
        $config = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($config64)) | ConvertFrom-Json
        Assert-EzDarkFactoryEqual -Actual $config.cloudInstanceId -Expected $moved.CloudInstanceId
        Assert-EzDarkFactoryEqual -Actual $config.controllerPublicKey -Expected 'ssh-ed25519 AAAA'
        Assert-EzDarkFactoryEqual -Actual $config.machineId -Expected $config.machineUuid.Replace('-', '')
        Assert-EzDarkFactoryTrue -Condition ($initializer.IndexOf('hardware_uuid !=') -lt $initializer.IndexOf('private_bytes =')) -Message 'Copied finalizer must check destination hardware before identity mutation.'
        Assert-EzDarkFactoryTrue -Condition (-not $moved.UserData.Contains([string][char]13))
        Assert-EzDarkFactoryTrue -Condition (-not $initializer.Contains('omitted-comment'))
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Portability identity: generation-aware QEMU and NoCloud agree and legacy no-reboot remains compatible' -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'identity argv'
    try {
        foreach ($intent in @((New-EzDarkFactorySshTestIntent), (New-EzDarkFactoryPortabilityIdentityTestIntent))) {
            $argv = New-EzDarkFactoryRuntimeQemuArguments -InstanceName $intent.name -Intent $intent -Disk (Join-Path $root 'disk.qcow2') -FirmwareCode (Join-Path $root 'code.fd') -FirmwareVariables (Join-Path $root 'vars.fd') -SerialLog (Join-Path $root 'serial.log') -QemuLog (Join-Path $root 'qemu.log') -QmpPort 32001 -Accelerator tcg -SshPort 22001 -SeedHostPort 43001
            $uuidIndex = [Array]::IndexOf($argv, '-uuid')
            if ($intent.schemaVersion -eq 2) {
                $module = Get-Module EzDarkFactory
                $uuid = & $module { param($i) Get-EzDarkFactoryGuestMachineUuid -Intent $i } $intent
                Assert-EzDarkFactoryTrue -Condition ($uuidIndex -ge 0)
                Assert-EzDarkFactoryEqual -Actual $argv[$uuidIndex + 1] -Expected $uuid
                Assert-EzDarkFactoryTrue -Condition ($argv -notcontains '-no-reboot')
                $smbios = $argv[[Array]::IndexOf($argv, '-smbios') + 1]
                Assert-EzDarkFactoryTrue -Condition ($smbios.Contains('i=' + (Get-EzDarkFactorySshTestCloudId -Intent $intent) + ';'))
            }
            else {
                Assert-EzDarkFactoryEqual -Actual $uuidIndex -Expected -1
                Assert-EzDarkFactoryTrue -Condition ($argv -contains '-no-reboot')
            }
        }
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Portability identity: copied complete source identity remains a strict readiness rejection' -ScriptBlock {
    $source = New-EzDarkFactoryPortabilityIdentityTestIntent
    $destination = New-EzDarkFactoryPortabilityIdentityTestIntent -Generation ('c' * 32)
    $copied = New-EzDarkFactorySshTestProbe -IdentityBase64 (ConvertTo-EzDarkFactorySshTestBase64 (New-EzDarkFactorySshTestIdentityJson -Intent $source))
    Assert-EzDarkFactoryThrows -ScriptBlock {
        ConvertFrom-EzDarkFactoryCodingTestProbe -StdOut $copied -Intent $destination
    } -MessagePattern 'identity mismatch.*cloudInstanceId' | Out-Null
}

Add-EzDarkFactoryTest -Name 'Portability identity: pending initialization cannot preserve cached READY or promote copied host trust' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'identity pending'
    try {
        $intent = New-EzDarkFactoryPortabilityIdentityTestIntent
        $pending = [pscustomobject]@{ ExitCode = 75; StdOut = 'EDF_GUEST_IDENTITY_PENDING=' + (Get-EzDarkFactorySshTestCloudId -Intent $intent); StdErr = '' }
        $observed = Invoke-EzDarkFactoryPortabilityIdentityWaitFixture -Root $root -Intent $intent -Outputs @($pending)
        Assert-EzDarkFactoryTrue -Condition ($observed.Error -match 'did not reach authenticated SSH READY.*destination guest identity initialization is pending')
        Assert-EzDarkFactoryEqual -Actual $observed.PrematurePromotion -Expected $false
        Assert-EzDarkFactoryEqual -Actual $observed.StrictBypass -Expected $false
        Assert-EzDarkFactoryTrue -Condition ($observed.Calls -gt 0)
        $paths = Get-EzDarkFactorySshPaths -Root $root -InstanceName $intent.name
        $access = Read-EzDarkFactoryJson -Path $paths.AccessState -SchemaVersion 2
        Assert-EzDarkFactoryEqual -Actual $access.state -Expected 'PROVISIONING'
        Assert-EzDarkFactoryEqual -Actual $access.readyAt -Expected ''
        Assert-EzDarkFactoryTrue -Condition ([IO.File]::ReadAllText($paths.InstanceKnownHosts).Contains('ssh-ed25519 AAAA'))
        Assert-EzDarkFactoryEqual -Actual (@(Get-ChildItem -LiteralPath $paths.KnownHostsDirectory -Force -File | Where-Object { $_.Name.EndsWith('.candidate') }).Count) -Expected 0
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Portability identity: pending source key and reboot transport rotate only unpromoted candidates before full proof' -ScriptBlock {
    foreach ($firstExit in @(75, 255, -1)) {
        $root = New-EzDarkFactoryCheckoutFixture -Prefix ('identity key transition ' + $firstExit)
        try {
            $intent = New-EzDarkFactoryPortabilityIdentityTestIntent
            $pendingText = if ($firstExit -eq 75) { 'EDF_GUEST_IDENTITY_PENDING=' + (Get-EzDarkFactorySshTestCloudId -Intent $intent) } else { '' }
            $first = [pscustomobject]@{ ExitCode = $firstExit; StdOut = $pendingText; StdErr = 'transient bootstrap' }
            $proof = New-EzDarkFactorySshTestProbe -IdentityBase64 (ConvertTo-EzDarkFactorySshTestBase64 (New-EzDarkFactorySshTestIdentityJson -Intent $intent))
            $second = [pscustomobject]@{ ExitCode = 0; StdOut = $proof; StdErr = '' }
            $observed = Invoke-EzDarkFactoryPortabilityIdentityWaitFixture -Root $root -Intent $intent -Outputs @($first, $second)
            Assert-EzDarkFactoryEqual -Actual $observed.Error -Expected ''
            Assert-EzDarkFactoryEqual -Actual $observed.Ready.state -Expected 'READY'
            Assert-EzDarkFactoryEqual -Actual $observed.Scans -Expected 2
            Assert-EzDarkFactoryEqual -Actual $observed.PrematurePromotion -Expected $false
            Assert-EzDarkFactoryEqual -Actual $observed.StrictBypass -Expected $false
            Assert-EzDarkFactoryTrue -Condition ([IO.File]::ReadAllText((Get-EzDarkFactorySshPaths -Root $root -InstanceName $intent.name).InstanceKnownHosts).Contains('ssh-ed25519 CCCC'))
        }
        finally { Remove-EzDarkFactoryTestDirectory -Path $root }
    }
}

Add-EzDarkFactoryTest -Name 'Portability identity: persistent Windows SSH disconnects expire without promoting READY or trust' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'identity Windows disconnect'
    try {
        $intent = New-EzDarkFactoryPortabilityIdentityTestIntent
        # Even copied proof bytes are unusable when the client did not receive
        # successful remote exit status before the channel closed.
        $copiedProof = New-EzDarkFactorySshTestProbe -IdentityBase64 (ConvertTo-EzDarkFactorySshTestBase64 (New-EzDarkFactorySshTestIdentityJson -Intent $intent))
        $disconnect = [pscustomobject]@{ ExitCode = -1; StdOut = $copiedProof; StdErr = 'Connection to 127.0.0.1 closed by remote host.' }
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $observed = Invoke-EzDarkFactoryPortabilityIdentityWaitFixture -Root $root -Intent $intent -Outputs @($disconnect)
        $clock.Stop()
        Assert-EzDarkFactoryTrue -Condition ($observed.Error -match 'did not reach authenticated SSH READY within 2 seconds.*SSH authentication/transport is not ready.*closed by remote host')
        Assert-EzDarkFactoryTrue -Condition ($clock.Elapsed.TotalSeconds -lt 5) -Message 'Repeated disconnects must remain inside the existing bounded readiness wait.'
        Assert-EzDarkFactoryTrue -Condition ($observed.Calls -gt 1)
        # The loop may allocate one final candidate before observing that less
        # than one second remains for another probe; it must never reuse one.
        Assert-EzDarkFactoryTrue -Condition ($observed.Scans -ge $observed.Calls -and $observed.Scans -le ($observed.Calls + 1)) -Message 'Each disconnected attempt must discard its unpromoted candidate.'
        Assert-EzDarkFactoryEqual -Actual $observed.Ready -Expected $null
        Assert-EzDarkFactoryEqual -Actual $observed.PrematurePromotion -Expected $false
        Assert-EzDarkFactoryEqual -Actual $observed.StrictBypass -Expected $false
        $paths = Get-EzDarkFactorySshPaths -Root $root -InstanceName $intent.name
        $access = Read-EzDarkFactoryJson -Path $paths.AccessState -SchemaVersion 2
        Assert-EzDarkFactoryEqual -Actual $access.state -Expected 'PROVISIONING'
        Assert-EzDarkFactoryEqual -Actual $access.readyAt -Expected ''
        Assert-EzDarkFactoryEqual -Actual ([IO.File]::ReadAllText($paths.InstanceKnownHosts)) -Expected ('[127.0.0.1]:22001 ssh-ed25519 AAAA' + [Environment]::NewLine)
        Assert-EzDarkFactoryEqual -Actual (@(Get-ChildItem -LiteralPath $paths.KnownHostsDirectory -Force -File | Where-Object { $_.Name.EndsWith('.candidate') }).Count) -Expected 0
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Portability identity: nontransport SSH exit codes remain fatal despite complete proof bytes' -ScriptBlock {
    foreach ($exitCode in @(1, 70, 254, -2)) {
        $root = New-EzDarkFactoryCheckoutFixture -Prefix ('identity fatal SSH exit ' + $exitCode)
        try {
            $intent = New-EzDarkFactoryPortabilityIdentityTestIntent
            $proof = New-EzDarkFactorySshTestProbe -IdentityBase64 (ConvertTo-EzDarkFactorySshTestBase64 (New-EzDarkFactorySshTestIdentityJson -Intent $intent))
            $failure = [pscustomobject]@{ ExitCode = $exitCode; StdOut = $proof; StdErr = 'probe failed' }
            $observed = Invoke-EzDarkFactoryPortabilityIdentityWaitFixture -Root $root -Intent $intent -Outputs @($failure)
            Assert-EzDarkFactoryTrue -Condition ($observed.Error -match ('exited unexpectedly with code ' + [regex]::Escape([string]$exitCode)))
            Assert-EzDarkFactoryEqual -Actual $observed.Calls -Expected 1
            Assert-EzDarkFactoryEqual -Actual $observed.Ready -Expected $null
            Assert-EzDarkFactoryEqual -Actual $observed.PrematurePromotion -Expected $false
            Assert-EzDarkFactoryEqual -Actual $observed.StrictBypass -Expected $false
            $paths = Get-EzDarkFactorySshPaths -Root $root -InstanceName $intent.name
            Assert-EzDarkFactoryEqual -Actual (Read-EzDarkFactoryJson -Path $paths.AccessState -SchemaVersion 2).state -Expected 'PROVISIONING'
            Assert-EzDarkFactoryEqual -Actual ([IO.File]::ReadAllText($paths.InstanceKnownHosts)) -Expected ('[127.0.0.1]:22001 ssh-ed25519 AAAA' + [Environment]::NewLine)
            Assert-EzDarkFactoryEqual -Actual (@(Get-ChildItem -LiteralPath $paths.KnownHostsDirectory -Force -File | Where-Object { $_.Name.EndsWith('.candidate') }).Count) -Expected 0
        }
        finally { Remove-EzDarkFactoryTestDirectory -Path $root }
    }
}

Add-EzDarkFactoryTest -Name 'Portability identity: malformed or wrong-generation pending token cannot bypass strict evidence' -ScriptBlock {
    $intent = New-EzDarkFactoryPortabilityIdentityTestIntent
    $token = 'EDF_GUEST_IDENTITY_PENDING=' + (Get-EzDarkFactorySshTestCloudId -Intent $intent)
    foreach ($case in @(
        [pscustomobject]@{ ExitCode = 75; StdOut = 'EDF_GUEST_IDENTITY_PENDING=source'; StdErr = '' },
        [pscustomobject]@{ ExitCode = 75; StdOut = ($token + "`nEDF_PROFILE_CHECK=pass"); StdErr = '' },
        [pscustomobject]@{ ExitCode = 0; StdOut = $token; StdErr = '' }
    )) {
        $root = New-EzDarkFactoryCheckoutFixture -Prefix 'bad identity pending'
        try {
            $observed = Invoke-EzDarkFactoryPortabilityIdentityWaitFixture -Root $root -Intent $intent -Outputs @($case)
            Assert-EzDarkFactoryTrue -Condition ($observed.Error -match 'exited unexpectedly|unexpected or duplicate readiness protocol')
            Assert-EzDarkFactoryEqual -Actual $observed.Calls -Expected 1
            Assert-EzDarkFactoryEqual -Actual $observed.PrematurePromotion -Expected $false
            Assert-EzDarkFactoryTrue -Condition ([IO.File]::ReadAllText((Get-EzDarkFactorySshPaths -Root $root -InstanceName $intent.name).InstanceKnownHosts).Contains('ssh-ed25519 AAAA'))
        }
        finally { Remove-EzDarkFactoryTestDirectory -Path $root }
    }
}

Add-EzDarkFactoryTest -Name 'Portability identity: initialized destination still rejects wrong identity and live profile failures' -ScriptBlock {
    $intent = New-EzDarkFactoryPortabilityIdentityTestIntent
    foreach ($kind in @('wrong-identity', 'missing-tool')) {
        $root = New-EzDarkFactoryCheckoutFixture -Prefix $kind
        try {
            $identity = New-EzDarkFactorySshTestIdentityJson -Intent $intent
            if ($kind -ceq 'wrong-identity') {
                $document = $identity | ConvertFrom-Json
                $document.instanceName = 'copied-source'
                $identity = $document | ConvertTo-Json -Compress
                $proof = New-EzDarkFactorySshTestProbe -IdentityBase64 (ConvertTo-EzDarkFactorySshTestBase64 $identity)
            }
            else { $proof = New-EzDarkFactorySshTestProbe -IdentityBase64 (ConvertTo-EzDarkFactorySshTestBase64 $identity) -ProfileCheck failed -ProfileError 'missing required command: rg' }
            $observed = Invoke-EzDarkFactoryPortabilityIdentityWaitFixture -Root $root -Intent $intent -Outputs @([pscustomobject]@{ ExitCode = 0; StdOut = $proof; StdErr = '' })
            Assert-EzDarkFactoryTrue -Condition ($observed.Error -match 'identity mismatch|missing required command: rg')
            Assert-EzDarkFactoryEqual -Actual $observed.Calls -Expected 1
            Assert-EzDarkFactoryEqual -Actual $observed.PrematurePromotion -Expected $false
        }
        finally { Remove-EzDarkFactoryTestDirectory -Path $root }
    }
}

Add-EzDarkFactoryTest -Name 'Portability identity: host-generated gate precedes copied readiness and refuses unsafe expected identities' -ScriptBlock {
    $module = Get-Module EzDarkFactory
    $intent = New-EzDarkFactoryPortabilityIdentityTestIntent
    $remote = & $module {
        param($i)
        Get-EzDarkFactoryReadinessRemoteScript -ProvisioningDigest ('a' * 64) -ExpectedCloudInstanceId (Get-EzDarkFactoryGuestCloudInstanceId -Intent $i) -ExpectedMachineUuid (Get-EzDarkFactoryGuestMachineUuid -Intent $i)
    } $intent
    Assert-EzDarkFactoryTrue -Condition ($remote.IndexOf('guest-identity.json') -lt $remote.IndexOf('identity_b64='))
    Assert-EzDarkFactoryTrue -Condition ($remote.Contains('initializedBootId') -and $remote.Contains('product_uuid'))
    Assert-EzDarkFactoryTrue -Condition ($remote.Contains('exit 75') -and $remote.Contains('EDF_GUEST_IDENTITY_PENDING='))
    Assert-EzDarkFactoryTrue -Condition ($remote.IndexOf('ezdarkfactory_boot_proof="$(ezdarkfactory_guest_boot_gate)"') -lt $remote.IndexOf('ready_b64='))
    Assert-EzDarkFactoryTrue -Condition ($remote.IndexOf('ezdarkfactory_boot_proof_after="$(ezdarkfactory_guest_boot_gate)"') -gt $remote.IndexOf('/usr/local/sbin/ezdarkfactory-coding-profile validate'))
    Assert-EzDarkFactoryTrue -Condition ($remote.IndexOf('ezdarkfactory_boot_proof_after="$(ezdarkfactory_guest_boot_gate)"') -lt $remote.IndexOf("printf 'EDF_IDENTITY_B64="))
    Assert-EzDarkFactoryTrue -Condition ($remote.Contains('test "$ezdarkfactory_boot_proof_after" != "$ezdarkfactory_boot_proof"')) -Message 'A restarted finalizer or changed readiness file must invalidate captured proof.'
    Assert-EzDarkFactoryThrows -ScriptBlock {
        & $module { Get-EzDarkFactoryReadinessRemoteScript -ProvisioningDigest ('a' * 64) -ExpectedCloudInstanceId 'x;reboot' -ExpectedMachineUuid ('a' * 32) }
    } -MessagePattern 'requires the exact destination' | Out-Null
}

$bootGatePython = @(Get-Command -Name 'python', 'python3' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
$bootGateSkip = if ($bootGatePython.Count -eq 0) { 'Python 3 is unavailable; executable generated-guest-gate regression requires the guest scripting language.' } else { '' }
$bootGatePythonPath = if ($bootGatePython.Count -eq 0) { '' } else { $bootGatePython[0].Source }
Add-EzDarkFactoryTest -Name 'Portability identity: executable gate requires current-boot finalizer completion and binds revalidation to its invocation and ready bytes' -Data $bootGatePythonPath -SkipReason $bootGateSkip -ScriptBlock {
    param($pythonPath)
    $root = New-EzDarkFactoryTestDirectory -Prefix 'current boot gate'
    try {
        $intent = New-EzDarkFactoryPortabilityIdentityTestIntent
        $module = Get-Module EzDarkFactory
        $remote = & $module {
            param($i)
            Get-EzDarkFactoryReadinessRemoteScript -ProvisioningDigest ('a' * 64) -ExpectedCloudInstanceId (Get-EzDarkFactoryGuestCloudInstanceId -Intent $i) -ExpectedMachineUuid (Get-EzDarkFactoryGuestMachineUuid -Intent $i)
        } $intent
        $encoding = New-Object Text.UTF8Encoding($false)
        $remotePath = Join-Path $root 'generated remote.sh'
        $identityPath = Join-Path $root 'identity.json'
        $fixturePath = Join-Path $root 'exercise gate.py'
        [IO.File]::WriteAllText($remotePath, $remote, $encoding)
        [IO.File]::WriteAllText($identityPath, (New-EzDarkFactorySshTestIdentityJson -Intent $intent), $encoding)
        $fixture = @'
import ast, contextlib, copy, hashlib, io, json, shlex, subprocess, sys, types

tokens = shlex.split(open(sys.argv[1], encoding='utf-8').read())
python_index = tokens.index('python3')
assert tokens[python_index + 1] == '-c'
tree = ast.parse(tokens[python_index + 2])
assert isinstance(tree.body[-1], ast.Try)
definitions = compile(ast.Module(body=tree.body[:-1], type_ignores=[]), '<generated gate definitions>', 'exec')
decision = compile(ast.Module(body=tree.body[-1:], type_ignores=[]), '<generated gate decision>', 'exec')
identity = json.load(open(sys.argv[2], encoding='utf-8'))
ready = (json.dumps(dict(identity, provisioningState='complete')) + '\n').encode()
boot = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
old_boot = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
complete = dict(LoadState='loaded', ActiveState='active', SubState='exited', Result='success',
                ExecMainCode='1', ExecMainStatus='0', ExecMainStartTimestampMonotonic='123456',
                InvocationID='c' * 32)

def run(status=None, returncode=0, missing_ready=False, ready_bytes=ready,
        duplicate=False, timeout=False, initialized_boot=old_boot, current_boot=boot,
        wrong_hardware=False):
    namespace = {}
    exec(definitions, namespace)
    expected = namespace['expected']
    public = b'ssh-ed25519 AAAA fixture\n'
    marker = dict(schemaVersion=1, cloudInstanceId=expected['cloudInstanceId'],
                  machineUuid=expected['machineUuid'], machineId=expected['machineId'],
                  initializedBootId=initialized_boot, sshHostKeySha256=hashlib.sha256(public).hexdigest(),
                  controllerPublicKeySha256='d' * 64)
    files = {'/var/lib/ezdarkfactory/guest-identity.json': json.dumps(marker).encode(),
             '/etc/ezdarkfactory/identity.json': json.dumps(identity).encode(),
             '/etc/machine-id': expected['machineId'].encode(),
             '/var/lib/dbus/machine-id': expected['machineId'].encode(),
             '/etc/ssh/ssh_host_ed25519_key.pub': public}
    if not missing_ready:
        files['/var/lib/ezdarkfactory/ready.json'] = ready_bytes
    observed = dict(queries=0, ready_reads=0)
    def read_regular(path):
        if path.endswith('/ready.json'):
            observed['ready_reads'] += 1
        if path not in files:
            raise FileNotFoundError(path)
        return files[path]
    def open_kernel(path, **kwargs):
        if path == '/sys/class/dmi/id/product_uuid':
            return io.StringIO('wrong' if wrong_hardware else expected['machineUuid'])
        assert path == '/proc/sys/kernel/random/boot_id', path
        return io.StringIO(current_boot)
    def query(arguments, **kwargs):
        observed['queries'] += 1
        assert arguments[:4] == ['/usr/bin/systemctl', 'show', '--no-pager', '--all']
        assert arguments[-1] == 'ezdarkfactory-instance-finalize.service'
        assert kwargs['timeout'] == 5 and kwargs['check'] is False
        if timeout:
            raise subprocess.TimeoutExpired(arguments, 5)
        values = complete if status is None else status
        output = ''.join(key + '=' + value + '\n' for key, value in reversed(list(values.items())))
        if duplicate:
            output += 'Result=success\n'
        return types.SimpleNamespace(returncode=returncode, stdout=output)
    # Replace only guest I/O boundaries. Execute the generated parsing and
    # decision code unchanged, with correctly matching prior-boot ready bytes.
    namespace.update(read_regular=read_regular, open=open_kernel,
                     os=types.SimpleNamespace(path=types.SimpleNamespace(islink=lambda path: False)),
                     subprocess=types.SimpleNamespace(run=query, PIPE=subprocess.PIPE,
                                                      DEVNULL=subprocess.DEVNULL,
                                                      TimeoutExpired=subprocess.TimeoutExpired))
    output, error = io.StringIO(), io.StringIO()
    result = 0
    with contextlib.redirect_stdout(output), contextlib.redirect_stderr(error):
        try:
            exec(decision, namespace)
        except SystemExit as stopped:
            result = stopped.code
    return result, output.getvalue().strip(), error.getvalue(), observed

for active, sub in [('inactive', 'dead'), ('activating', 'start'), ('active', 'running')]:
    result = run(dict(complete, ActiveState=active, SubState=sub))
    assert result[0] == 75 and result[1] == '' and result[3]['ready_reads'] == 0, result
never_started = dict(complete, ActiveState='inactive', SubState='dead', ExecMainCode='0',
                     ExecMainStartTimestampMonotonic='0', InvocationID='')
assert run(never_started)[0] == 75
assert run({'LoadState': 'not-found'}, returncode=4)[0] == 75
assert run(timeout=True)[0] == 75
assert run(missing_ready=True)[0] == 75
assert run(initialized_boot=boot)[0] == 75  # Required identity reboot still wins.
assert run(initialized_boot=boot)[3]['queries'] == 0
assert run(wrong_hardware=True)[0] == 70
assert run(wrong_hardware=True)[3]['queries'] == 0

for changes in [dict(ActiveState='failed', Result='exit-code'), dict(Result='timeout'),
                dict(ExecMainStatus='1'), dict(ExecMainCode='2'),
                dict(ExecMainStartTimestampMonotonic='0'), dict(InvocationID='0' * 32)]:
    result = run(dict(complete, **changes))
    assert result[0] == 70 and result[1] == '', result
assert run(dict(complete, Unexpected='value'))[0] == 70
missing = dict(complete)
del missing['InvocationID']
assert run(missing)[0] == 70
assert run(duplicate=True)[0] == 70
assert run(returncode=1)[0] == 70

fresh = run()
assert fresh[0] == 0 and fresh[1] == boot + ':' + 'c' * 32 + ':' + hashlib.sha256(ready).hexdigest(), fresh
assert run()[1] == fresh[1]
# Revalidation must expose restart, file replacement and boot transitions;
# the generated shell compares this fingerprint before printing proof bytes.
assert run(dict(complete, InvocationID='e' * 32))[1] != fresh[1]
assert run(ready_bytes=ready + b' ')[1] != fresh[1]
assert run(current_boot='ffffffff-ffff-ffff-ffff-ffffffffffff')[1] != fresh[1]
print('PASS generated gate: prior READY blocked; completed current boot accepted; restart/failure/change invalidated.')
'@
        [IO.File]::WriteAllText($fixturePath, $fixture, $encoding)
        $result = Invoke-EzDarkFactoryProcess -FilePath $pythonPath -ArgumentList @($fixturePath, $remotePath, $identityPath) -WorkingDirectory $root -TimeoutSeconds 15
        Assert-EzDarkFactoryEqual -Actual $result.ExitCode -Expected 0 -Message $result.StdErr
        Assert-EzDarkFactoryTrue -Condition ($result.StdOut.Contains('PASS generated gate:'))
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Portability identity: SSH allocation refuses a redirected lock directory before creating outside state' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'ssh lock redirection'
    $outside = New-EzDarkFactoryTestDirectory -Prefix 'ssh lock outside'
    $link = $null
    try {
        $paths = Get-EzDarkFactoryPaths -Root $root
        [void][IO.Directory]::CreateDirectory($paths.Runtime)
        $link = $paths.Locks
        $linkType = if ($script:EzDarkFactoryIsWindowsHost) { 'Junction' } else { 'SymbolicLink' }
        $null = New-Item -ItemType $linkType -Path $link -Target $outside -ErrorAction Stop
        $module = Get-Module EzDarkFactory
        Assert-EzDarkFactoryThrows -ScriptBlock {
            & $module { param($r) $lock = Enter-EzDarkFactorySshAllocationLock -Root $r; $lock.Dispose() } $root
        } -MessagePattern 'reparse point' | Out-Null
        Assert-EzDarkFactoryEqual -Actual (@(Get-ChildItem -LiteralPath $outside -Force).Count) -Expected 0
    }
    finally {
        if ($null -ne $link -and (Test-Path -LiteralPath $link)) { [IO.Directory]::Delete($link) }
        Remove-EzDarkFactoryTestDirectory -Path $root
        Remove-EzDarkFactoryTestDirectory -Path $outside
    }
}
