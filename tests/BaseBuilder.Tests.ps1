function New-EzDarkFactoryBaseBuildFixture {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'prepared base build [fixture] with spaces'
    $paths = Get-EzDarkFactoryPaths -Root $root

    [void][IO.Directory]::CreateDirectory($paths.Qemu)
    $share = Join-Path $paths.Qemu 'share'
    [void][IO.Directory]::CreateDirectory($share)
    [IO.File]::WriteAllText((Join-Path $paths.Qemu 'qemu-system-x86_64.exe'), 'fixture qemu')
    [IO.File]::WriteAllText((Join-Path $paths.Qemu 'qemu-img.exe'), 'fixture qemu-img')
    [IO.File]::WriteAllText((Join-Path $share 'edk2-x86_64-code.fd'), 'fixture firmware code')
    [IO.File]::WriteAllText((Join-Path $share 'edk2-i386-vars.fd'), 'fixture firmware vars')

    [void][IO.Directory]::CreateDirectory($paths.SourceImages)
    $sourcePath = Join-Path $paths.SourceImages 'ubuntu-24.04-server-cloudimg-amd64.img'
    [IO.File]::WriteAllText($sourcePath, 'synthetic verified Ubuntu qcow2 source')
    $sourceDigest = Get-EzDarkFactoryFileDigest -Path $sourcePath -Algorithm SHA256

    $sourceManifest = Read-EzDarkFactoryJson -Path $paths.UbuntuManifest
    $sourceManifest.sha256 = $sourceDigest
    Write-EzDarkFactoryJson -Path $paths.UbuntuManifest -Value $sourceManifest

    $qemuStatusProvider = {
        param($fixtureRoot, $manifest)
        $fixturePaths = Get-EzDarkFactoryPaths -Root $fixtureRoot
        [pscustomobject]@{
            Valid = $true
            Reason = 'synthetic QEMU fixture'
            QemuSystem = Join-Path $fixturePaths.Qemu 'qemu-system-x86_64.exe'
            QemuImg = Join-Path $fixturePaths.Qemu 'qemu-img.exe'
            QemuSystemVersion = 'QEMU emulator version 11.1.0 (fixture)'
            QemuImgVersion = 'qemu-img version 11.1.0 (fixture)'
        }
    }

    $sourceProvider = {
        param($fixtureRoot, $manifest)
        $fixturePaths = Get-EzDarkFactoryPaths -Root $fixtureRoot
        $path = Join-Path $fixturePaths.SourceImages $manifest.filename
        [pscustomobject]@{
            path = $path
            sha256 = $manifest.sha256
            publication = $manifest.publication
            provenancePath = $path + '.provenance.json'
        }
    }

    $sourceForRunner = $sourcePath
    $qemuImgRunner = {
        param($argumentList)
        $arguments = @($argumentList)
        $command = $arguments[0]
        $stdout = ''
        if ($command -ceq 'create') {
            $destination = $arguments[$arguments.Count - 1]
            [IO.File]::WriteAllText($destination, 'synthetic staging overlay')
        }
        elseif ($command -ceq 'resize') {
        }
        elseif ($command -ceq 'convert') {
            $destination = $arguments[$arguments.Count - 1]
            [IO.File]::WriteAllText($destination, 'synthetic flattened standalone prepared base')
        }
        elseif ($command -ceq 'info') {
            $path = $arguments[$arguments.Count - 1]
            if ([IO.Path]::GetFileName($path) -ceq 'staging.qcow2') {
                $value = [pscustomobject][ordered]@{
                    format = 'qcow2'
                    'virtual-size' = [long]17179869184
                    'backing-filename' = [IO.Path]::GetFullPath($sourceForRunner)
                    'backing-filename-format' = 'qcow2'
                }
            }
            else {
                $value = [pscustomobject][ordered]@{
                    format = 'qcow2'
                    'virtual-size' = [long]17179869184
                }
            }
            $stdout = $value | ConvertTo-Json -Compress
        }
        elseif ($command -ceq 'check') {
            $stdout = '{"corruptions":0,"leaks":0,"check-errors":0}'
        }
        else {
            return [pscustomobject]@{ ExitCode = 91; StdOut = ''; StdErr = "unexpected qemu-img command: $command" }
        }
        return [pscustomobject]@{ ExitCode = 0; StdOut = $stdout; StdErr = '' }
    }.GetNewClosure()

    $guestRunner = {
        param($context)
        if ($context.SeedServer.Address -cne '127.0.0.1') { throw 'seed listener was not loopback' }
        if ($context.SeedUrl -cne 'http://10.0.2.100:8000/') { throw 'unexpected NoCloud seed URL' }
        if ($context.GuestForward -notmatch '-tcp:127\.0\.0\.1:[0-9]+$') { throw 'seed forwarding is not loopback-only' }
        if (($context.Arguments -join ' ') -notmatch 'ds=nocloud;s=http://10\.0\.2\.100:8000/') { throw 'SMBIOS NoCloud configuration missing' }
        [pscustomobject][ordered]@{
            OsId = 'ubuntu'
            OsVersion = '24.04'
            CloudInitVersion = 'cloud-init 24.1 fixture'
            ToolsValidated = $true
            IdentityCleaned = $true
        }
    }

    return [pscustomobject]@{
        Root = $root
        Paths = $paths
        SourcePath = $sourcePath
        SourceDigest = $sourceDigest
        QemuStatusProvider = $qemuStatusProvider
        SourceProvider = $sourceProvider
        QemuImgRunner = $qemuImgRunner
        GuestRunner = $guestRunner
    }
}

function Remove-EzDarkFactoryBaseBuildFixture {
    param([object]$Fixture)
    if ($null -ne $Fixture) { Remove-EzDarkFactoryTestDirectory -Path $Fixture.Root }
}

Add-EzDarkFactoryTest -Name 'Base builder: verified staging is flattened, content-addressed, read-only and standalone' -ScriptBlock {
    $fixture = New-EzDarkFactoryBaseBuildFixture
    try {
        $sourceBefore = Get-EzDarkFactoryFileDigest -Path $fixture.SourcePath -Algorithm SHA256
        $result = Invoke-EzDarkFactoryBaseBuild -Root $fixture.Root -Accelerator tcg -BuildTimeoutSeconds 60 -QemuStatusProvider $fixture.QemuStatusProvider -SourceProvider $fixture.SourceProvider -QemuImgRunner $fixture.QemuImgRunner -GuestRunner $fixture.GuestRunner
        Assert-EzDarkFactoryTrue -Condition ($result.baseId -match '^base-[a-f0-9]{64}$')
        Assert-EzDarkFactoryEqual -Actual $result.baseId -Expected ('base-' + $result.sha256)
        Assert-EzDarkFactoryEqual -Actual $result.accelerator -Expected 'tcg'
        Assert-EzDarkFactoryTrue -Condition (-not $result.reused)
        Assert-EzDarkFactoryTrue -Condition (Test-Path -LiteralPath $result.path -PathType Leaf)
        Assert-EzDarkFactoryTrue -Condition (Test-Path -LiteralPath $result.manifestPath -PathType Leaf)
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryFileDigest -Path $fixture.SourcePath -Algorithm SHA256) -Expected $sourceBefore -Message 'Base build must never mutate the verified source image.'

        $accepted = Test-EzDarkFactoryPreparedBase -Root $fixture.Root -BaseId $result.baseId -QemuImgRunner $fixture.QemuImgRunner
        Assert-EzDarkFactoryTrue -Condition $accepted.ReadOnly
        Assert-EzDarkFactoryEqual -Actual $accepted.Manifest.source.imageSha256 -Expected $fixture.SourceDigest
        Assert-EzDarkFactoryEqual -Actual $accepted.Manifest.guest.osId -Expected 'ubuntu'
        Assert-EzDarkFactoryEqual -Actual $accepted.Manifest.guest.osVersion -Expected '24.04'
        Assert-EzDarkFactoryEqual -Actual $accepted.Manifest.build.accelerator -Expected 'tcg'
        Assert-EzDarkFactoryTrue -Condition ($accepted.Manifest.provisioning.digest -match '^[a-f0-9]{64}$')
        Assert-EzDarkFactoryEqual -Actual @(Get-ChildItem -LiteralPath $fixture.Paths.Bases -Directory -Filter '.build-*' -Force).Count -Expected 0
        Assert-EzDarkFactoryEqual -Actual @(Get-ChildItem -LiteralPath $fixture.Paths.Bases -Directory -Filter '.publish-*' -Force).Count -Expected 0
    }
    finally { Remove-EzDarkFactoryBaseBuildFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Base builder: identical final content reuses the content-addressed base without replacement' -ScriptBlock {
    $fixture = New-EzDarkFactoryBaseBuildFixture
    try {
        $first = Invoke-EzDarkFactoryBaseBuild -Root $fixture.Root -Accelerator tcg -BuildTimeoutSeconds 60 -QemuStatusProvider $fixture.QemuStatusProvider -SourceProvider $fixture.SourceProvider -QemuImgRunner $fixture.QemuImgRunner -GuestRunner $fixture.GuestRunner
        $firstManifest = [IO.File]::ReadAllText($first.manifestPath)
        $second = Invoke-EzDarkFactoryBaseBuild -Root $fixture.Root -Accelerator tcg -BuildTimeoutSeconds 60 -QemuStatusProvider $fixture.QemuStatusProvider -SourceProvider $fixture.SourceProvider -QemuImgRunner $fixture.QemuImgRunner -GuestRunner $fixture.GuestRunner
        Assert-EzDarkFactoryTrue -Condition $second.reused
        Assert-EzDarkFactoryEqual -Actual $second.baseId -Expected $first.baseId
        Assert-EzDarkFactoryEqual -Actual ([IO.File]::ReadAllText($first.manifestPath)) -Expected $firstManifest -Message 'Existing immutable base manifest must not be replaced.'
    }
    finally { Remove-EzDarkFactoryBaseBuildFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Base builder: guest provisioning failure never creates an authoritative base' -ScriptBlock {
    $fixture = New-EzDarkFactoryBaseBuildFixture
    try {
        $failedGuest = { param($context) throw 'synthetic cloud-init failure' }
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Invoke-EzDarkFactoryBaseBuild -Root $fixture.Root -Accelerator tcg -BuildTimeoutSeconds 60 -QemuStatusProvider $fixture.QemuStatusProvider -SourceProvider $fixture.SourceProvider -QemuImgRunner $fixture.QemuImgRunner -GuestRunner $failedGuest
        } -MessagePattern 'No authoritative base was promoted.*synthetic cloud-init failure' | Out-Null
        Assert-EzDarkFactoryEqual -Actual @(Get-ChildItem -LiteralPath $fixture.Paths.Bases -Directory -Filter 'base-*' -Force).Count -Expected 0
        $failed = @(Get-ChildItem -LiteralPath $fixture.Paths.Bases -Directory -Filter '.build-*' -Force)
        Assert-EzDarkFactoryEqual -Actual $failed.Count -Expected 1
        Assert-EzDarkFactoryTrue -Condition (Test-Path -LiteralPath (Join-Path $failed[0].FullName 'failure.json') -PathType Leaf)
        Assert-EzDarkFactoryTrue -Condition (Test-Path -LiteralPath (Join-Path $failed[0].FullName 'staging.qcow2') -PathType Leaf)
        Assert-EzDarkFactoryEqual -Actual @(Get-ChildItem -LiteralPath $fixture.Paths.Bases -Directory -Filter '.publish-*' -Force).Count -Expected 0
    }
    finally { Remove-EzDarkFactoryBaseBuildFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Base builder: flatten or integrity failure never becomes authoritative' -ScriptBlock {
    $fixture = New-EzDarkFactoryBaseBuildFixture
    try {
        $normalRunner = $fixture.QemuImgRunner
        $brokenRunner = {
            param($argumentList)
            $arguments = @($argumentList)
            if ($arguments[0] -ceq 'convert') {
                return [pscustomobject]@{ ExitCode = 82; StdOut = ''; StdErr = 'synthetic flatten failure' }
            }
            & $normalRunner $arguments
        }.GetNewClosure()

        Assert-EzDarkFactoryThrows -ScriptBlock {
            Invoke-EzDarkFactoryBaseBuild -Root $fixture.Root -Accelerator tcg -BuildTimeoutSeconds 60 -QemuStatusProvider $fixture.QemuStatusProvider -SourceProvider $fixture.SourceProvider -QemuImgRunner $brokenRunner -GuestRunner $fixture.GuestRunner
        } -MessagePattern 'No authoritative base was promoted.*flatten failure' | Out-Null
        Assert-EzDarkFactoryEqual -Actual @(Get-ChildItem -LiteralPath $fixture.Paths.Bases -Directory -Filter 'base-*' -Force).Count -Expected 0
    }
    finally { Remove-EzDarkFactoryBaseBuildFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Base builder: rejects unverified QEMU and source content before guest launch' -ScriptBlock {
    $fixture = New-EzDarkFactoryBaseBuildFixture
    try {
        $badQemu = { [pscustomobject]@{ Valid = $false; Reason = 'fixture provenance mismatch' } }
        $script:EzDarkFactoryGuestRan = $false
        $guest = { $script:EzDarkFactoryGuestRan = $true; throw 'must not launch' }
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Invoke-EzDarkFactoryBaseBuild -Root $fixture.Root -Accelerator tcg -BuildTimeoutSeconds 60 -QemuStatusProvider $badQemu -SourceProvider $fixture.SourceProvider -QemuImgRunner $fixture.QemuImgRunner -GuestRunner $guest
        } -MessagePattern 'validated managed QEMU.*provenance mismatch' | Out-Null
        Assert-EzDarkFactoryTrue -Condition (-not $script:EzDarkFactoryGuestRan)

        $badQemu = $fixture.QemuStatusProvider
        [IO.File]::AppendAllText($fixture.SourcePath, 'tamper')
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Invoke-EzDarkFactoryBaseBuild -Root $fixture.Root -Accelerator tcg -BuildTimeoutSeconds 60 -QemuStatusProvider $badQemu -SourceProvider $fixture.SourceProvider -QemuImgRunner $fixture.QemuImgRunner -GuestRunner $guest
        } -MessagePattern 'no longer matches the reviewed manifest' | Out-Null
        Assert-EzDarkFactoryTrue -Condition (-not $script:EzDarkFactoryGuestRan)
    }
    finally { Remove-EzDarkFactoryBaseBuildFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Base builder: standalone validation rejects an unexpected backing chain' -ScriptBlock {
    $fixture = New-EzDarkFactoryBaseBuildFixture
    try {
        $result = Invoke-EzDarkFactoryBaseBuild -Root $fixture.Root -Accelerator tcg -BuildTimeoutSeconds 60 -QemuStatusProvider $fixture.QemuStatusProvider -SourceProvider $fixture.SourceProvider -QemuImgRunner $fixture.QemuImgRunner -GuestRunner $fixture.GuestRunner
        $badInfo = {
            param($argumentList)
            $arguments = @($argumentList)
            if ($arguments[0] -ceq 'info') {
                $value = [pscustomobject][ordered]@{
                    format = 'qcow2'
                    'virtual-size' = [long]17179869184
                    'backing-filename' = '..\outside.qcow2'
                }
                return [pscustomobject]@{ ExitCode = 0; StdOut = ($value | ConvertTo-Json -Compress); StdErr = '' }
            }
            [pscustomobject]@{ ExitCode = 0; StdOut = '{}'; StdErr = '' }
        }
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Test-EzDarkFactoryPreparedBase -Root $fixture.Root -BaseId $result.baseId -QemuImgRunner $badInfo
        } -MessagePattern 'standalone with no backing file' | Out-Null
    }
    finally { Remove-EzDarkFactoryBaseBuildFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Base builder: guest serial facts require READY, tool validation, cleanup and matching build identity' -ScriptBlock {
    $module = Get-Module EzDarkFactory
    $buildId = '0123456789abcdef0123456789abcdef'
    $encode = { param($text) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text)) }
    $markerLines = @(
        ('EDF_BASE_BUILD_ID=' + $buildId)
        ('EDF_BASE_OS_ID_B64=' + (& $encode 'ubuntu'))
        ('EDF_BASE_OS_VERSION_B64=' + (& $encode '24.04'))
        ('EDF_BASE_CLOUD_INIT_B64=' + (& $encode 'cloud-init 24.1'))
        'EDF_BASE_TOOLS_OK=1'
        'EDF_BASE_CLEAN_OK=1'
        'EDF_BASE_READY=1'
    )
    $lines = [string]::Join([Environment]::NewLine, [string[]]$markerLines)
    $facts = & $module { param($text, $id) Get-EzDarkFactoryBaseGuestFacts -SerialText $text -BuildId $id } $lines $buildId
    Assert-EzDarkFactoryEqual -Actual $facts.OsId -Expected 'ubuntu'
    Assert-EzDarkFactoryEqual -Actual $facts.CloudInitVersion -Expected 'cloud-init 24.1'

    Assert-EzDarkFactoryThrows -ScriptBlock {
        & $module { param($text, $id) Get-EzDarkFactoryBaseGuestFacts -SerialText $text -BuildId $id } $lines 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    } -MessagePattern 'different build identity' | Out-Null
}

Add-EzDarkFactoryTest -Name 'Base builder: candidate validation fails before authoritative publication' -ScriptBlock {
    $fixture = New-EzDarkFactoryBaseBuildFixture
    try {
        $normalRunner = $fixture.QemuImgRunner
        $candidateRejectRunner = {
            param($argumentList)
            $arguments = @($argumentList)
            if ($arguments[0] -ceq 'info' -and [IO.Path]::GetFileName($arguments[$arguments.Count - 1]) -ceq 'base.qcow2') {
                $value = [pscustomobject][ordered]@{
                    format = 'qcow2'
                    'virtual-size' = [long]17179869184
                    'backing-filename' = '..\unexpected-backing.qcow2'
                }
                return [pscustomobject]@{ ExitCode = 0; StdOut = ($value | ConvertTo-Json -Compress); StdErr = '' }
            }
            & $normalRunner $arguments
        }.GetNewClosure()

        Assert-EzDarkFactoryThrows -ScriptBlock {
            Invoke-EzDarkFactoryBaseBuild -Root $fixture.Root -Accelerator tcg -BuildTimeoutSeconds 60 -QemuStatusProvider $fixture.QemuStatusProvider -SourceProvider $fixture.SourceProvider -QemuImgRunner $candidateRejectRunner -GuestRunner $fixture.GuestRunner
        } -MessagePattern 'No authoritative base was promoted.*standalone with no backing file' | Out-Null

        Assert-EzDarkFactoryEqual -Actual @(Get-ChildItem -LiteralPath $fixture.Paths.Bases -Directory -Filter 'base-*' -Force).Count -Expected 0
        Assert-EzDarkFactoryEqual -Actual @(Get-ChildItem -LiteralPath $fixture.Paths.Bases -Directory -Filter '.publish-*' -Force).Count -Expected 0
        Assert-EzDarkFactoryEqual -Actual @(Get-ChildItem -LiteralPath $fixture.Paths.Bases -Directory -Filter '.build-*' -Force).Count -Expected 1
    }
    finally { Remove-EzDarkFactoryBaseBuildFixture $fixture }
}
