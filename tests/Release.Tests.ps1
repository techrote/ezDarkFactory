Add-EzDarkFactoryTest -Name 'Development source: public version and module metadata distinguish EDF from EzVM v0.1.0' -ScriptBlock {
    $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $script:EzDarkFactoryRepositoryRoot 'src/EzDarkFactory/EzDarkFactory.psd1')
    Assert-EzDarkFactoryEqual -Actual ([string]$manifest.ModuleVersion) -Expected '0.0.0'
    Assert-EzDarkFactoryEqual -Actual ([string]$manifest.PrivateData.EzDarkFactoryVersion) -Expected '0.0.0-dev'
    Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryVersion) -Expected '0.0.0-dev'
}

Add-EzDarkFactoryTest -Name 'Development source: recorded pins and WHPX limitation' -ScriptBlock {
    $root = $script:EzDarkFactoryRepositoryRoot
    $qemu = Get-Content -LiteralPath (Join-Path $root 'manifests/qemu-windows.json') -Raw | ConvertFrom-Json
    $ubuntu = Get-Content -LiteralPath (Join-Path $root 'manifests/ubuntu-noble-amd64.json') -Raw | ConvertFrom-Json
    $notes = [IO.File]::ReadAllText((Join-Path $root 'docs/DEVELOPMENT.md'))
    foreach ($value in @(
        [string]$qemu.qemu.version,
        [string]$qemu.qemu.providerBuild,
        [string]$qemu.qemu.digest,
        [string]$qemu.extractor.version,
        [string]$qemu.extractor.bootstrap.digest,
        [string]$qemu.extractor.package.digest,
        [string]$ubuntu.publication,
        [string]$ubuntu.sha256
    )) {
        Assert-EzDarkFactoryTrue -Condition $notes.Contains($value) -Message ('Release notes omitted reviewed pin: ' + $value)
    }
    Assert-EzDarkFactoryTrue -Condition ($notes -match 'WHPX.*UNMEASURED') -Message 'Development source must explicitly classify WHPX as UNMEASURED.'
}

Add-EzDarkFactoryTest -Name 'Development source: deterministic source-only package is self-describing and executable' -ScriptBlock {
    $first = New-EzDarkFactoryTestDirectory -Prefix 'release package one'
    $second = New-EzDarkFactoryTestDirectory -Prefix 'release package two'
    $extract = New-EzDarkFactoryTestDirectory -Prefix 'release extracted'
    try {
        $scriptPath = Join-Path $script:EzDarkFactoryRepositoryRoot 'scripts/New-EzDarkFactoryReleasePackage.ps1'
        $one = & $scriptPath -Root $script:EzDarkFactoryRepositoryRoot -OutputDirectory $first -Version '0.0.0-dev'
        $two = & $scriptPath -Root $script:EzDarkFactoryRepositoryRoot -OutputDirectory $second -Version '0.0.0-dev'

        Assert-EzDarkFactoryEqual -Actual $one.Version -Expected '0.0.0-dev'
        Assert-EzDarkFactoryEqual -Actual $one.SourceCommit -Expected $two.SourceCommit
        Assert-EzDarkFactoryEqual -Actual $one.SourceTree -Expected $two.SourceTree
        Assert-EzDarkFactoryEqual -Actual $one.PackageSha256 -Expected $two.PackageSha256
        Assert-EzDarkFactoryEqual -Actual (Get-FileHash -LiteralPath $one.PackagePath -Algorithm SHA256).Hash.ToLowerInvariant() -Expected $one.PackageSha256

        $sidecar = [IO.File]::ReadAllText($one.ChecksumPath).Trim()
        Assert-EzDarkFactoryEqual -Actual $sidecar -Expected ($one.PackageSha256 + '  ezdarkfactory-0.0.0-dev.zip')

        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        $archive = [IO.Compression.ZipFile]::OpenRead($one.PackagePath)
        try {
            $names = @($archive.Entries | ForEach-Object { $_.FullName })
            foreach ($required in @(
                'ezdarkfactory-0.0.0-dev/ezdarkfactory.ps1',
                'ezdarkfactory-0.0.0-dev/README.md',
                'ezdarkfactory-0.0.0-dev/THIRD-PARTY-NOTICES.md',
                'ezdarkfactory-0.0.0-dev/docs/GETTING-STARTED.md',
                'ezdarkfactory-0.0.0-dev/docs/DEVELOPMENT.md',
                'ezdarkfactory-0.0.0-dev/docs/WHPX-QUALIFICATION.md',
                'ezdarkfactory-0.0.0-dev/manifests/qemu-windows.json',
                'ezdarkfactory-0.0.0-dev/manifests/ubuntu-noble-amd64.json',
                'ezdarkfactory-0.0.0-dev/RELEASE-METADATA.json'
            )) {
                Assert-EzDarkFactoryTrue -Condition ($names -ccontains $required) -Message ('Release package omitted ' + $required)
            }
            foreach ($name in $names) {
                Assert-EzDarkFactoryTrue -Condition ($name.StartsWith('ezdarkfactory-0.0.0-dev/', [StringComparison]::Ordinal)) -Message 'Release ZIP contains content outside its versioned root.'
                Assert-EzDarkFactoryTrue -Condition ($name -notmatch '/(?:runtime|cache|artifacts|tests|scripts|\.github)/') -Message ('Release ZIP contains generated/test/workflow/tooling content: ' + $name)
                Assert-EzDarkFactoryTrue -Condition ($name -notmatch '(?i)\.(?:qcow2?|img|iso|vhdx?|vmdk|vdi|raw|exe|dll|msi|zip|7z|pem|key|pfx|token)$') -Message ('Release ZIP contains a binary/secret-like payload: ' + $name)
            }

            $metadataEntry = @($archive.Entries | Where-Object { $_.FullName -ceq 'ezdarkfactory-0.0.0-dev/RELEASE-METADATA.json' })
            Assert-EzDarkFactoryEqual -Actual $metadataEntry.Count -Expected 1
            $reader = New-Object IO.StreamReader($metadataEntry[0].Open(), (New-Object Text.UTF8Encoding($false, $true)))
            try { $metadata = $reader.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop }
            finally { $reader.Dispose() }
            Assert-EzDarkFactoryEqual -Actual $metadata.version -Expected '0.0.0-dev'
            Assert-EzDarkFactoryEqual -Actual $metadata.sourceCommit -Expected $one.SourceCommit
            Assert-EzDarkFactoryEqual -Actual $metadata.sourceTree -Expected $one.SourceTree
            Assert-EzDarkFactoryEqual -Actual $metadata.thirdPartyBinariesIncluded -Expected $false
            Assert-EzDarkFactoryEqual -Actual $metadata.distributableRelease -Expected $false
            Assert-EzDarkFactoryEqual -Actual $metadata.qualification -Expected 'SOURCE-FAST-CI-ONLY'
            Assert-EzDarkFactoryEqual -Actual @($metadata.files).Count -Expected $one.FileCount
        }
        finally { $archive.Dispose() }

        [IO.Compression.ZipFile]::ExtractToDirectory($one.PackagePath, $extract)
        $packageRoot = Join-Path $extract 'ezdarkfactory-0.0.0-dev'
        $entry = "'" + (Join-Path $packageRoot 'ezdarkfactory.ps1').Replace("'", "''") + "'"
        $command = '$value = & ' + $entry + ' version -Json | ConvertFrom-Json; if (-not $value.success -or $value.data.version -cne ''0.0.0-dev'') { exit 93 }; [Console]::Write($value.data.version); exit 0'
        $result = Invoke-EzDarkFactoryTestPowerShell -CommandText $command -WorkingDirectory $packageRoot
        Assert-EzDarkFactoryEqual -Actual $result.ExitCode -Expected 0
        Assert-EzDarkFactoryEqual -Actual $result.StandardOutput -Expected '0.0.0-dev'
        Assert-EzDarkFactoryEqual -Actual $result.StandardError -Expected ''
    }
    finally {
        Remove-EzDarkFactoryTestDirectory $first
        Remove-EzDarkFactoryTestDirectory $second
        Remove-EzDarkFactoryTestDirectory $extract
    }
}


Add-EzDarkFactoryTest -Name 'Release: developer source packaging cannot publish or impersonate EDF-012 acceptance' -ScriptBlock {
    $root = $script:EzDarkFactoryRepositoryRoot
    $publisherPath = Join-Path $root 'scripts/Publish-EzDarkFactoryGitHubRelease.ps1'
    $publisher = [IO.File]::ReadAllText($publisherPath)
    Assert-EzDarkFactoryTrue -Condition ($publisher.Contains("EDF-012 release qualification has not been completed"))
    Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root '.github/workflows/release.yml')))
    Assert-EzDarkFactoryTrue -Condition ($publisher.Contains('Release checksum sidecar does not match the exact ZIP bytes'))
    Assert-EzDarkFactoryTrue -Condition ($publisher.Contains('draft = $true'))
    $packager = [IO.File]::ReadAllText((Join-Path $root 'scripts/New-EzDarkFactoryReleasePackage.ps1'))
    Assert-EzDarkFactoryTrue -Condition ($packager.Contains("Only the EDF-002 unqualified development source ZIP"))
    Assert-EzDarkFactoryTrue -Condition ($packager.Contains('distributableRelease = $false'))
}
