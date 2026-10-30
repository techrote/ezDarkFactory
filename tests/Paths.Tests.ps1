Add-EzDarkFactoryTest -Name 'Paths: default root is independent of the current working directory' -ScriptBlock {
    $elsewhere = New-EzDarkFactoryTestDirectory -Prefix 'unrelated working directory'
    $previous = Get-Location
    try {
        Set-Location -LiteralPath $elsewhere
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryRoot) -Expected $script:EzDarkFactoryRepositoryRoot
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryPaths).Root -Expected $script:EzDarkFactoryRepositoryRoot
    }
    finally {
        Set-Location -LiteralPath $previous.Path
        Remove-EzDarkFactoryTestDirectory -Path $elsewhere
    }
}

Add-EzDarkFactoryTest -Name 'Paths: every managed path follows a root containing spaces without creating state' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture
    try {
        $paths = Get-EzDarkFactoryPaths -Root $root
        $expected = [ordered]@{
            Root = ''
            Config = 'config'
            Defaults = 'config/defaults.json'
            Manifests = 'manifests'
            QemuManifest = 'manifests/qemu-windows.json'
            UbuntuManifest = 'manifests/ubuntu-noble-amd64.json'
            Guest = 'guest'
            BaseCloudInit = 'guest/base-cloud-init'
            BaseBaseline = 'guest/base-cloud-init/baseline.json'
            BaseUserDataTemplate = 'guest/base-cloud-init/user-data.yaml'
            BaseMetaDataTemplate = 'guest/base-cloud-init/meta-data.yaml'
            Runtime = 'runtime'
            UserConfig = 'runtime/config.json'
            Qemu = 'runtime/qemu'
            Cache = 'runtime/cache'
            Downloads = 'runtime/cache/downloads'
            SourceImages = 'runtime/cache/source-images'
            Keys = 'runtime/keys'
            Bases = 'runtime/bases'
            Instances = 'runtime/instances'
            Locks = 'runtime/locks'
        }
        Assert-EzDarkFactoryEqual -Actual @($paths.PSObject.Properties.Name).Count -Expected $expected.Count
        foreach ($entry in $expected.GetEnumerator()) {
            $name = $entry.Key
            $wanted = $root
            if ($expected[$name]) { $wanted = Join-Path $root $expected[$name] }
            Assert-EzDarkFactoryEqual -Actual $paths.$name -Expected $wanted -Message "Incorrect $name path."
            Assert-EzDarkFactoryTrue -Condition ([IO.Path]::IsPathRooted($paths.$name)) -Message "$name is not absolute."
        }
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath $paths.Runtime)) -Message 'Path discovery created runtime state.'
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Paths: cold relocation works without Git metadata or the previous root' -ScriptBlock {
    $original = New-EzDarkFactoryCheckoutFixture -Prefix 'original long-ish portable checkout'
    $relocated = New-EzDarkFactoryTestDirectory -Prefix 'relocated portable checkout'
    try {
        Get-ChildItem -LiteralPath $original -Force | Copy-Item -Destination $relocated -Recurse -Force
        Remove-EzDarkFactoryTestDirectory -Path $original
        $paths = Get-EzDarkFactoryPaths -Root $relocated
        Assert-EzDarkFactoryEqual -Actual $paths.Root -Expected $relocated
        Assert-EzDarkFactoryEqual -Actual $paths.Instances -Expected (Join-Path $relocated 'runtime/instances')
        foreach ($property in $paths.PSObject.Properties) {
            Assert-EzDarkFactoryTrue -Condition (-not $property.Value.Contains($original)) -Message 'Relocated paths still refer to the previous root.'
        }
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $relocated '.git')))
    }
    finally {
        Remove-EzDarkFactoryTestDirectory -Path $original
        Remove-EzDarkFactoryTestDirectory -Path $relocated
    }
}

Add-EzDarkFactoryTest -Name 'Paths: relative dot paths resolve to a complete checkout' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture
    $previous = Get-Location
    try {
        Set-Location -LiteralPath $root
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryRoot -Path '.') -Expected $root
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryPaths -Root '.').Defaults -Expected (Join-Path $root 'config/defaults.json')
    }
    finally {
        Set-Location -LiteralPath $previous.Path
        Remove-EzDarkFactoryTestDirectory -Path $root
    }
}

Add-EzDarkFactoryTest -Name 'Paths: empty, missing, incomplete and file roots fail with remediation' -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'incomplete checkout'
    try {
        $leaf = Join-Path $root 'not-a-directory.txt'
        [IO.File]::WriteAllText($leaf, 'fixture')
        foreach ($invalid in @('', ' ', (Join-Path $root 'missing'), $root, $leaf)) {
            Assert-EzDarkFactoryThrows -ScriptBlock { Get-EzDarkFactoryRoot -Path $invalid } -MessagePattern 'checkout|root' | Out-Null
        }
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}
