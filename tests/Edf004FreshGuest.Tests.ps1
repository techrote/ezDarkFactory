# EDF-004 fresh-project source/generation contract tests.

function New-EzDarkFactoryEdf004Fixture {
    $fixture = New-EzDarkFactoryBaseBuildFixture
    $base = Invoke-EzDarkFactoryBaseBuild -Root $fixture.Root -Accelerator tcg -BuildTimeoutSeconds 60 -QemuStatusProvider $fixture.QemuStatusProvider -SourceProvider $fixture.SourceProvider -QemuImgRunner $fixture.QemuImgRunner -GuestRunner $fixture.GuestRunner
    $baseRunner = $fixture.QemuImgRunner
    $storageRunner = {
        param($argumentList)
        $arguments = @($argumentList)
        $command = $arguments[0]
        if ($command -ceq 'create') {
            $destination = [IO.Path]::GetFullPath($arguments[$arguments.Count - 1])
            $backingIndex = [Array]::IndexOf($arguments, '-b')
            $backing = $arguments[$backingIndex + 1]
            [IO.File]::WriteAllText($destination, ([pscustomobject][ordered]@{
                kind = 'edf004-runtime-overlay'; backing = $backing
            } | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
            return [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
        }
        if ($command -ceq 'info') {
            $path = [IO.Path]::GetFullPath($arguments[$arguments.Count - 1])
            $payload = $null
            try {
                $text = [IO.File]::ReadAllText($path)
                if ($text.StartsWith('{', [StringComparison]::Ordinal)) { $payload = $text | ConvertFrom-Json -ErrorAction Stop }
            } catch { $payload = $null }
            if ($null -ne $payload -and $payload.kind -ceq 'edf004-runtime-overlay') {
                $resolved = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($path)) ([string]$payload.backing)))
                $top = [pscustomobject][ordered]@{
                    filename = $path; format = 'qcow2'; 'virtual-size' = [long]17179869184
                    'backing-filename' = [string]$payload.backing; 'backing-filename-format' = 'qcow2'
                }
                $baseInfo = [pscustomobject][ordered]@{
                    filename = $resolved; format = 'qcow2'; 'virtual-size' = [long]17179869184
                }
                if ($arguments -ccontains '--backing-chain') {
                    return [pscustomobject]@{ ExitCode = 0; StdOut = (@($top, $baseInfo) | ConvertTo-Json -Compress); StdErr = '' }
                }
                return [pscustomobject]@{ ExitCode = 0; StdOut = ($top | ConvertTo-Json -Compress); StdErr = '' }
            }
        }
        return & $baseRunner $arguments
    }.GetNewClosure()
    return [pscustomobject]@{ Base = $fixture; Build = $base; StorageRunner = $storageRunner }
}

Add-EzDarkFactoryTest -Name 'EDF-004: fresh-project v1 is distinct EDF profile with stable tool and policy contract' -ScriptBlock {
    $profile = Get-EzDarkFactoryCodingProfile -Root $script:EzDarkFactoryRepositoryRoot -Name 'fresh-project' -Version 1
    Assert-EzDarkFactoryEqual -Actual $profile.Name -Expected 'fresh-project'
    Assert-EzDarkFactoryEqual -Actual $profile.Version -Expected 1
    Assert-EzDarkFactoryTrue -Condition ($profile.Digest -cmatch '^[a-f0-9]{64}$')
    Assert-EzDarkFactoryEqual -Actual $profile.Manifest.workspacePolicy -Expected 'empty-at-first-ready'
    Assert-EzDarkFactoryEqual -Actual $profile.Manifest.historicalWorkloadPolicy -Expected 'absent'
    Assert-EzDarkFactoryEqual -Actual $profile.Manifest.referencePolicy -Expected 'isolated-opt-in'
    Assert-EzDarkFactoryEqual -Actual $profile.Manifest.user -Expected 'coder'
    Assert-EzDarkFactoryEqual -Actual $profile.Manifest.workspace -Expected '/home/coder/workspace'
    Assert-EzDarkFactoryEqual -Actual $profile.Manifest.privilege -Expected 'passwordless-sudo'
    $legacy = Get-EzDarkFactoryCodingProfile -Root $script:EzDarkFactoryRepositoryRoot -Name 'coding-default' -Version 1
    Assert-EzDarkFactoryTrue -Condition ($legacy.Digest -cne $profile.Digest)
}

Add-EzDarkFactoryTest -Name 'EDF-004: new managed instance defaults to fresh-project and unique durable generation' -ScriptBlock {
    $f = New-EzDarkFactoryEdf004Fixture
    try {
        $first = New-EzDarkFactoryManagedInstance -Root $f.Base.Root -InstanceName 'fresh-one' -BaseId $f.Build.baseId -Profile light -QemuImgRunner $f.StorageRunner -PortProbe { $true }
        $second = New-EzDarkFactoryManagedInstance -Root $f.Base.Root -InstanceName 'fresh-two' -BaseId $f.Build.baseId -Profile light -QemuImgRunner $f.StorageRunner -PortProbe { $true }
        foreach ($created in @($first, $second)) {
            Assert-EzDarkFactoryEqual -Actual $created.provisioningProfile -Expected 'fresh-project'
            Assert-EzDarkFactoryEqual -Actual $created.provisioningVersion -Expected 1
            Assert-EzDarkFactoryTrue -Condition ($created.identityGeneration -cmatch '^[a-f0-9]{32}$')
        }
        Assert-EzDarkFactoryTrue -Condition ($first.identityGeneration -cne $second.identityGeneration)
    }
    finally { Remove-EzDarkFactoryBaseBuildFixture $f.Base }
}

Add-EzDarkFactoryTest -Name 'EDF-004: sensitive snapshot bases cannot masquerade as fresh empty projects' -ScriptBlock {
    $source = [IO.File]::ReadAllText((Join-Path $script:EzDarkFactoryRepositoryRoot 'src/EzDarkFactory/Registry.ps1'))
    Assert-EzDarkFactoryTrue -Condition $source.Contains('Test-EzDarkFactoryPreparedBase -Root $Root -BaseId $base.BaseId')
    Assert-EzDarkFactoryTrue -Condition $source.Contains('[int]$validatedBase.Manifest.schemaVersion -eq 1')
    Assert-EzDarkFactoryTrue -Condition $source.Contains("{ 'fresh-project' } else { 'coding-default' }")
    Assert-EzDarkFactoryTrue -Condition $source.Contains('Get-EzDarkFactoryCodingProfile -Root $Root -Name $provisioningProfileName -Version 1')
}

Add-EzDarkFactoryTest -Name 'EDF-004: generated seed binds current base generation and fresh profile marker without private material' -ScriptBlock {
    $f = New-EzDarkFactoryEdf004Fixture
    try {
        $created = New-EzDarkFactoryManagedInstance -Root $f.Base.Root -InstanceName 'fresh-seed' -BaseId $f.Build.baseId -Profile normal -QemuImgRunner $f.StorageRunner -PortProbe { $true }
        $intent = Get-EzDarkFactoryInstanceIntent -Root $f.Base.Root -InstanceName 'fresh-seed'
        $seed = New-EzDarkFactoryInstanceSeedData -Root $f.Base.Root -Intent $intent -InstanceName $intent.name -ControllerPublicKey 'ssh-ed25519 AAAA edf004-comment'
        Assert-EzDarkFactoryEqual -Actual $seed.Identity.baseId -Expected $intent.baseId
        Assert-EzDarkFactoryEqual -Actual $seed.Identity.provisioningProfile -Expected 'fresh-project'
        Assert-EzDarkFactoryEqual -Actual $seed.Identity.provisioningVersion -Expected 1
        Assert-EzDarkFactoryEqual -Actual $seed.Identity.provisioningDigest -Expected (Get-EzDarkFactoryCodingProfile -Root $f.Base.Root -Name 'fresh-project' -Version 1).Digest
        $expectedCloudId = & (Get-Module EzDarkFactory) { param($i) Get-EzDarkFactoryGuestCloudInstanceId -Intent $i } $intent
        Assert-EzDarkFactoryEqual -Actual $seed.CloudInstanceId -Expected $expectedCloudId
        Assert-EzDarkFactoryTrue -Condition ($seed.UserData.Contains('"name": "fresh-project"') -or $seed.UserData.Contains('fresh-project'))
        Assert-EzDarkFactoryTrue -Condition (-not $seed.UserData.Contains('edf004-comment'))
        Assert-EzDarkFactoryTrue -Condition ($seed.UserData -notmatch '(?i)PRIVATE KEY|github_pat_|ghp_[A-Za-z0-9]')
    }
    finally { Remove-EzDarkFactoryBaseBuildFixture $f.Base }
}

Add-EzDarkFactoryTest -Name 'EDF-004: first READY requires empty workspace and refuses historical provider model or autostart state' -ScriptBlock {
    $profile = Get-EzDarkFactoryCodingProfile -Root $script:EzDarkFactoryRepositoryRoot -Name 'fresh-project' -Version 1
    $script = $profile.Script
    foreach ($needle in @(
        "prior_ready=0", "fresh workspace is not empty", "historical workload state exists in coder home",
        "provider, model, credential or autostart state exists in coder home",
        "project-specific coder crontab exists", "historical workload, agent or model service is installed",
        ".config/opencode", ".config/gh/hosts.yml", ".cache/huggingface", ".ollama",
        ".config/systemd/user", ".config/autostart"
    )) { Assert-EzDarkFactoryTrue -Condition $script.Contains($needle) -Message ("Missing fresh refusal: " + $needle) }
    Assert-EzDarkFactoryTrue -Condition ($script.Contains("prior_ready != '1'")) -Message 'Only a matching prior completed marker may make same-generation provisioning idempotent after project files exist.'
    Assert-EzDarkFactoryTrue -Condition ($script.Contains('rm -f -- /var/lib/ezdarkfactory/ready.json')) -Message 'Live revalidation must invalidate cached READY before executing.'
    Assert-EzDarkFactoryTrue -Condition ($script -notmatch '(?i)rm\s+-rf\s+--?\s+/home/coder/workspace|chown\s+-R') -Message 'Fresh validation must never erase or recursively rewrite user project files.'
}

Add-EzDarkFactoryTest -Name 'EDF-004: base recipe remains project-neutral and scrubs machine SSH and cloud identity before publication' -ScriptBlock {
    $root = $script:EzDarkFactoryRepositoryRoot
    $base = [IO.File]::ReadAllText((Join-Path $root 'guest/base-cloud-init/user-data.yaml'))
    foreach ($needle in @('rm -f /etc/ssh/ssh_host_*', "find /root /home -type f -path '*/.ssh/authorized_keys' -delete", 'cloud-init clean --logs --machine-id')) {
        Assert-EzDarkFactoryTrue -Condition $base.Contains($needle) -Message ('Missing base hygiene: ' + $needle)
    }
    Assert-EzDarkFactoryTrue -Condition ($base -notmatch '(?i)tuisynth|TRIO|OPENSSH PRIVATE KEY|github_pat_|ghp_[A-Za-z0-9]|controller_ed25519')
    $recipe = Read-EzDarkFactoryJson -Path (Join-Path $root 'guest/base-cloud-init/baseline.json')
    foreach ($command in @('git','gcc','g++','make','cmake','ninja','python3','pip3','curl','wget','jq','rg','unzip','zip','rsync','tmux','ssh','scp','sshd','sudo','cloud-init')) {
        Assert-EzDarkFactoryTrue -Condition (@($recipe.requiredCommands) -ccontains $command)
    }
}

Add-EzDarkFactoryTest -Name 'EDF-004: sensitive-base reset and fresh clone rotate generation without claiming fresh profile' -ScriptBlock {
    # Reuse the repository's synthetic QCOW2 fixture so this crosses the
    # accepted reset/clone storage boundary, not a JSON disk stand-in.
    $f = New-EzDarkFactorySnapshotFixture
    try {
        $created = New-EzDarkFactoryManagedInstance -Root $f.Root -InstanceName 'fresh-source' -BaseId $f.Base.BaseId -Profile light -QemuImgRunner $f.Runner -PortProbe { $true }
        $before = Get-EzDarkFactoryInstanceIntent -Root $f.Root -InstanceName 'fresh-source'
        Assert-EzDarkFactoryEqual -Actual $before.provisioningProfile -Expected 'coding-default'
        $reset = Reset-EzDarkFactoryManagedInstance -Root $f.Root -InstanceName 'fresh-source' -QemuImgRunner $f.Runner -ProcessProvider { @() }
        $after = Get-EzDarkFactoryInstanceIntent -Root $f.Root -InstanceName 'fresh-source'
        Assert-EzDarkFactoryEqual -Actual $after.provisioningProfile -Expected 'coding-default'
        Assert-EzDarkFactoryTrue -Condition ($after.identityGeneration -cne $before.identityGeneration)
        Assert-EzDarkFactoryEqual -Actual $reset.identityGeneration -Expected $after.identityGeneration
        $clone = Copy-EzDarkFactoryManagedInstance -Root $f.Root -SourceInstanceName 'fresh-source' -DestinationInstanceName 'fresh-clone' -Mode fresh -QemuImgRunner $f.Runner -QemuStatusProvider $f.QemuStatusProvider -ProcessProvider { @() } -PortProbe { $true }
        $cloneIntent = Get-EzDarkFactoryInstanceIntent -Root $f.Root -InstanceName 'fresh-clone'
        Assert-EzDarkFactoryEqual -Actual $cloneIntent.provisioningProfile -Expected 'coding-default'
        Assert-EzDarkFactoryTrue -Condition ($cloneIntent.identityGeneration -cne $after.identityGeneration)
        # The fixture deliberately uses an imported/sensitive base; fresh
        # identity must not erase that provenance classification.
        Assert-EzDarkFactoryEqual -Actual $clone.sensitiveState -Expected $true
    }
    finally { Remove-EzDarkFactorySnapshotFixture $f }
}

Add-EzDarkFactoryTest -Name 'EDF-004: stale and legacy READY cannot impersonate fresh current generation' -ScriptBlock {
    $profile = Get-EzDarkFactoryCodingProfile -Root $script:EzDarkFactoryRepositoryRoot -Name 'fresh-project' -Version 1
    $expected = [ordered]@{
        schemaVersion = 2; instanceName = 'fresh-ready'; baseId = ('base-' + ('a' * 64)); profile = 'normal'
        cloudInstanceId = 'ezdarkfactory-fresh-ready-012345abcdef'; provisioningProfile = 'fresh-project'
        provisioningVersion = 1; provisioningDigest = $profile.Digest
    }
    $identityJson = ([pscustomobject]$expected | ConvertTo-Json -Compress)
    $ready = [ordered]@{}; foreach ($key in $expected.Keys) { $ready[$key] = $expected[$key] }; $ready.provisioningState = 'complete'
    $encode = { param($value) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($value)) }
    $probe = @(
        'EDF_IDENTITY_B64=' + (& $encode $identityJson)
        'EDF_CLOUD_B64=' + (& $encode 'status: done')
        'EDF_CLOUD_EXIT=0'
        'EDF_READY_B64=' + (& $encode (([pscustomobject]$ready | ConvertTo-Json -Compress)))
        'EDF_PROFILE_CHECK=pass'
        'EDF_PROFILE_ERROR_B64=' + (& $encode '')
    ) -join [Environment]::NewLine
    $ok = ConvertFrom-EzDarkFactoryReadinessProbe -StdOut $probe -ExpectedInstanceName $expected.instanceName -ExpectedBaseId $expected.baseId -ExpectedProfile $expected.profile -ExpectedCloudInstanceId $expected.cloudInstanceId -ExpectedProvisioningProfile 'fresh-project' -ExpectedProvisioningVersion 1 -ExpectedProvisioningDigest $profile.Digest
    Assert-EzDarkFactoryTrue -Condition $ok.Ready
    Assert-EzDarkFactoryThrows -ScriptBlock {
        ConvertFrom-EzDarkFactoryReadinessProbe -StdOut $probe -ExpectedInstanceName $expected.instanceName -ExpectedBaseId $expected.baseId -ExpectedProfile $expected.profile -ExpectedCloudInstanceId 'ezdarkfactory-fresh-ready-fedcba543210' -ExpectedProvisioningProfile 'fresh-project' -ExpectedProvisioningVersion 1 -ExpectedProvisioningDigest $profile.Digest
    } -MessagePattern 'identity mismatch' | Out-Null
    Assert-EzDarkFactoryThrows -ScriptBlock {
        ConvertFrom-EzDarkFactoryReadinessProbe -StdOut $probe -ExpectedInstanceName $expected.instanceName -ExpectedBaseId $expected.baseId -ExpectedProfile $expected.profile -ExpectedCloudInstanceId $expected.cloudInstanceId -ExpectedProvisioningProfile 'coding-default' -ExpectedProvisioningVersion 1 -ExpectedProvisioningDigest $profile.Digest
    } -MessagePattern 'identity mismatch' | Out-Null
}
