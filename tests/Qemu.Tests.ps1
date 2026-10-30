function New-EzDarkFactoryQemuFixture {
    param([string]$Root)

    $qemuPayload = Join-Path $Root 'qemu-fixture.bin'
    $bootstrapPayload = Join-Path $Root '7zr-fixture.bin'
    $packagePayload = Join-Path $Root '7zip-package-fixture.bin'
    [IO.File]::WriteAllBytes($qemuPayload, [Text.Encoding]::UTF8.GetBytes('synthetic-qemu-installer'))
    [IO.File]::WriteAllBytes($bootstrapPayload, [Text.Encoding]::UTF8.GetBytes('synthetic-7zr'))
    [IO.File]::WriteAllBytes($packagePayload, [Text.Encoding]::UTF8.GetBytes('synthetic-full-7zip'))

    $manifest = [pscustomobject][ordered]@{
        schemaVersion = 1
        provider = 'Synthetic Stefan Weil fixture'
        qemu = [pscustomobject][ordered]@{
            version = '11.1.0'
            providerBuild = '20260811'
            url = 'https://qemu.weilnetz.de/w64/qemu-fixture.exe'
            filename = 'qemu-fixture.exe'
            digestAlgorithm = 'SHA512'
            digest = Get-EzDarkFactoryFileDigest -Path $qemuPayload -Algorithm SHA512
            sizeBytes = [long](Get-Item -LiteralPath $qemuPayload).Length
            expectedVersionPrefix = '11.1.0'
        }
        extractor = [pscustomobject][ordered]@{
            version = '26.04'
            bootstrap = [pscustomobject][ordered]@{
                url = 'https://github.com/ip7z/7zip/releases/download/26.04/7zr-fixture.exe'
                filename = '7zr-fixture.exe'
                digestAlgorithm = 'SHA256'
                digest = Get-EzDarkFactoryFileDigest -Path $bootstrapPayload -Algorithm SHA256
                sizeBytes = [long](Get-Item -LiteralPath $bootstrapPayload).Length
            }
            package = [pscustomobject][ordered]@{
                url = 'https://github.com/ip7z/7zip/releases/download/26.04/7zip-package-fixture.exe'
                filename = '7zip-package-fixture.exe'
                digestAlgorithm = 'SHA256'
                digest = Get-EzDarkFactoryFileDigest -Path $packagePayload -Algorithm SHA256
                sizeBytes = [long](Get-Item -LiteralPath $packagePayload).Length
            }
        }
    }
    $manifestPath = Join-Path $Root 'synthetic-qemu-manifest.json'
    Write-EzDarkFactoryJson -Path $manifestPath -Value $manifest

    return [pscustomobject]@{
        ManifestPath = $manifestPath
        QemuPayload = $qemuPayload
        BootstrapPayload = $bootstrapPayload
        PackagePayload = $packagePayload
    }
}

function New-EzDarkFactoryQemuFixtureHooks {
    param([object]$Fixture)

    $qemuPayload = $Fixture.QemuPayload
    $bootstrapPayload = $Fixture.BootstrapPayload
    $packagePayload = $Fixture.PackagePayload
    $downloader = {
        param($url, $destination)
        if ($url -match 'qemu-fixture') { $source = $qemuPayload }
        elseif ($url -match '7zr-fixture') { $source = $bootstrapPayload }
        elseif ($url -match '7zip-package-fixture') { $source = $packagePayload }
        else { throw "Unexpected fixture URL: $url" }
        [IO.File]::Copy($source, $destination, $false)
    }.GetNewClosure()

    $extractor = {
        param($bootstrap, $package, $destination, $expectedVersion)
        [void][IO.Directory]::CreateDirectory($destination)
        $exe = Join-Path $destination '7z.exe'
        [IO.File]::WriteAllText($exe, 'fixture 7z executable')
        [IO.File]::WriteAllText((Join-Path $destination '7z.dll'), 'fixture 7z library')
        return [pscustomobject]@{ SevenZipExe = $exe; VersionOutput = "7-Zip $expectedVersion (x64) fixture" }
    }

    $expander = {
        param($sevenZipExe, $installer, $destination)
        [void][IO.Directory]::CreateDirectory($destination)
        [void][IO.Directory]::CreateDirectory((Join-Path $destination 'share'))
        [void][IO.Directory]::CreateDirectory((Join-Path $destination 'lib'))
        foreach ($name in @('qemu-system-x86_64.exe', 'qemu-img.exe', 'COPYING', 'COPYING.LIB')) {
            [IO.File]::WriteAllText((Join-Path $destination $name), "fixture $name")
        }
        return [pscustomobject]@{
            Root = $destination
            QemuSystem = Join-Path $destination 'qemu-system-x86_64.exe'
            QemuImg = Join-Path $destination 'qemu-img.exe'
        }
    }

    $probe = {
        param($runtimeRoot, $expectedVersion)
        return [pscustomobject]@{
            QemuSystemVersion = "QEMU emulator version $expectedVersion (fixture)"
            QemuImgVersion = "qemu-img version $expectedVersion (fixture)"
        }
    }

    return [pscustomobject]@{
        Downloader = $downloader
        ExtractorBootstrapper = $extractor
        QemuExpander = $expander
        PayloadProbe = $probe
    }
}

Add-EzDarkFactoryTest -Name 'QEMU: checked-in manifest pins reviewed provider artifacts exactly' -ScriptBlock {
    $manifest = Get-EzDarkFactoryQemuManifest -Root $script:EzDarkFactoryRepositoryRoot
    Assert-EzDarkFactoryEqual -Actual $manifest.qemu.version -Expected '11.1.0'
    Assert-EzDarkFactoryEqual -Actual $manifest.qemu.providerBuild -Expected '20260811'
    Assert-EzDarkFactoryEqual -Actual $manifest.qemu.filename -Expected 'qemu-w64-setup-20260811.exe'
    Assert-EzDarkFactoryEqual -Actual $manifest.qemu.digestAlgorithm -Expected 'SHA512'
    Assert-EzDarkFactoryEqual -Actual $manifest.qemu.digest -Expected '5bcf9eed634e8575a37b74f445af41a2fe4106da512d0c30c368301d4c105037fdfab40a5287367a28a957624cddebbc8c07e16c88ab6634f554cdf3d16bf543'
    Assert-EzDarkFactoryEqual -Actual $manifest.extractor.version -Expected '26.04'
    Assert-EzDarkFactoryEqual -Actual $manifest.extractor.bootstrap.digest -Expected '256feca8e274e5da655e2a284fabafd9f554365eb164862089dacd4e8276d282'
    Assert-EzDarkFactoryEqual -Actual $manifest.extractor.package.digest -Expected 'd54bf805f9f3704d1e8db2fa3498ae7ef2df0312b40b558e7c71c734430a665d'
}

$qemuWindowsSkip = $null
if (-not $script:EzDarkFactoryIsWindowsHost) {
    $qemuWindowsSkip = 'Portable QEMU bootstrap targets Windows x86-64; both supported Windows CI lanes execute this test.'
}

Add-EzDarkFactoryTest -Name 'QEMU: fixture bootstrap promotes verified runtime and second run is idempotent' -SkipReason $qemuWindowsSkip -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'QEMU portable [root] with spaces'
    try {
        $fixture = New-EzDarkFactoryQemuFixture -Root $root
        $hooks = New-EzDarkFactoryQemuFixtureHooks -Fixture $fixture
        $arguments = @{
            Root = $root
            ManifestPath = $fixture.ManifestPath
            Downloader = $hooks.Downloader
            ExtractorBootstrapper = $hooks.ExtractorBootstrapper
            QemuExpander = $hooks.QemuExpander
            PayloadProbe = $hooks.PayloadProbe
        }
        $first = Install-EzDarkFactoryQemuRuntime @arguments
        Assert-EzDarkFactoryTrue -Condition (-not $first.idempotent)
        Assert-EzDarkFactoryTrue -Condition $first.downloaded
        Assert-EzDarkFactoryTrue -Condition ([IO.Path]::IsPathRooted($first.qemuSystem))
        Assert-EzDarkFactoryTrue -Condition ($first.qemuSystem.StartsWith([IO.Path]::GetFullPath($root), [StringComparison]::OrdinalIgnoreCase))
        Assert-EzDarkFactoryTrue -Condition (Test-Path -LiteralPath (Join-Path $first.runtimePath 'ezdarkfactory-provenance.json') -PathType Leaf)

        $mustNotDownload = { throw 'idempotent bootstrap must not redownload' }
        $arguments.Downloader = $mustNotDownload
        $second = Install-EzDarkFactoryQemuRuntime @arguments
        Assert-EzDarkFactoryTrue -Condition $second.idempotent
        Assert-EzDarkFactoryTrue -Condition (-not $second.downloaded)
        Assert-EzDarkFactoryEqual -Actual $second.runtimePath -Expected $first.runtimePath
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'QEMU: digest mismatch fails before extraction and does not promote runtime' -SkipReason $qemuWindowsSkip -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'QEMU digest rejection'
    try {
        $fixture = New-EzDarkFactoryQemuFixture -Root $root
        $manifest = Read-EzDarkFactoryJson -Path $fixture.ManifestPath
        $manifest.qemu.digest = ('0' * 128)
        Write-EzDarkFactoryJson -Path $fixture.ManifestPath -Value $manifest
        $hooks = New-EzDarkFactoryQemuFixtureHooks -Fixture $fixture
        $script:EzDarkFactoryExtractorWasCalled = $false
        $mustNotExtract = {
            $script:EzDarkFactoryExtractorWasCalled = $true
            throw 'extractor should not run'
        }
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Install-EzDarkFactoryQemuRuntime -Root $root -ManifestPath $fixture.ManifestPath -Downloader $hooks.Downloader -ExtractorBootstrapper $mustNotExtract -QemuExpander $hooks.QemuExpander -PayloadProbe $hooks.PayloadProbe
        } -MessagePattern 'failed SHA512 verification' | Out-Null
        Assert-EzDarkFactoryTrue -Condition (-not $script:EzDarkFactoryExtractorWasCalled)
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Get-EzDarkFactoryPaths -Root $root).Qemu))
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'QEMU: unexpected extraction layout fails closed without runtime promotion' -SkipReason $qemuWindowsSkip -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'QEMU malformed extraction'
    try {
        $fixture = New-EzDarkFactoryQemuFixture -Root $root
        $hooks = New-EzDarkFactoryQemuFixtureHooks -Fixture $fixture
        $badExpander = {
            param($sevenZipExe, $installer, $destination)
            [void][IO.Directory]::CreateDirectory($destination)
            [IO.File]::WriteAllText((Join-Path $destination 'not-qemu.txt'), 'malformed fixture')
            return [pscustomobject]@{ Root = $destination }
        }
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Install-EzDarkFactoryQemuRuntime -Root $root -ManifestPath $fixture.ManifestPath -Downloader $hooks.Downloader -ExtractorBootstrapper $hooks.ExtractorBootstrapper -QemuExpander $badExpander -PayloadProbe $hooks.PayloadProbe
        } -MessagePattern 'required managed executables' | Out-Null
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Get-EzDarkFactoryPaths -Root $root).Qemu))
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'QEMU: payload probe must confirm reviewed version before promotion' -SkipReason $qemuWindowsSkip -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'QEMU version mismatch'
    try {
        $fixture = New-EzDarkFactoryQemuFixture -Root $root
        $hooks = New-EzDarkFactoryQemuFixtureHooks -Fixture $fixture
        $badProbe = {
            [pscustomobject]@{
                QemuSystemVersion = 'QEMU emulator version 99.0.0 fixture'
                QemuImgVersion = 'qemu-img version 99.0.0 fixture'
            }
        }
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Install-EzDarkFactoryQemuRuntime -Root $root -ManifestPath $fixture.ManifestPath -Downloader $hooks.Downloader -ExtractorBootstrapper $hooks.ExtractorBootstrapper -QemuExpander $hooks.QemuExpander -PayloadProbe $badProbe
        } -MessagePattern 'reviewed version prefix' | Out-Null
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Get-EzDarkFactoryPaths -Root $root).Qemu))
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'QEMU: managed tool resolution is absolute and independent of PATH and registry' -SkipReason $qemuWindowsSkip -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'QEMU no PATH dependency'
    $oldPath = $env:PATH
    try {
        $fixture = New-EzDarkFactoryQemuFixture -Root $root
        [IO.File]::Copy($fixture.ManifestPath, (Get-EzDarkFactoryPaths -Root $root).QemuManifest, $true)
        $hooks = New-EzDarkFactoryQemuFixtureHooks -Fixture $fixture
        $null = Install-EzDarkFactoryQemuRuntime -Root $root -ManifestPath $fixture.ManifestPath -Downloader $hooks.Downloader -ExtractorBootstrapper $hooks.ExtractorBootstrapper -QemuExpander $hooks.QemuExpander -PayloadProbe $hooks.PayloadProbe
        $env:PATH = ''
        $system = Get-EzDarkFactoryQemuToolPath -Name 'qemu-system-x86_64.exe' -Root $root
        $image = Get-EzDarkFactoryQemuToolPath -Name 'qemu-img.exe' -Root $root
        Assert-EzDarkFactoryTrue -Condition ([IO.Path]::IsPathRooted($system))
        Assert-EzDarkFactoryTrue -Condition ([IO.Path]::IsPathRooted($image))
        $source = [IO.File]::ReadAllText((Join-Path $script:EzDarkFactoryRepositoryRoot 'src/EzDarkFactory/Qemu.ps1'))
        Assert-EzDarkFactoryTrue -Condition ($source -notmatch '(?i)env:PATH|HKLM:|Registry::|Set-ItemProperty') -Message 'Managed QEMU code must not depend on PATH or registry mutation.'
    }
    finally {
        $env:PATH = $oldPath
        Remove-EzDarkFactoryTestDirectory -Path $root
    }
}

Add-EzDarkFactoryTest -Name 'QEMU: strict manifest rejects wrong provider host, digest algorithm and unknown fields' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'QEMU manifest validation'
    try {
        $fixture = New-EzDarkFactoryQemuFixture -Root $root
        $manifest = Read-EzDarkFactoryJson -Path $fixture.ManifestPath
        $manifest.qemu.url = 'https://example.invalid/qemu.exe'
        Write-EzDarkFactoryJson -Path $fixture.ManifestPath -Value $manifest
        Assert-EzDarkFactoryThrows -ScriptBlock { Get-EzDarkFactoryQemuManifest -Root $root -ManifestPath $fixture.ManifestPath } -MessagePattern 'reviewed provider host' | Out-Null

        $fixture = New-EzDarkFactoryQemuFixture -Root $root
        $manifest = Read-EzDarkFactoryJson -Path $fixture.ManifestPath
        $manifest.qemu.digestAlgorithm = 'SHA256'
        Write-EzDarkFactoryJson -Path $fixture.ManifestPath -Value $manifest
        Assert-EzDarkFactoryThrows -ScriptBlock { Get-EzDarkFactoryQemuManifest -Root $root -ManifestPath $fixture.ManifestPath } -MessagePattern "must be 'SHA512'" | Out-Null

        $fixture = New-EzDarkFactoryQemuFixture -Root $root
        $manifest = Read-EzDarkFactoryJson -Path $fixture.ManifestPath
        $manifest | Add-Member -NotePropertyName surprise -NotePropertyValue 'no'
        Write-EzDarkFactoryJson -Path $fixture.ManifestPath -Value $manifest
        Assert-EzDarkFactoryThrows -ScriptBlock { Get-EzDarkFactoryQemuManifest -Root $root -ManifestPath $fixture.ManifestPath } -MessagePattern 'unknown field' | Out-Null
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'QEMU: atomic runtime promotion retries transient Windows-style locks without copy fallback' -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'qemu atomic promotion retry'
    try {
        $source = Join-Path $root 'stage'
        $destination = Join-Path $root 'runtime'
        [void][IO.Directory]::CreateDirectory($source)
        [IO.File]::WriteAllText((Join-Path $source 'marker.txt'), 'fixture')
        $state = [pscustomobject]@{ Count = 0 }
        $mover = {
            param($from, $to)
            $state.Count++
            if ($state.Count -lt 3) {
                throw [UnauthorizedAccessException]::new('synthetic transient scanner lock')
            }
            [IO.Directory]::Move($from, $to)
        }.GetNewClosure()

        $module = Get-Module EzDarkFactory
        & $module {
            param($from, $to, $move)
            Move-EzDarkFactoryDirectoryAtomically -Source $from -Destination $to -Attempts 4 -DelayMilliseconds 0 -Mover $move
        } $source $destination $mover

        Assert-EzDarkFactoryEqual -Actual $state.Count -Expected 3
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath $source))
        Assert-EzDarkFactoryTrue -Condition (Test-Path -LiteralPath (Join-Path $destination 'marker.txt') -PathType Leaf)
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}
