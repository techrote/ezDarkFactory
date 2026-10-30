Add-EzDarkFactoryTest -Name 'Doctor: overall classification has deterministic severity precedence' -ScriptBlock {
    $module = Get-Module EzDarkFactory
    $ready = @([pscustomobject]@{ status = 'ready' })
    $unknown = @([pscustomobject]@{ status = 'ready' }, [pscustomobject]@{ status = 'unknown' })
    $notConfigured = @([pscustomobject]@{ status = 'unknown' }, [pscustomobject]@{ status = 'supported-but-not-configured' })
    $unsupported = @([pscustomobject]@{ status = 'supported-but-not-configured' }, [pscustomobject]@{ status = 'unsupported' })

    $a = & $module { param($checks) Resolve-EzDarkFactoryDoctorOverallStatus -Checks $checks } (, $ready)
    $b = & $module { param($checks) Resolve-EzDarkFactoryDoctorOverallStatus -Checks $checks } (, $unknown)
    $c = & $module { param($checks) Resolve-EzDarkFactoryDoctorOverallStatus -Checks $checks } (, $notConfigured)
    $d = & $module { param($checks) Resolve-EzDarkFactoryDoctorOverallStatus -Checks $checks } (, $unsupported)
    Assert-EzDarkFactoryEqual -Actual $a -Expected 'ready'
    Assert-EzDarkFactoryEqual -Actual $b -Expected 'unknown'
    Assert-EzDarkFactoryEqual -Actual $c -Expected 'supported-but-not-configured'
    Assert-EzDarkFactoryEqual -Actual $d -Expected 'unsupported'
}

Add-EzDarkFactoryTest -Name 'Doctor: report has independent prerequisite checks and never claims WHPX execution' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'doctor [root] with spaces'
    try {
        $report = Get-EzDarkFactoryDoctorReport -Root $root
        Assert-EzTrueStatusVocabulary -Checks $report.checks
        $names = @($report.checks | ForEach-Object { $_.name })
        foreach ($required in @(
            'host-os', 'powershell', 'hardware-virtualization', 'whpx',
            'runtime-write', 'path', 'disk-space', 'managed-qemu', 'openssh-client', 'runtime-state'
        )) {
            Assert-EzDarkFactoryTrue -Condition ($names -ccontains $required) -Message "Doctor omitted '$required'."
        }
        Assert-EzDarkFactoryEqual -Actual $report.whpxExecutionTested -Expected $false
        Assert-EzDarkFactoryTrue -Condition ($report.note -match 'does not claim WHPX execution')
        $managed = @($report.checks | Where-Object { $_.name -ceq 'managed-qemu' })[0]
        Assert-EzDarkFactoryEqual -Actual $managed.status -Expected 'supported-but-not-configured'
        Assert-EzDarkFactoryTrue -Condition ($managed.remediation -match 'bootstrap')
        $path = @($report.checks | Where-Object { $_.name -ceq 'path' })[0]
        Assert-EzDarkFactoryEqual -Actual $path.status -Expected 'ready'
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

function Assert-EzTrueStatusVocabulary {
    param([object[]]$Checks)
    foreach ($check in $Checks) {
        Assert-EzDarkFactoryTrue -Condition (@('ready', 'supported-but-not-configured', 'unsupported', 'unknown') -ccontains $check.status) -Message "Unexpected doctor status '$($check.status)'."
        Assert-EzDarkFactoryTrue -Condition (-not [string]::IsNullOrWhiteSpace($check.message))
    }
}

Add-EzDarkFactoryTest -Name 'Doctor: JSON CLI output is structured even when host is not release-ready' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'doctor CLI'
    try {
        $result = Invoke-EzDarkFactoryCliForTest -ArgumentList @('doctor', '-Json') -Root $root
        $value = Assert-EzDarkFactoryJsonEnvelope -Result $result -Command 'doctor' -ExitCode 0
        Assert-EzDarkFactoryTrue -Condition (@('ready', 'supported-but-not-configured', 'unsupported', 'unknown') -ccontains $value.data.status)
        Assert-EzDarkFactoryEqual -Actual $value.data.whpxExecutionTested -Expected $false
        Assert-EzDarkFactoryTrue -Condition (@($value.data.checks).Count -ge 8)
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Doctor: WHPX remediation is informational and host features are never enabled by code' -ScriptBlock {
    $source = [IO.File]::ReadAllText((Join-Path $script:EzDarkFactoryRepositoryRoot 'src/EzDarkFactory/Doctor.ps1'))
    Assert-EzDarkFactoryTrue -Condition ($source -notmatch '(?i)Enable-WindowsOptionalFeature') -Message 'doctor must never enable Windows optional features.'
    Assert-EzDarkFactoryTrue -Condition ($source -notmatch '(?i)Start-Process[^\r\n]*RunAs') -Message 'doctor must never elevate itself.'
    Assert-EzDarkFactoryTrue -Condition ($source -notmatch '(?i)Invoke-EzDarkFactoryProcess[^\r\n]*dism') -Message 'doctor must never execute DISM feature changes.'
    Assert-EzDarkFactoryTrue -Condition ($source -match 'DISM /online /Enable-Feature /FeatureName:HypervisorPlatform /All') -Message 'doctor should provide the documented remediation command as text.'
}

Add-EzDarkFactoryTest -Name 'Doctor: runtime-state files are reported as unknown rather than trusted PID evidence' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'doctor stale state'
    try {
        $paths = Get-EzDarkFactoryPaths -Root $root
        $instance = Join-Path $paths.Instances 'fixture'
        [void][IO.Directory]::CreateDirectory($instance)
        Write-EzDarkFactoryJson -Path (Join-Path $instance 'runtime.json') -Value ([pscustomobject][ordered]@{
            schemaVersion = 1
            pid = 1234
        })
        $report = Get-EzDarkFactoryDoctorReport -Root $root
        $state = @($report.checks | Where-Object { $_.name -ceq 'runtime-state' })[0]
        Assert-EzDarkFactoryEqual -Actual $state.status -Expected 'unknown'
        Assert-EzDarkFactoryTrue -Condition ($state.message -match 'Reconcile each instance')
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}
