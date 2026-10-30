function ConvertFrom-EzDarkFactoryCodingTestProbe {
    param([string]$StdOut, [object]$Intent = (New-EzDarkFactorySshTestIntent))
    $profile = Get-EzDarkFactoryCodingProfile -Root $script:EzDarkFactoryRepositoryRoot
    return ConvertFrom-EzDarkFactoryReadinessProbe -StdOut $StdOut -ExpectedInstanceName $Intent.name -ExpectedBaseId $Intent.baseId -ExpectedProfile $Intent.profile -ExpectedCloudInstanceId (Get-EzDarkFactorySshTestCloudId -Intent $Intent) -ExpectedProvisioningProfile $profile.Name -ExpectedProvisioningVersion $profile.Version -ExpectedProvisioningDigest $profile.Digest
}

function Set-EzDarkFactoryCodingTestProbeField {
    param([string]$Probe, [string]$Field, [AllowEmptyString()][string]$Value)
    $lines = @($Probe -split '\r?\n' | ForEach-Object {
        if ($_.StartsWith(($Field + '='), [StringComparison]::Ordinal)) { $Field + '=' + $Value }
        else { $_ }
    })
    return [string]::Join([Environment]::NewLine, $lines)
}

Add-EzDarkFactoryTest -Name 'Coding readiness: seed separates resource and coding identities and configures locked coder workspace policy' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'coding seed [spaces]'
    try {
        $intent = New-EzDarkFactorySshTestIntent -Cpus 2 -MemoryMiB 4096
        $seed = New-EzDarkFactoryInstanceSeedData -Root $root -Intent $intent -InstanceName $intent.name -ControllerPublicKey 'ssh-ed25519 AAAA do-not-copy-this-comment'
        Assert-EzDarkFactoryEqual -Actual $seed.Identity.schemaVersion -Expected 2
        Assert-EzDarkFactoryEqual -Actual $seed.Identity.profile -Expected 'light'
        Assert-EzDarkFactoryEqual -Actual $seed.Identity.provisioningProfile -Expected 'coding-default'
        Assert-EzDarkFactoryEqual -Actual $seed.Identity.provisioningVersion -Expected 1
        Assert-EzDarkFactoryEqual -Actual $seed.Identity.provisioningDigest -Expected (Get-EzDarkFactoryCodingProfile -Root $root).Digest
        foreach ($content in @('homedir: /home/coder', 'lock_passwd: true', 'ssh_pwauth: false', 'disable_root: true', 'ALL=(ALL:ALL) NOPASSWD:ALL', 'PasswordAuthentication no', 'KbdInteractiveAuthentication no', 'PermitRootLogin no')) {
            Assert-EzDarkFactoryTrue -Condition ($seed.UserData.Contains($content)) -Message "Missing coder policy: $content"
        }
        Assert-EzDarkFactoryTrue -Condition ($seed.UserData.Contains('/etc/ezdarkfactory/profile.json') -and $seed.UserData.Contains('/usr/local/sbin/ezdarkfactory-coding-profile'))
        Assert-EzDarkFactoryTrue -Condition ($seed.UserData.Contains('systemctl reload ssh')) -Message 'Effective SSH policy must be activated before completion.'
        Assert-EzDarkFactoryTrue -Condition ($seed.UserData.Contains('systemd-run, --no-block')) -Message 'Finalization must not deadlock cloud-init completion.'
        Assert-EzDarkFactoryTrue -Condition (-not $seed.UserData.Contains('do-not-copy-this-comment')) -Message 'Public-key comments must not enter guest seed.'
        Assert-EzDarkFactoryTrue -Condition (-not $seed.UserData.Contains([string][char]13)) -Message 'Guest seed must use Unix newlines on Windows too.'
        Assert-EzDarkFactoryTrue -Condition ($seed.UserData -notmatch '(?im)^packages:|^package_upgrade:|curl.+\|\s*(sh|bash)') -Message 'Instance startup must validate the baseline without unreviewed package installation.'
        Assert-EzDarkFactoryThrows -ScriptBlock {
            New-EzDarkFactoryInstanceSeedData -Root $root -Intent $intent -InstanceName $intent.name -ControllerPublicKey 'ssh-ed25519 AAAA' -Profile heavy
        } -MessagePattern 'resource profile.*does not match durable intent' | Out-Null
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Coding readiness: legacy intent remains readable but start refuses before key generation or guest mutation' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'legacy coding refusal'
    try {
        $intent = New-EzDarkFactorySshTestIntent
        $intent.provisioningProfile = 'ezdarkfactory-core'
        $paths = Get-EzDarkFactoryInstanceRuntimePaths -Root $root -InstanceName $intent.name
        [void][IO.Directory]::CreateDirectory($paths.Directory)
        Write-EzDarkFactoryJson -Path $paths.Intent -Value $intent
        $before = [IO.File]::ReadAllText($paths.Intent)
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryInstanceIntent -Root $root -InstanceName $intent.name).provisioningProfile -Expected 'ezdarkfactory-core'
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Start-EzDarkFactoryReadyInstance -Root $root -InstanceName $intent.name
        } -MessagePattern 'unsupported.*new named instance.*not silently upgraded' | Out-Null
        Assert-EzDarkFactoryEqual -Actual ([IO.File]::ReadAllText($paths.Intent)) -Expected $before
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath $paths.Runtime)) -Message 'Unsupported profile cannot launch a guest.'
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Get-EzDarkFactorySshPaths -Root $root).ControllerPrivateKey)) -Message 'Unsupported profile must be refused before controller-key creation.'
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Coding readiness: complete versioned identity plus live proof grants READY' -ScriptBlock {
    $intent = New-EzDarkFactorySshTestIntent
    $identity = New-EzDarkFactorySshTestIdentityJson -Intent $intent
    $probe = New-EzDarkFactorySshTestProbe -IdentityBase64 (ConvertTo-EzDarkFactorySshTestBase64 $identity)
    $result = ConvertFrom-EzDarkFactoryCodingTestProbe -StdOut $probe -Intent $intent
    Assert-EzDarkFactoryEqual -Actual $result.Ready -Expected $true
    Assert-EzDarkFactoryEqual -Actual $result.ReadyMarker.provisioningState -Expected 'complete'
    Assert-EzDarkFactoryEqual -Actual $result.ProfileReady -Expected $true
    Assert-EzDarkFactoryEqual -Actual $result.Identity.provisioningVersion -Expected 1
}

Add-EzDarkFactoryTest -Name 'Coding readiness: each identity field in either identity or completion marker is compared with host intent' -ScriptBlock {
    $intent = New-EzDarkFactorySshTestIntent
    $identity = New-EzDarkFactorySshTestIdentityJson -Intent $intent
    $probe = New-EzDarkFactorySshTestProbe -IdentityBase64 (ConvertTo-EzDarkFactorySshTestBase64 $identity)
    $changes = @(
        @('instanceName', 'different-agent'), @('baseId', ('base-' + ('b' * 64))),
        @('profile', 'heavy'), @('cloudInstanceId', 'ezdarkfactory-other-123456789abc'),
        @('provisioningProfile', 'ezdarkfactory-core'), @('provisioningVersion', 2),
        @('provisioningDigest', ('0' * 64))
    )
    foreach ($field in @('EDF_IDENTITY_B64', 'EDF_READY_B64')) {
        foreach ($change in $changes) {
            $document = $identity | ConvertFrom-Json
            if ($field -ceq 'EDF_READY_B64') { $document | Add-Member -NotePropertyName provisioningState -NotePropertyValue 'complete' }
            $document.($change[0]) = $change[1]
            $changed = Set-EzDarkFactoryCodingTestProbeField -Probe $probe -Field $field -Value (ConvertTo-EzDarkFactorySshTestBase64 ($document | ConvertTo-Json -Compress))
            Assert-EzDarkFactoryThrows -ScriptBlock {
                ConvertFrom-EzDarkFactoryCodingTestProbe -StdOut $changed -Intent $intent
            } -MessagePattern 'identity mismatch' | Out-Null
        }
    }
}

Add-EzDarkFactoryTest -Name 'Coding readiness: malformed schemas, coerced versions and extra identity fields cannot pass' -ScriptBlock {
    $intent = New-EzDarkFactorySshTestIntent
    $identity = New-EzDarkFactorySshTestIdentityJson -Intent $intent
    $probe = New-EzDarkFactorySshTestProbe -IdentityBase64 (ConvertTo-EzDarkFactorySshTestBase64 $identity)
    foreach ($field in @('EDF_IDENTITY_B64', 'EDF_READY_B64')) {
        foreach ($change in @(@('schemaVersion', 1), @('schemaVersion', '2'), @('schemaVersion', $true), @('provisioningVersion', '1'), @('provisioningVersion', $true), @('provisioningVersion', 1.5), @('provisioningVersion', $null))) {
            $document = $identity | ConvertFrom-Json
            if ($field -ceq 'EDF_READY_B64') { $document | Add-Member -NotePropertyName provisioningState -NotePropertyValue 'complete' }
            $document.($change[0]) = $change[1]
            $changed = Set-EzDarkFactoryCodingTestProbeField -Probe $probe -Field $field -Value (ConvertTo-EzDarkFactorySshTestBase64 ($document | ConvertTo-Json -Compress))
            Assert-EzDarkFactoryThrows -ScriptBlock { ConvertFrom-EzDarkFactoryCodingTestProbe -StdOut $changed } -MessagePattern 'schemaVersion|integer' | Out-Null
        }
        foreach ($kind in @('missing', 'extra')) {
            $document = $identity | ConvertFrom-Json
            if ($field -ceq 'EDF_READY_B64') { $document | Add-Member -NotePropertyName provisioningState -NotePropertyValue 'complete' }
            if ($kind -ceq 'missing') { $document.PSObject.Properties.Remove('provisioningDigest') }
            else { $document | Add-Member -NotePropertyName unexpected -NotePropertyValue 'ignored fields are not allowed' }
            $changed = Set-EzDarkFactoryCodingTestProbeField -Probe $probe -Field $field -Value (ConvertTo-EzDarkFactorySshTestBase64 ($document | ConvertTo-Json -Compress))
            Assert-EzDarkFactoryThrows -ScriptBlock { ConvertFrom-EzDarkFactoryCodingTestProbe -StdOut $changed } -MessagePattern 'missing required field|unknown field' | Out-Null
        }
    }
}

Add-EzDarkFactoryTest -Name 'Coding readiness: no identity, absent completion, pending profile and unfinished cloud-init never become READY' -ScriptBlock {
    $identity = New-EzDarkFactorySshTestIdentityJson -Intent (New-EzDarkFactorySshTestIntent)
    $probe = New-EzDarkFactorySshTestProbe -IdentityBase64 (ConvertTo-EzDarkFactorySshTestBase64 $identity)
    foreach ($change in @(
        @('EDF_IDENTITY_B64', ''), @('EDF_READY_B64', ''), @('EDF_PROFILE_CHECK', 'pending'),
        @('EDF_CLOUD_B64', (ConvertTo-EzDarkFactorySshTestBase64 'status: running'))
    )) {
        $changed = Set-EzDarkFactoryCodingTestProbeField -Probe $probe -Field $change[0] -Value $change[1]
        Assert-EzDarkFactoryEqual -Actual (ConvertFrom-EzDarkFactoryCodingTestProbe -StdOut $changed).Ready -Expected $false
    }
    $document = $identity | ConvertFrom-Json
    $document | Add-Member -NotePropertyName provisioningState -NotePropertyValue 'provisioning'
    $changed = Set-EzDarkFactoryCodingTestProbeField -Probe $probe -Field 'EDF_READY_B64' -Value (ConvertTo-EzDarkFactorySshTestBase64 ($document | ConvertTo-Json -Compress))
    Assert-EzDarkFactoryThrows -ScriptBlock { ConvertFrom-EzDarkFactoryCodingTestProbe -StdOut $changed } -MessagePattern 'does not record complete' | Out-Null
}

Add-EzDarkFactoryTest -Name 'Coding readiness: missing required tool and degraded cloud-init are hard failures despite old success markers' -ScriptBlock {
    $identity = New-EzDarkFactorySshTestIdentityJson -Intent (New-EzDarkFactorySshTestIntent)
    $encoded = ConvertTo-EzDarkFactorySshTestBase64 $identity
    $probe = New-EzDarkFactorySshTestProbe -IdentityBase64 $encoded -ProfileCheck failed -ProfileError 'missing required command: rg'
    Assert-EzDarkFactoryThrows -ScriptBlock { ConvertFrom-EzDarkFactoryCodingTestProbe -StdOut $probe } -MessagePattern 'Coding profile validation failed.*missing required command: rg' | Out-Null
    foreach ($exit in @('1', '2', '127', 'invalid')) {
        $probe = New-EzDarkFactorySshTestProbe -IdentityBase64 $encoded -CloudExit $exit
        Assert-EzDarkFactoryThrows -ScriptBlock { ConvertFrom-EzDarkFactoryCodingTestProbe -StdOut $probe } -MessagePattern 'cloud-init reports failed' | Out-Null
    }
}

Add-EzDarkFactoryTest -Name 'Coding readiness: malformed, duplicate, truncated and legacy probe records fail closed' -ScriptBlock {
    $identity = New-EzDarkFactorySshTestIdentityJson -Intent (New-EzDarkFactorySshTestIntent)
    $encoded = ConvertTo-EzDarkFactorySshTestBase64 $identity
    $probe = New-EzDarkFactorySshTestProbe -IdentityBase64 $encoded
    foreach ($bad in @(
        ($probe + 'EDF_PROFILE_CHECK=pass'),
        ($probe + 'UNEXPECTED=pass'),
        ($probe + 'unframed output'),
        (Set-EzDarkFactoryCodingTestProbeField -Probe $probe -Field 'EDF_IDENTITY_B64' -Value '%%%'),
        (Set-EzDarkFactoryCodingTestProbeField -Probe $probe -Field 'EDF_READY_B64' -Value '/w=='),
        (Set-EzDarkFactoryCodingTestProbeField -Probe $probe -Field 'EDF_READY_B64' -Value (ConvertTo-EzDarkFactorySshTestBase64 ('x' * 8193))),
        ('x' * 65537),
        ('EDF_IDENTITY_B64=' + $encoded + [Environment]::NewLine + 'EDF_READY=1')
    )) {
        Assert-EzDarkFactoryThrows -ScriptBlock { ConvertFrom-EzDarkFactoryCodingTestProbe -StdOut $bad } | Out-Null
    }
}

Add-EzDarkFactoryTest -Name 'Coding readiness: failed live proof clears cached host READY and preserves managed host-key trust' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'coding failed revalidation'
    try {
        $intent = New-EzDarkFactorySshTestIntent
        $access = New-EzDarkFactorySshTestAccess -Root $root -Intent $intent
        $launch = New-EzDarkFactorySshTestLaunch -Root $root -Intent $intent -Access $access
        $access.state = 'READY'
        $access.readyAt = [DateTime]::UtcNow.ToString('o')
        $paths = Get-EzDarkFactorySshPaths -Root $root -InstanceName $intent.name
        [void][IO.Directory]::CreateDirectory($paths.KnownHostsDirectory)
        $oldTrust = '[127.0.0.1]:22001 ssh-ed25519 AAAA' + [Environment]::NewLine
        [IO.File]::WriteAllText($paths.InstanceKnownHosts, $oldTrust)
        $probe = New-EzDarkFactorySshTestProbe -IdentityBase64 (ConvertTo-EzDarkFactorySshTestBase64 (New-EzDarkFactorySshTestIdentityJson -Intent $intent)) -ProfileCheck failed -ProfileError 'missing required command: rg'
        $module = Get-Module EzDarkFactory
        Assert-EzDarkFactoryThrows -ScriptBlock {
            & $module {
                param($r, $i, $a, $output, $processProvider)
                $runner = { param($exe, $arguments, $timeout) [pscustomobject]@{ ExitCode = 0; StdOut = $output; StdErr = '' } }.GetNewClosure()
                Wait-EzDarkFactorySshReady -Root $r -InstanceName $i.name -Intent $i -Access $a -Identity ([pscustomobject]@{PrivateKey = 'unused'}) -Tooling ([pscustomobject]@{Ssh = 'unused'}) -TimeoutSeconds 3 -PortProbe { $true } -HostKeyScanner { '[127.0.0.1]:22001 ssh-ed25519 BBBB' } -SshRunner $runner -ProcessProvider $processProvider
            } $root $intent $access $probe $launch.ProcessProvider
        } -MessagePattern 'Coding profile validation failed.*missing required command: rg' | Out-Null
        $after = Read-EzDarkFactoryJson -Path $paths.AccessState -SchemaVersion 2
        Assert-EzDarkFactoryEqual -Actual $after.state -Expected 'PROVISIONING'
        Assert-EzDarkFactoryEqual -Actual $after.readyAt -Expected ''
        Assert-EzDarkFactoryEqual -Actual ([IO.File]::ReadAllText($paths.InstanceKnownHosts)) -Expected $oldTrust
        Assert-EzDarkFactoryEqual -Actual @(Get-ChildItem -LiteralPath $paths.KnownHostsDirectory -Filter '*.candidate' -File -Force).Count -Expected 0
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Coding readiness: parent deadline prevents a fresh child budget from granting late READY or trust' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'coding late proof'
    try {
        $intent = New-EzDarkFactorySshTestIntent
        $access = New-EzDarkFactorySshTestAccess -Root $root -Intent $intent
        $launch = New-EzDarkFactorySshTestLaunch -Root $root -Intent $intent -Access $access
        $paths = Get-EzDarkFactorySshPaths -Root $root -InstanceName $intent.name
        $probe = New-EzDarkFactorySshTestProbe -IdentityBase64 (ConvertTo-EzDarkFactorySshTestBase64 (New-EzDarkFactorySshTestIdentityJson -Intent $intent))
        $module = Get-Module EzDarkFactory
        Assert-EzDarkFactoryThrows -ScriptBlock {
            & $module {
                param($r, $i, $a, $output, $processProvider)
                $runner = {
                    param($exe, $arguments, $timeout)
                    Start-Sleep -Milliseconds 2200
                    [pscustomobject]@{ ExitCode = 0; StdOut = $output; StdErr = '' }
                }.GetNewClosure()
                Wait-EzDarkFactorySshReady -Root $r -InstanceName $i.name -Intent $i -Access $a -Identity ([pscustomobject]@{PrivateKey = 'unused'}) -Tooling ([pscustomobject]@{Ssh = 'unused'}) -TimeoutSeconds 5 -DeadlineUtc ([DateTime]::UtcNow.AddSeconds(2)) -PortProbe { $true } -HostKeyScanner { '[127.0.0.1]:22001 ssh-ed25519 BBBB' } -SshRunner $runner -ProcessProvider $processProvider
            } $root $intent $access $probe $launch.ProcessProvider
        } -MessagePattern 'exceeded.*deadline' | Out-Null
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath $paths.InstanceKnownHosts)) -Message 'Late evidence must not become managed host-key trust.'
        Assert-EzDarkFactoryEqual -Actual (Read-EzDarkFactoryJson -Path $paths.AccessState -SchemaVersion 2).state -Expected 'PROVISIONING'
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Coding readiness: access schemas and profile versions reject coercion and mixed intent' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'coding access schemas'
    try {
        $intent = New-EzDarkFactorySshTestIntent
        $module = Get-Module EzDarkFactory
        foreach ($change in @(@('schemaVersion', 1), @('schemaVersion', '2'), @('provisioningVersion', $true), @('provisioningVersion', '1'), @('provisioningProfile', 'ezdarkfactory-core'), @('provisioningDigest', 'bad'))) {
            $access = New-EzDarkFactorySshTestAccess -Root $root -Intent $intent
            $access.($change[0]) = $change[1]
            Assert-EzDarkFactoryThrows -ScriptBlock {
                & $module { param($a) Assert-EzDarkFactorySshAccessState -Access $a -ExpectedName 'ssh-agent' } $access
            } | Out-Null
        }
        foreach ($change in @(@('baseId', ('base-' + ('b' * 64))), @('provisioningDigest', ('0' * 64)), @('cloudInstanceId', 'ezdarkfactory-different-123456789abc'))) {
            $access = New-EzDarkFactorySshTestAccess -Root $root -Intent $intent
            $access.($change[0]) = $change[1]
            Assert-EzDarkFactoryThrows -ScriptBlock {
                & $module {
                    param($r, $i, $a)
                    Wait-EzDarkFactorySshReady -Root $r -InstanceName $i.name -Intent $i -Access $a -Identity ([pscustomobject]@{PrivateKey='unused'}) -Tooling ([pscustomobject]@{Ssh='unused'}) -TimeoutSeconds 2
                } $root $intent $access
            } -MessagePattern 'does not match the requested instance and coding profile' | Out-Null
        }
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}
