function Set-EzDarkFactoryTestUserConfiguration {
    param([string]$Root, [string]$Json)
    $runtime = Join-Path $Root 'runtime'
    [void][IO.Directory]::CreateDirectory($runtime)
    [IO.File]::WriteAllText((Join-Path $runtime 'config.json'), $Json, (New-Object Text.UTF8Encoding($false)))
}

Add-EzDarkFactoryTest -Name 'Configuration: repository defaults load with the published profiles and no runtime writes' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'default configuration'
    try {
        $config = Get-EzDarkFactoryConfiguration -Root $root
        Assert-EzDarkFactoryEqual -Actual $config.schemaVersion -Expected 1
        Assert-EzDarkFactoryEqual -Actual $config.defaultProfile -Expected 'normal'
        Assert-EzDarkFactoryEqual -Actual $config.profiles.light.cpus -Expected 2
        Assert-EzDarkFactoryEqual -Actual $config.profiles.light.memoryMiB -Expected 4096
        Assert-EzDarkFactoryEqual -Actual $config.profiles.normal.cpus -Expected 4
        Assert-EzDarkFactoryEqual -Actual $config.profiles.normal.memoryMiB -Expected 8192
        Assert-EzDarkFactoryEqual -Actual $config.profiles.heavy.cpus -Expected 8
        Assert-EzDarkFactoryEqual -Actual $config.profiles.heavy.memoryMiB -Expected 16384
        Assert-EzDarkFactoryEqual -Actual $config.ssh.portRangeStart -Expected 22000
        Assert-EzDarkFactoryEqual -Actual $config.ssh.portRangeEnd -Expected 22999
        Assert-EzDarkFactoryEqual -Actual $config.timeouts.processSeconds -Expected 60
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root 'runtime')))
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Configuration: partial runtime overrides preserve unrelated defaults and source bytes' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'override configuration'
    try {
        $defaultsPath = Join-Path $root 'config/defaults.json'
        $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($defaultsPath))
        Set-EzDarkFactoryTestUserConfiguration -Root $root -Json '{"schemaVersion":1,"defaultProfile":"light","profiles":{"normal":{"cpus":6}},"ssh":{"portRangeStart":23000,"portRangeEnd":23009},"timeouts":{"processSeconds":90}}'
        $config = Get-EzDarkFactoryConfiguration -Root $root
        Assert-EzDarkFactoryEqual -Actual $config.defaultProfile -Expected 'light'
        Assert-EzDarkFactoryEqual -Actual $config.profiles.normal.cpus -Expected 6
        Assert-EzDarkFactoryEqual -Actual $config.profiles.normal.memoryMiB -Expected 8192
        Assert-EzDarkFactoryEqual -Actual $config.profiles.heavy.cpus -Expected 8
        Assert-EzDarkFactoryEqual -Actual $config.ssh.portRangeStart -Expected 23000
        Assert-EzDarkFactoryEqual -Actual $config.ssh.portRangeEnd -Expected 23009
        Assert-EzDarkFactoryEqual -Actual $config.timeouts.processSeconds -Expected 90
        Assert-EzDarkFactoryEqual -Actual ([Convert]::ToBase64String([IO.File]::ReadAllBytes($defaultsPath))) -Expected $before
        $config.profiles.normal.cpus = 99
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryConfiguration -Root $root).profiles.normal.cpus -Expected 6 -Message 'A caller mutated a cached configuration value.'
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Configuration: validated numeric boundary values are accepted' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'configuration boundaries'
    try {
        Set-EzDarkFactoryTestUserConfiguration -Root $root -Json '{"schemaVersion":1,"profiles":{"light":{"cpus":1,"memoryMiB":512},"heavy":{"cpus":256,"memoryMiB":1048576}},"ssh":{"portRangeStart":1024,"portRangeEnd":65535},"timeouts":{"processSeconds":1}}'
        $config = Get-EzDarkFactoryConfiguration -Root $root
        Assert-EzDarkFactoryEqual -Actual $config.profiles.light.cpus -Expected 1
        Assert-EzDarkFactoryEqual -Actual $config.profiles.heavy.memoryMiB -Expected 1048576
        Assert-EzDarkFactoryEqual -Actual $config.ssh.portRangeStart -Expected 1024
        Assert-EzDarkFactoryEqual -Actual $config.ssh.portRangeEnd -Expected 65535
        Set-EzDarkFactoryTestUserConfiguration -Root $root -Json '{"schemaVersion":1,"ssh":{"portRangeStart":22000,"portRangeEnd":22000},"timeouts":{"processSeconds":3600}}'
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryConfiguration -Root $root).timeouts.processSeconds -Expected 3600
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

$invalidOverrides = @(
    @{ Name = 'missing schema version'; Json = '{"defaultProfile":"light"}' },
    @{ Name = 'unsupported schema version'; Json = '{"schemaVersion":2}' },
    @{ Name = 'string schema version'; Json = '{"schemaVersion":"1"}' },
    @{ Name = 'malformed JSON'; Json = '{"schemaVersion":1,' },
    @{ Name = 'array root'; Json = '[{"schemaVersion":1}]' },
    @{ Name = 'null root'; Json = 'null' },
    @{ Name = 'unknown top-level field'; Json = '{"schemaVersion":1,"defautProfile":"light"}' },
    @{ Name = 'root dictionary Keys member shadowing'; Json = '{"schemaVersion":1,"Keys":[]}' },
    @{ Name = 'lowercase dictionary keys member shadowing'; Json = '{"schemaVersion":1,"keys":[],"defaultProfile":"bad"}' },
    @{ Name = 'incorrect key case'; Json = '{"schemaVersion":1,"DefaultProfile":"light"}' },
    @{ Name = 'unknown nested field'; Json = '{"schemaVersion":1,"profiles":{"normal":{"cpu":8}}}' },
    @{ Name = 'nested dictionary Keys member shadowing'; Json = '{"schemaVersion":1,"profiles":{"normal":{"Keys":[],"cpus":7}}}' },
    @{ Name = 'unknown profile'; Json = '{"schemaVersion":1,"profiles":{"custom":{"cpus":2}}}' },
    @{ Name = 'missing profile selection'; Json = '{"schemaVersion":1,"defaultProfile":"custom"}' },
    @{ Name = 'null profile map'; Json = '{"schemaVersion":1,"profiles":null}' },
    @{ Name = 'array profile'; Json = '{"schemaVersion":1,"profiles":{"normal":[4,8192]}}' },
    @{ Name = 'boolean CPU count'; Json = '{"schemaVersion":1,"profiles":{"normal":{"cpus":true}}}' },
    @{ Name = 'string CPU count'; Json = '{"schemaVersion":1,"profiles":{"normal":{"cpus":"4"}}}' },
    @{ Name = 'fractional CPU count'; Json = '{"schemaVersion":1,"profiles":{"normal":{"cpus":2.5}}}' },
    @{ Name = 'CPU count below range'; Json = '{"schemaVersion":1,"profiles":{"normal":{"cpus":0}}}' },
    @{ Name = 'CPU count above range'; Json = '{"schemaVersion":1,"profiles":{"normal":{"cpus":257}}}' },
    @{ Name = 'memory below range'; Json = '{"schemaVersion":1,"profiles":{"normal":{"memoryMiB":511}}}' },
    @{ Name = 'memory above range'; Json = '{"schemaVersion":1,"profiles":{"normal":{"memoryMiB":1048577}}}' },
    @{ Name = 'SSH port below range'; Json = '{"schemaVersion":1,"ssh":{"portRangeStart":1023}}' },
    @{ Name = 'SSH port above range'; Json = '{"schemaVersion":1,"ssh":{"portRangeEnd":65536}}' },
    @{ Name = 'reversed SSH range'; Json = '{"schemaVersion":1,"ssh":{"portRangeStart":23000,"portRangeEnd":22000}}' },
    @{ Name = 'timeout below range'; Json = '{"schemaVersion":1,"timeouts":{"processSeconds":0}}' },
    @{ Name = 'timeout above range'; Json = '{"schemaVersion":1,"timeouts":{"processSeconds":3601}}' }
)
foreach ($invalidOverride in $invalidOverrides) {
    Add-EzDarkFactoryTest -Name ('Configuration: rejects ' + $invalidOverride.Name) -Data $invalidOverride -ScriptBlock {
        param($case)
        $root = New-EzDarkFactoryCheckoutFixture -Prefix 'invalid configuration'
        try {
            Set-EzDarkFactoryTestUserConfiguration -Root $root -Json $case.Json
            Assert-EzDarkFactoryThrows -ScriptBlock { Get-EzDarkFactoryConfiguration -Root $root } | Out-Null
            Assert-EzDarkFactoryEqual -Actual ([IO.File]::ReadAllText((Join-Path $root 'runtime/config.json'))) -Expected $case.Json -Message 'Rejected configuration was silently rewritten.'
        }
        finally { Remove-EzDarkFactoryTestDirectory -Path $root }
    }
}

Add-EzDarkFactoryTest -Name 'Configuration: invalid repository defaults fail before runtime overrides can hide them' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'invalid defaults'
    try {
        [IO.File]::WriteAllText((Join-Path $root 'config/defaults.json'), '{"schemaVersion":1}')
        Set-EzDarkFactoryTestUserConfiguration -Root $root -Json ([IO.File]::ReadAllText((Join-Path $script:EzDarkFactoryRepositoryRoot 'config/defaults.json')))
        Assert-EzDarkFactoryThrows -ScriptBlock { Get-EzDarkFactoryConfiguration -Root $root } -MessagePattern 'Missing configuration' | Out-Null
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}
