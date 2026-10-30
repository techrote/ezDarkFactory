function New-EzDarkFactorySourceImageFixture {
    param(
        [string]$Root,
        [string]$Payload = 'synthetic Ubuntu cloud image fixture',
        [string]$Release = '24.04',
        [string]$Codename = 'noble',
        [string]$Architecture = 'amd64',
        [string]$Publication = '20260926',
        [string]$Url,
        [string]$FileName = 'ubuntu-24.04-server-cloudimg-amd64.img'
    )

    $payloadPath = Join-Path $Root 'synthetic-source-payload.bin'
    [IO.File]::WriteAllBytes($payloadPath, [Text.Encoding]::UTF8.GetBytes($Payload))
    $digest = Get-EzDarkFactoryFileDigest -Path $payloadPath -Algorithm SHA256
    if (-not $PSBoundParameters.ContainsKey('Url')) {
        $Url = 'https://cloud-images.ubuntu.com/releases/noble/release-' + $Publication + '/' + $FileName
    }
    $manifestPath = Join-Path $Root 'synthetic-ubuntu-manifest.json'
    $manifest = [pscustomobject][ordered]@{
        schemaVersion = 1
        provider = 'Canonical Ubuntu Cloud Images'
        release = $Release
        codename = $Codename
        architecture = $Architecture
        publication = $Publication
        url = $Url
        filename = $FileName
        sha256 = $digest
    }
    Write-EzDarkFactoryJson -Path $manifestPath -Value $manifest -SchemaVersion 1
    return [pscustomobject]@{ PayloadPath = $payloadPath; Digest = $digest; ManifestPath = $manifestPath }
}

Add-EzDarkFactoryTest -Name 'Source image: checked-in Noble manifest is exact, dated and reviewed' -ScriptBlock {
    $manifest = Get-EzDarkFactorySourceImageManifest -Root $script:EzDarkFactoryRepositoryRoot
    Assert-EzDarkFactoryEqual -Actual $manifest.release -Expected '24.04'
    Assert-EzDarkFactoryEqual -Actual $manifest.codename -Expected 'noble'
    Assert-EzDarkFactoryEqual -Actual $manifest.architecture -Expected 'amd64'
    Assert-EzDarkFactoryEqual -Actual $manifest.publication -Expected '20260926'
    Assert-EzDarkFactoryEqual -Actual $manifest.filename -Expected 'ubuntu-24.04-server-cloudimg-amd64.img'
    Assert-EzDarkFactoryEqual -Actual $manifest.sha256 -Expected '6a81c37564db9b1ee84e141922625e1d7c5b389b99bb3c572e0243607d5bb4d2'
    Assert-EzDarkFactoryTrue -Condition ($manifest.url -match '/release-20260926/') -Message 'Manifest must not follow a mutable current alias.'
}

Add-EzDarkFactoryTest -Name 'Source image: acquisition verifies fixture content, records provenance and never mutates source' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'source image acquire with spaces'
    try {
        $fixture = New-EzDarkFactorySourceImageFixture -Root $root
        $before = [IO.File]::ReadAllBytes($fixture.PayloadPath)
        $payloadPath = $fixture.PayloadPath
        $downloader = { param($url, $temporary) [IO.File]::Copy($payloadPath, $temporary, $false) }.GetNewClosure()
        $result = Invoke-EzDarkFactorySourceImageAcquire -Root $root -ManifestPath $fixture.ManifestPath -Downloader $downloader

        Assert-EzDarkFactoryTrue -Condition $result.downloaded
        Assert-EzDarkFactoryTrue -Condition $result.immutable
        Assert-EzDarkFactoryEqual -Actual $result.sha256 -Expected $fixture.Digest
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryFileDigest -Path $result.path -Algorithm SHA256) -Expected $fixture.Digest
        Assert-EzDarkFactoryEqual -Actual ([Convert]::ToBase64String([IO.File]::ReadAllBytes($fixture.PayloadPath))) -Expected ([Convert]::ToBase64String($before))
        Assert-EzDarkFactoryTrue -Condition (Test-Path -LiteralPath $result.provenancePath -PathType Leaf)
        $provenance = Read-EzDarkFactoryJson -Path $result.provenancePath
        Assert-EzDarkFactoryEqual -Actual $provenance.sha256 -Expected $fixture.Digest
        Assert-EzDarkFactoryEqual -Actual $provenance.architecture -Expected 'amd64'
        Assert-EzDarkFactoryTrue -Condition ($provenance.recordedAt -is [string])
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Source image: cached-good acquisition is idempotent and preserves provenance' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'source image cache idempotent'
    try {
        $fixture = New-EzDarkFactorySourceImageFixture -Root $root
        $payloadPath = $fixture.PayloadPath
        $downloader = { param($url, $temporary) [IO.File]::Copy($payloadPath, $temporary, $false) }.GetNewClosure()
        $first = Invoke-EzDarkFactorySourceImageAcquire -Root $root -ManifestPath $fixture.ManifestPath -Downloader $downloader
        $provenanceBefore = [IO.File]::ReadAllText($first.provenancePath)
        $mustNotDownload = { throw 'valid cached source must not redownload' }
        $second = Invoke-EzDarkFactorySourceImageAcquire -Root $root -ManifestPath $fixture.ManifestPath -Downloader $mustNotDownload
        Assert-EzDarkFactoryTrue -Condition (-not $second.downloaded)
        Assert-EzDarkFactoryEqual -Actual $second.path -Expected $first.path
        Assert-EzDarkFactoryEqual -Actual ([IO.File]::ReadAllText($second.provenancePath)) -Expected $provenanceBefore
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Source image: corrupt cached image is rejected and replaced only by matching content' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'source image corrupt cache'
    try {
        $fixture = New-EzDarkFactorySourceImageFixture -Root $root
        $paths = Get-EzDarkFactoryPaths -Root $root
        [void][IO.Directory]::CreateDirectory($paths.SourceImages)
        $authoritative = Join-Path $paths.SourceImages 'ubuntu-24.04-server-cloudimg-amd64.img'
        [IO.File]::WriteAllText($authoritative, 'corrupt cache')
        $payloadPath = $fixture.PayloadPath
        $downloader = { param($url, $temporary) [IO.File]::Copy($payloadPath, $temporary, $false) }.GetNewClosure()
        $result = Invoke-EzDarkFactorySourceImageAcquire -Root $root -ManifestPath $fixture.ManifestPath -Downloader $downloader
        Assert-EzDarkFactoryTrue -Condition $result.downloaded
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryFileDigest -Path $authoritative -Algorithm SHA256) -Expected $fixture.Digest
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Source image: failed recovery of a corrupt cache leaves no authoritative image' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'source image failed recovery'
    try {
        $fixture = New-EzDarkFactorySourceImageFixture -Root $root
        $paths = Get-EzDarkFactoryPaths -Root $root
        [void][IO.Directory]::CreateDirectory($paths.SourceImages)
        $authoritative = Join-Path $paths.SourceImages 'ubuntu-24.04-server-cloudimg-amd64.img'
        [IO.File]::WriteAllText($authoritative, 'corrupt cache')
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Invoke-EzDarkFactorySourceImageAcquire -Root $root -ManifestPath $fixture.ManifestPath -Downloader { throw 'interrupted source transfer' }
        } -MessagePattern 'interrupted source transfer' | Out-Null
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath $authoritative))
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Source image: manifest rejects release, architecture, mutable URL and unknown fields' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'source manifest validation'
    try {
        $wrongArch = New-EzDarkFactorySourceImageFixture -Root $root -Architecture 'arm64'
        Assert-EzDarkFactoryThrows -ScriptBlock { Get-EzDarkFactorySourceImageManifest -Root $root -ManifestPath $wrongArch.ManifestPath } -MessagePattern "architecture must be 'amd64'" | Out-Null

        $wrongRelease = New-EzDarkFactorySourceImageFixture -Root $root -Release '24.10'
        Assert-EzDarkFactoryThrows -ScriptBlock { Get-EzDarkFactorySourceImageManifest -Root $root -ManifestPath $wrongRelease.ManifestPath } -MessagePattern '24.04 LTS Noble' | Out-Null

        $mutable = New-EzDarkFactorySourceImageFixture -Root $root -Url 'https://cloud-images.ubuntu.com/releases/noble/current/ubuntu-24.04-server-cloudimg-amd64.img'
        Assert-EzDarkFactoryThrows -ScriptBlock { Get-EzDarkFactorySourceImageManifest -Root $root -ManifestPath $mutable.ManifestPath } -MessagePattern 'dated Noble release' | Out-Null

        $value = Read-EzDarkFactoryJson -Path $wrongArch.ManifestPath
        $value | Add-Member -NotePropertyName unexpected -NotePropertyValue 'no'
        Write-EzDarkFactoryJson -Path $wrongArch.ManifestPath -Value $value
        Assert-EzDarkFactoryThrows -ScriptBlock { Get-EzDarkFactorySourceImageManifest -Root $root -ManifestPath $wrongArch.ManifestPath } -MessagePattern 'unknown field' | Out-Null
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Source image: malformed old provenance is replaced rather than crashing strict mode' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'source provenance recovery'
    try {
        $fixture = New-EzDarkFactorySourceImageFixture -Root $root
        $payloadPath = $fixture.PayloadPath
        $downloader = { param($url, $temporary) [IO.File]::Copy($payloadPath, $temporary, $false) }.GetNewClosure()
        $first = Invoke-EzDarkFactorySourceImageAcquire -Root $root -ManifestPath $fixture.ManifestPath -Downloader $downloader
        Write-EzDarkFactoryJson -Path $first.provenancePath -Value ([pscustomobject][ordered]@{ schemaVersion = 1; legacy = 'incomplete' })
        $second = Invoke-EzDarkFactorySourceImageAcquire -Root $root -ManifestPath $fixture.ManifestPath -Downloader { throw 'cache hit should avoid downloader' }
        $provenance = Read-EzDarkFactoryJson -Path $second.provenancePath
        Assert-EzDarkFactoryEqual -Actual $provenance.sha256 -Expected $fixture.Digest
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}
