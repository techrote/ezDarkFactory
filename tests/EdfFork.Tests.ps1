Add-EzDarkFactoryTest -Name 'EDF: namespaced manifest/CLI identity is a distinct development build' -ScriptBlock {
    $root = $script:EzDarkFactoryRepositoryRoot
    $moduleManifest = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'src/EzDarkFactory/EzDarkFactory.psd1')
    Assert-EzDarkFactoryEqual -Actual ([string]$moduleManifest.ModuleVersion) -Expected '0.0.0'
    Assert-EzDarkFactoryEqual -Actual ([string]$moduleManifest.PrivateData.EzDarkFactoryVersion) -Expected '0.0.0-dev'
    Assert-EzDarkFactoryTrue -Condition ([string]$moduleManifest.GUID -cne '2e0b7e67-36f3-4e77-96c8-8d40296b7abd')
    Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryVersion) -Expected '0.0.0-dev'
    Assert-EzDarkFactoryTrue -Condition (Test-Path -LiteralPath (Join-Path $root 'ezdarkfactory.ps1') -PathType Leaf)
    Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root 'src/EzVm')))
}

Add-EzDarkFactoryTest -Name 'EDF: stopped root-local state and synthetic identity survive relocation without hidden host authority' -ScriptBlock {
    $original = New-EzDarkFactoryCheckoutFixture -Prefix 'new factory source [spaces]'
    $destination = New-EzDarkFactoryTestDirectory -Prefix 'moved factory source [spaces]'
    try {
        $runtime = Join-Path $original 'runtime'
        [void][IO.Directory]::CreateDirectory((Join-Path $runtime 'instances/project-one'))
        [IO.File]::WriteAllText((Join-Path $runtime 'config.json'), '{"schemaVersion":1,"profiles":{"normal":{"memoryMiB":12288}}}', (New-Object Text.UTF8Encoding($false)))
        $instanceIdentity = 'instance-demo-opaque-0001'
        $identityFile = Join-Path $runtime 'instances/project-one/identity.json'
        [IO.File]::WriteAllText($identityFile, ('{"schemaVersion":1,"instanceId":"' + $instanceIdentity + '"}'), (New-Object Text.UTF8Encoding($false)))
        foreach ($child in (Get-ChildItem -LiteralPath $original -Force)) {
            Copy-Item -LiteralPath $child.FullName -Destination $destination -Recurse -Force
        }
        $paths = Get-EzDarkFactoryPaths -Root $destination
        Assert-EzDarkFactoryTrue -Condition ($paths.Root -cne $original)
        Assert-EzDarkFactoryTrue -Condition ($paths.Instances.StartsWith($destination, [StringComparison]::OrdinalIgnoreCase))
        Assert-EzDarkFactoryEqual -Actual (($paths.Instances | Split-Path -Parent)) -Expected (Join-Path $destination 'runtime')
        $movedIdentity = Get-Content -LiteralPath (Join-Path $paths.Instances 'project-one/identity.json') -Raw | ConvertFrom-Json
        Assert-EzDarkFactoryEqual -Actual $movedIdentity.instanceId -Expected $instanceIdentity
        $movedConfiguration = Get-EzDarkFactoryConfiguration -Root $destination
        Assert-EzDarkFactoryEqual -Actual $movedConfiguration.profiles.normal.memoryMiB -Expected 12288
        Assert-EzDarkFactoryTrue -Condition (-not $paths.Runtime.StartsWith($original, [StringComparison]::OrdinalIgnoreCase))
        # The fixture itself lives beneath the host's TEMP directory, which
        # may be within LOCALAPPDATA. The invariant is ownership by this
        # relocated root, not an arbitrary prefix exclusion of user-profile paths.
        Assert-EzDarkFactoryEqual -Actual $paths.Keys -Expected (Join-Path $destination 'runtime/keys')
        Assert-EzDarkFactoryTrue -Condition ($paths.Keys.StartsWith($destination, [StringComparison]::OrdinalIgnoreCase))
        Assert-EzDarkFactoryTrue -Condition (-not $paths.Keys.StartsWith($original, [StringComparison]::OrdinalIgnoreCase))
    }
    finally {
        Remove-EzDarkFactoryTestDirectory -Path $original
        Remove-EzDarkFactoryTestDirectory -Path $destination
    }
}
