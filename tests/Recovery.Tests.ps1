Add-EzDarkFactoryTest -Name 'Recovery: absent instance diagnosis is read-only and explicit about missing intent' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'absent diagnosis'
    try {
        $result = Get-EzDarkFactoryInstanceDiagnosis -Root $root -InstanceName absent
        Assert-EzDarkFactoryEqual $result.lifecycleState 'ABSENT'
        Assert-EzDarkFactoryEqual $result.repairsPerformed $false
        Assert-EzDarkFactoryTrue ($result.findings.code -contains 'instance_missing')
        Assert-EzDarkFactoryEqual $result.imageCheck 'not-requested'
        Assert-EzDarkFactoryTrue (-not (Test-Path -LiteralPath (Get-EzDarkFactoryPaths $root).Runtime))
        $cli = Invoke-EzDarkFactoryCommand -Root $root -Arguments @('diagnose', 'absent', '-Json')
        Assert-EzDarkFactoryEqual $cli.exitCode 0
        Assert-EzDarkFactoryEqual $cli.data.status 'attention'
        foreach ($args in @(@('diagnose'), @('diagnose', '../bad'), @('diagnose', 'one', '-Force'), @('diagnose', 'one', '-CheckImage', '-CheckImage'))) {
            Assert-EzDarkFactoryEqual (Invoke-EzDarkFactoryCommand -Root $root -Arguments $args).exitCode 2
        }
    }
    finally { Remove-EzDarkFactoryTestDirectory $root }
}

Add-EzDarkFactoryTest -Name 'Recovery: stopped image inspection verifies headers chain digest and integrity without changing data' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    try {
        $before = Get-EzDarkFactoryFileDigest -Path $fixture.Disk -Algorithm SHA256
        $intentPath = (Get-EzDarkFactoryInstanceRuntimePaths -Root $fixture.Root -InstanceName $fixture.Intent.name).Intent
        $intentBefore = [IO.File]::ReadAllText($intentPath)
        $result = Get-EzDarkFactoryInstanceDiagnosis -Root $fixture.Root -InstanceName $fixture.Intent.name -CheckImage -ProcessProvider { @() } -QemuImgRunner $fixture.Runner
        Assert-EzDarkFactoryEqual $result.imageCheck 'passed'
        Assert-EzDarkFactoryEqual $result.repairsPerformed $false
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $fixture.Disk -Algorithm SHA256) $before
        Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText($intentPath)) $intentBefore
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Recovery: running ambiguous and stale owners cannot reach offline diagnostic tools' -ScriptBlock {
    foreach ($mode in @('running', 'stale', 'unknown')) {
        $root = New-EzDarkFactoryCheckoutFixture -Prefix ('diagnosis ownership ' + $mode)
        try {
            $intent = New-EzDarkFactoryPortabilityIdentityTestIntent
            $access = New-EzDarkFactorySshTestAccess -Root $root -Intent $intent
            $launch = New-EzDarkFactorySshTestLaunch -Root $root -Intent $intent -Access $access
            $paths = Get-EzDarkFactoryInstanceRuntimePaths -Root $root -InstanceName $intent.name
            $original = [IO.File]::ReadAllText($paths.Runtime)
            $provider = if ($mode -ceq 'running') { $launch.ProcessProvider } elseif ($mode -ceq 'stale') { { @() } } else { { throw 'process query unavailable' } }
            $observed = [pscustomobject]@{ Calls = 0 }
            $runner = { param($a) $observed.Calls++; throw 'must not invoke qemu-img' }.GetNewClosure()
            $result = Get-EzDarkFactoryInstanceDiagnosis -Root $root -InstanceName $intent.name -CheckImage -ProcessProvider $provider -QemuImgRunner $runner
            Assert-EzDarkFactoryEqual $result.imageCheck 'refused'
            Assert-EzDarkFactoryEqual $observed.Calls 0
            Assert-EzDarkFactoryEqual $result.repairsPerformed $false
            Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText($paths.Runtime)) $original
        }
        finally { Remove-EzDarkFactoryTestDirectory $root }
    }
}

Add-EzDarkFactoryTest -Name 'Recovery: missing base bad provenance and redirected backing provide actionable fail-closed findings' -ScriptBlock {
    foreach ($mode in @('missing', 'manifest', 'backing', 'digest', 'corrupt')) {
        $fixture = New-EzDarkFactorySnapshotFixture
        try {
            $paths = Get-EzDarkFactoryInstanceRuntimePaths -Root $fixture.Root -InstanceName $fixture.Intent.name
            if ($mode -ceq 'missing') { [IO.File]::Move($fixture.Base.Image, ($fixture.Base.Image + '.saved')) }
            elseif ($mode -ceq 'manifest') {
                [IO.File]::SetAttributes($fixture.Base.ManifestPath, [IO.FileAttributes]::Normal)
                [IO.File]::WriteAllText($fixture.Base.ManifestPath, '{bad')
            }
            elseif ($mode -ceq 'backing') { Write-EzDarkFactorySnapshotFixtureImage -Path $fixture.Disk -Backing '../../../outside.qcow2' }
            elseif ($mode -ceq 'digest') {
                [IO.File]::SetAttributes($fixture.Base.Image, [IO.FileAttributes]::Normal)
                [IO.File]::AppendAllText($fixture.Base.Image, 'tamper')
            }
            else { $fixture.State.Mode = 'bad-check' }
            $before = Get-EzDarkFactoryFileDigest -Path $fixture.Disk -Algorithm SHA256
            $result = Get-EzDarkFactoryInstanceDiagnosis -Root $fixture.Root -InstanceName $fixture.Intent.name -CheckImage -ProcessProvider { @() } -QemuImgRunner $fixture.Runner
            Assert-EzDarkFactoryEqual $result.imageCheck 'failed'
            Assert-EzDarkFactoryTrue ($result.findings.Count -gt 0)
            Assert-EzDarkFactoryTrue (@($result.findings | Where-Object { $_.remediation.Length -lt 20 }).Count -eq 0)
            Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $fixture.Disk -Algorithm SHA256) $before
        }
        finally { Remove-EzDarkFactorySnapshotFixture $fixture }
    }
}

Add-EzDarkFactoryTest -Name 'Recovery: interrupted reset journal and staging artifacts are preserved and never followed as instructions' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    try {
        $paths = Get-EzDarkFactoryInstanceRuntimePaths -Root $fixture.Root -InstanceName $fixture.Intent.name
        $journal = '{"schemaVersion":1,"untrustedPath":"../../outside","private":"synthetic"}'
        [IO.File]::WriteAllText($paths.Operation, $journal)
        $artifact = Join-Path $paths.Directory ('.disk-backup-' + ('a' * 32) + '.qcow2')
        [IO.File]::WriteAllText($artifact, 'recovery bytes')
        $result = Get-EzDarkFactoryInstanceDiagnosis -Root $fixture.Root -InstanceName $fixture.Intent.name -CheckImage -ProcessProvider { @() } -QemuImgRunner { throw 'must not open image' }
        Assert-EzDarkFactoryEqual $result.imageCheck 'refused'
        Assert-EzDarkFactoryTrue ($result.findings.code -contains 'interrupted_reset')
        Assert-EzDarkFactoryEqual $result.recoveryArtifacts.Count 1
        Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText($artifact)) 'recovery bytes'
        Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText($paths.Operation)) $journal
        Assert-EzDarkFactoryTrue (($result | ConvertTo-Json -Depth 8) -notmatch 'untrustedPath|synthetic')
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Recovery: a real loopback collision is diagnosed without changing durable reservations' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        $fixture.Intent.sshPort = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
        $paths = Get-EzDarkFactoryInstanceRuntimePaths -Root $fixture.Root -InstanceName $fixture.Intent.name
        Write-EzDarkFactoryJson -Path $paths.Intent -Value $fixture.Intent -SchemaVersion 2
        $before = [IO.File]::ReadAllText($paths.Intent)
        $result = Get-EzDarkFactoryInstanceDiagnosis -Root $fixture.Root -InstanceName $fixture.Intent.name -ProcessProvider { @() }
        Assert-EzDarkFactoryTrue ($result.findings.code -contains 'port_collision')
        Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText($paths.Intent)) $before
    }
    finally { $listener.Stop(); Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Recovery: failed base build clears seed input while preserving disk and redacted failure evidence' -ScriptBlock {
    $fixture = New-EzDarkFactoryBaseBuildFixture
    try {
        $credential = 'ghp_' + ('Z' * 36)
        $guest = { param($context) throw ('failure with ' + $credential) }.GetNewClosure()
        Assert-EzDarkFactoryThrows { Invoke-EzDarkFactoryBaseBuild -Root $fixture.Root -Accelerator tcg -BuildTimeoutSeconds 60 -QemuStatusProvider $fixture.QemuStatusProvider -SourceProvider $fixture.SourceProvider -QemuImgRunner $fixture.QemuImgRunner -GuestRunner $guest } | Out-Null
        $stage = @(Get-ChildItem -LiteralPath $fixture.Paths.Bases -Directory -Force -Filter '.build-*')[0]
        Assert-EzDarkFactoryTrue (-not (Test-Path -LiteralPath (Join-Path $stage.FullName 'seed')))
        Assert-EzDarkFactoryTrue (Test-Path -LiteralPath (Join-Path $stage.FullName 'staging.qcow2'))
        $failure = [IO.File]::ReadAllText((Join-Path $stage.FullName 'failure.json'))
        Assert-EzDarkFactoryTrue ($failure.Contains('[REDACTED]') -and -not $failure.Contains($credential))
    }
    finally { Remove-EzDarkFactoryBaseBuildFixture $fixture }
}
