Add-EzDarkFactoryTest -Name 'Base recipe: reviewed baseline contains the stable coding prerequisites' -ScriptBlock {
    $recipe = Get-EzDarkFactoryBaseRecipe -Root $script:EzDarkFactoryRepositoryRoot
    Assert-EzDarkFactoryEqual -Actual $recipe.recipeVersion -Expected '2'
    Assert-EzDarkFactoryEqual -Actual $recipe.machine -Expected 'q35'
    Assert-EzDarkFactoryEqual -Actual $recipe.seedGuestAddress -Expected '10.0.2.100'
    Assert-EzDarkFactoryEqual -Actual $recipe.seedGuestPort -Expected 8000
    foreach ($package in @(
        'openssh-server', 'git', 'build-essential', 'cmake', 'ninja-build',
        'python3', 'python3-venv', 'curl', 'wget', 'jq', 'ripgrep',
        'unzip', 'zip', 'rsync', 'tmux'
    )) {
        Assert-EzDarkFactoryTrue -Condition (@($recipe.packages) -ccontains $package) -Message "Baseline recipe omitted '$package'."
    }
}

Add-EzDarkFactoryTest -Name 'Base recipe: generated NoCloud seed is build-specific, credential-free and cleans golden-image identity' -ScriptBlock {
    $buildId = '0123456789abcdef0123456789abcdef'
    $seed = New-EzDarkFactoryBaseSeedData -Root $script:EzDarkFactoryRepositoryRoot -BuildId $buildId
    Assert-EzDarkFactoryTrue -Condition ($seed.MetaData -match ('instance-id: ezdarkfactory-base-' + $buildId))
    Assert-EzDarkFactoryTrue -Condition ($seed.UserData -match 'package_update: true')
    Assert-EzDarkFactoryTrue -Condition ($seed.UserData -match 'cloud-init clean --logs --machine-id')
    Assert-EzDarkFactoryTrue -Condition ($seed.UserData -match 'rm -f /etc/ssh/ssh_host_')
    Assert-EzDarkFactoryTrue -Condition ($seed.UserData -match 'systemd-run')
    Assert-EzDarkFactoryTrue -Condition ($seed.UserData -match 'systemd-run, --no-block, .*--property=Type=oneshot') -Message 'The oneshot finalizer must be queued non-blocking so cloud-final can finish before cloud-init status --wait returns.'
    Assert-EzDarkFactoryTrue -Condition ($seed.UserData -match 'cloud-init status --wait') -Message 'Finalization must wait on cloud-init completion state.'
    Assert-EzDarkFactoryTrue -Condition ($seed.UserData -notmatch 'systemctl is-active --quiet cloud-final') -Message 'cloud-final remains active after exit on supported cloud-init units; do not use it as completion state.'
    Assert-EzDarkFactoryTrue -Condition ($seed.UserData -notmatch '(?m)^\s*- \[systemd-run, --unit=.*--property=Type=oneshot') -Message 'A blocking Type=oneshot launch deadlocks cloud-final against cloud-init status --wait.'
    Assert-EzDarkFactoryTrue -Condition ($seed.UserData -match 'EDF_BASE_READY=1')
    Assert-EzDarkFactoryTrue -Condition ($seed.UserData -notmatch '__[A-Z0-9_]+__')
    Assert-EzDarkFactoryTrue -Condition ($seed.UserData -notmatch '(?im)PRIVATE KEY|github_pat_|ghp_[A-Za-z0-9]')
    Assert-EzDarkFactoryTrue -Condition ($seed.ProvisioningDigest -match '^[a-f0-9]{64}$')
}

Add-EzDarkFactoryTest -Name 'Base recipe: provisioning digest changes when reviewed recipe source changes' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'base digest source'
    try {
        $before = Get-EzDarkFactoryBaseProvisioningDigest -Root $root
        $path = (Get-EzDarkFactoryPaths -Root $root).BaseMetaDataTemplate
        [IO.File]::AppendAllText($path, [Environment]::NewLine + '# fixture change')
        $after = Get-EzDarkFactoryBaseProvisioningDigest -Root $root
        Assert-EzDarkFactoryTrue -Condition ($before -cne $after) -Message 'Provisioning digest must cover every reviewed seed source.'
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Base recipe: QEMU arguments use explicit UEFI, virtio and loopback guest forwarding' -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'base qemu args with spaces'
    try {
        $recipe = Get-EzDarkFactoryBaseRecipe -Root $script:EzDarkFactoryRepositoryRoot
        $disk = Join-Path $root 'staging disk.qcow2'
        $code = Join-Path $root 'edk2 code.fd'
        $vars = Join-Path $root 'edk2 vars.fd'
        $serial = Join-Path $root 'serial log.txt'
        foreach ($path in @($disk, $code, $vars)) { [IO.File]::WriteAllText($path, 'fixture') }

        $command = New-EzDarkFactoryBaseQemuArguments -BuildId '0123456789abcdef0123456789abcdef' -Recipe $recipe -StagingDisk $disk -FirmwareCode $code -FirmwareVariables $vars -SerialLog $serial -SeedHostPort 32123 -Accelerator whpx
        $joined = $command.Arguments -join [char]10
        Assert-EzDarkFactoryEqual -Actual $command.SeedUrl -Expected 'http://10.0.2.100:8000/'
        Assert-EzDarkFactoryEqual -Actual $command.GuestForward -Expected 'guestfwd=tcp:10.0.2.100:8000-tcp:127.0.0.1:32123'
        Assert-EzDarkFactoryTrue -Condition ($joined -match '(?m)^q35$')
        Assert-EzDarkFactoryTrue -Condition ($joined -match 'virtio-blk-pci,drive=osdisk')
        Assert-EzDarkFactoryTrue -Condition ($joined -match 'virtio-net-pci,netdev=net0')
        Assert-EzDarkFactoryTrue -Condition ($joined -match 'readonly=on')
        Assert-EzDarkFactoryTrue -Condition ($joined -match 'ds=nocloud;s=http://10\.0\.2\.100:8000/')
        Assert-EzDarkFactoryTrue -Condition ($joined -match '(?m)^whpx$')
        Assert-EzDarkFactoryTrue -Condition ($joined -notmatch '(?i)hostfwd=|0\.0\.0\.0|cloud-localds|mkisofs')
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Base recipe: TCG is explicit qualification mode and never substituted into WHPX arguments' -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'base accelerator args'
    try {
        $recipe = Get-EzDarkFactoryBaseRecipe -Root $script:EzDarkFactoryRepositoryRoot
        $disk = Join-Path $root 'disk.qcow2'
        $code = Join-Path $root 'code.fd'
        $vars = Join-Path $root 'vars.fd'
        $serial = Join-Path $root 'serial.txt'
        foreach ($path in @($disk, $code, $vars)) { [IO.File]::WriteAllText($path, 'fixture') }

        $whpx = New-EzDarkFactoryBaseQemuArguments -BuildId 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' -Recipe $recipe -StagingDisk $disk -FirmwareCode $code -FirmwareVariables $vars -SerialLog $serial -SeedHostPort 32001 -Accelerator whpx
        $tcg = New-EzDarkFactoryBaseQemuArguments -BuildId 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' -Recipe $recipe -StagingDisk $disk -FirmwareCode $code -FirmwareVariables $vars -SerialLog $serial -SeedHostPort 32002 -Accelerator tcg
        Assert-EzDarkFactoryTrue -Condition (($whpx.Arguments -join ' ') -match ' -accel whpx ')
        Assert-EzDarkFactoryTrue -Condition (($whpx.Arguments -join ' ') -notmatch 'tcg')
        Assert-EzDarkFactoryTrue -Condition (($tcg.Arguments -join ' ') -match 'tcg,thread=multi')
        Assert-EzDarkFactoryTrue -Condition (($tcg.Arguments -join ' ') -match ' -cpu max ')
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Base recipe: invalid package or command tokens fail before cloud-init generation' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'base invalid recipe'
    try {
        $path = (Get-EzDarkFactoryPaths -Root $root).BaseBaseline
        $recipe = Read-EzDarkFactoryJson -Path $path
        $recipe.packages[0] = 'bad package'
        Write-EzDarkFactoryJson -Path $path -Value $recipe
        Assert-EzDarkFactoryThrows -ScriptBlock { Get-EzDarkFactoryBaseRecipe -Root $root } -MessagePattern 'package name' | Out-Null
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}
