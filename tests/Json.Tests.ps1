Add-EzDarkFactoryTest -Name 'JSON creates and replaces versioned state in a path with spaces' -ScriptBlock {
    $directory = New-EzDarkFactoryTestDirectory -Prefix 'json roundtrip'
    try {
        $path = Join-Path $directory 'state with spaces.json'
        $text = 'VM ' + [char] 0x03BB + ' ' + [char] 0x65E5
        $inputValue = [ordered] @{
            schemaVersion = 1
            name = $text
            enabled = $true
            optional = $null
            empty = @()
            nested = [pscustomobject] @{ values = @(1, 'two', $false) }
        }
        $output = @(Write-EzDarkFactoryJson -Path $path -Value $inputValue)
        Assert-EzDarkFactoryEqual -Actual $output.Count -Expected 0
        $actual = Read-EzDarkFactoryJson -Path $path
        Assert-EzDarkFactoryEqual -Actual $actual.schemaVersion -Expected 1
        Assert-EzDarkFactoryEqual -Actual $actual.name -Expected $text
        Assert-EzDarkFactoryEqual -Actual $actual.enabled -Expected $true
        Assert-EzDarkFactoryTrue -Condition ($null -eq $actual.optional) -Message 'JSON null must round-trip.'
        Assert-EzDarkFactoryEqual -Actual @($actual.empty).Count -Expected 0
        Assert-EzDarkFactoryEqual -Actual $actual.nested.values.Count -Expected 3
        Assert-EzDarkFactoryEqual -Actual $actual.nested.values[1] -Expected 'two'

        Write-EzDarkFactoryJson -Path $path -Value @{ schemaVersion = 1; name = 'replacement' }
        Assert-EzDarkFactoryEqual -Actual (Read-EzDarkFactoryJson -Path $path).name -Expected 'replacement'
        Assert-EzDarkFactoryEqual -Actual ([System.IO.Directory]::GetFiles($directory).Length) -Expected 1
        $bytes = [System.IO.File]::ReadAllBytes($path)
        Assert-EzDarkFactoryTrue -Condition ([BitConverter]::ToString($bytes[0..2]) -ne 'EF-BB-BF') -Message 'State is written as UTF-8 without a BOM.'
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $directory }
}

Add-EzDarkFactoryTest -Name 'JSON resolves relative paths against the PowerShell location' -ScriptBlock {
    $directory = New-EzDarkFactoryTestDirectory -Prefix 'json location'
    Push-Location -LiteralPath $directory
    try {
        Write-EzDarkFactoryJson -Path 'relative.json' -Value @{ schemaVersion = 1; name = 'relative' }
        Assert-EzDarkFactoryTrue -Condition ([System.IO.File]::Exists((Join-Path $directory 'relative.json'))) -Message 'The file must use the PowerShell location.'
        Assert-EzDarkFactoryEqual -Actual (Read-EzDarkFactoryJson -Path 'relative.json').name -Expected 'relative'
    }
    finally {
        Pop-Location
        Remove-EzDarkFactoryTestDirectory -Path $directory
    }
}

Add-EzDarkFactoryTest -Name 'JSON round-trips a literal Keys member in hashtables and ordered dictionaries' -ScriptBlock {
    $directory = New-EzDarkFactoryTestDirectory -Prefix 'json dictionary Keys'
    try {
        $path = Join-Path $directory 'state.json'
        $values = @(
            @{ schemaVersion = 1; Keys = @('first', 'second'); payload = @{ value = 'hashtable' } },
            [ordered] @{ schemaVersion = 1; Keys = @('first', 'second'); payload = @{ value = 'ordered dictionary' } }
        )
        foreach ($value in $values) {
            Write-EzDarkFactoryJson -Path $path -Value $value
            $actual = Read-EzDarkFactoryJson -Path $path
            Assert-EzDarkFactoryEqual -Actual $actual.schemaVersion -Expected 1
            Assert-EzDarkFactoryEqual -Actual $actual.Keys.Count -Expected 2
            Assert-EzDarkFactoryEqual -Actual $actual.Keys[0] -Expected 'first'
            Assert-EzDarkFactoryEqual -Actual $actual.Keys[1] -Expected 'second'
            Assert-EzDarkFactoryEqual -Actual $actual.payload.value -Expected $value['payload']['value']
        }
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $directory }
}

Add-EzDarkFactoryTest -Name 'JSON literal Keys members cannot hide unsupported or cyclic payloads from validation' -ScriptBlock {
    $directory = New-EzDarkFactoryTestDirectory -Prefix 'json Keys validation'
    try {
        $path = Join-Path $directory 'state.json'
        $original = [System.Text.Encoding]::UTF8.GetBytes('{"schemaVersion":1,"value":"preserve exactly"}')
        [System.IO.File]::WriteAllBytes($path, $original)
        $cycle = @{}
        $cycle['self'] = $cycle
        $values = @(
            @{ schemaVersion = 1; Keys = @('schemaVersion'); payload = { 'unsupported script' } },
            [ordered] @{ schemaVersion = 1; Keys = @('schemaVersion'); payload = { 'unsupported script' } },
            @{ schemaVersion = 1; Keys = @('schemaVersion'); payload = $cycle },
            [ordered] @{ schemaVersion = 1; Keys = @('schemaVersion'); payload = $cycle }
        )
        foreach ($value in $values) {
            Assert-EzDarkFactoryThrows -ScriptBlock { Write-EzDarkFactoryJson -Path $path -Value $value } -MessagePattern 'unsupported type|reference cycle'
            Assert-EzDarkFactoryEqual -Actual ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path))) -Expected ([Convert]::ToBase64String($original))
            Assert-EzDarkFactoryEqual -Actual ([System.IO.Directory]::GetFiles($directory).Length) -Expected 1
        }
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $directory }
}

Add-EzDarkFactoryTest -Name 'JSON rejects malformed documents and non-object roots' -ScriptBlock {
    $directory = New-EzDarkFactoryTestDirectory -Prefix 'json invalid'
    try {
        $path = Join-Path $directory 'invalid.json'
        $documents = @('', 'null', 'true', '42', '"text"', '[]', '[{"schemaVersion":1}]', '{"schemaVersion":')
        foreach ($document in $documents) {
            [System.IO.File]::WriteAllText($path, $document)
            Assert-EzDarkFactoryThrows -ScriptBlock { Read-EzDarkFactoryJson -Path $path } -MessagePattern 'JSON'
        }
        Assert-EzDarkFactoryThrows -ScriptBlock { Read-EzDarkFactoryJson -Path (Join-Path $directory 'missing.json') } -MessagePattern 'exists.*readable'
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $directory }
}

Add-EzDarkFactoryTest -Name 'JSON requires an exact integer schema version' -ScriptBlock {
    $directory = New-EzDarkFactoryTestDirectory -Prefix 'json schema'
    try {
        $path = Join-Path $directory 'state.json'
        $documents = @('{}', '{"SchemaVersion":1}', '{"schemaVersion":null}', '{"schemaVersion":"1"}', '{"schemaVersion":true}', '{"schemaVersion":1.0}', '{"schemaVersion":1.5}', '{"schemaVersion":2}')
        foreach ($document in $documents) {
            [System.IO.File]::WriteAllText($path, $document)
            Assert-EzDarkFactoryThrows -ScriptBlock { Read-EzDarkFactoryJson -Path $path } -MessagePattern 'schemaVersion'
        }
        Write-EzDarkFactoryJson -Path $path -Value @{ schemaVersion = 2; name = 'explicit schema' } -SchemaVersion 2
        Assert-EzDarkFactoryEqual -Actual (Read-EzDarkFactoryJson -Path $path -SchemaVersion 2).name -Expected 'explicit schema'
        Assert-EzDarkFactoryThrows -ScriptBlock { Read-EzDarkFactoryJson -Path $path } -MessagePattern 'unsupported schemaVersion'
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $directory }
}

Add-EzDarkFactoryTest -Name 'JSON preserves nested timestamp strings including offsets' -ScriptBlock {
    $directory = New-EzDarkFactoryTestDirectory -Prefix 'json timestamps'
    try {
        $path = Join-Path $directory 'state.json'
        $offset = '2026-10-11T12:34:56.1234000+02:00'
        $utc = '2026-10-11T10:34:56Z'
        Write-EzDarkFactoryJson -Path $path -Value @{ schemaVersion = 1; nested = @{ times = @($offset, $utc) } }
        $value = Read-EzDarkFactoryJson -Path $path
        Assert-EzDarkFactoryTrue -Condition ($value.nested.times[0] -is [string]) -Message 'Timestamps must remain JSON strings.'
        Assert-EzDarkFactoryEqual -Actual $value.nested.times[0] -Expected $offset
        Assert-EzDarkFactoryEqual -Actual $value.nested.times[1] -Expected $utc
        Write-EzDarkFactoryJson -Path $path -Value $value
        Assert-EzDarkFactoryEqual -Actual (Read-EzDarkFactoryJson -Path $path).nested.times[0] -Expected $offset
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $directory }
}

Add-EzDarkFactoryTest -Name 'JSON serialization failures preserve old bytes and create no temporary remnants' -ScriptBlock {
    $directory = New-EzDarkFactoryTestDirectory -Prefix 'json fail safe'
    try {
        $path = Join-Path $directory 'state.json'
        $original = [System.Text.Encoding]::UTF8.GetBytes("{`n  `"schemaVersion`": 1, `"name`": `"keep exactly`"`n}`n")
        [System.IO.File]::WriteAllBytes($path, $original)
        $cycle = @{ schemaVersion = 1 }
        $cycle['self'] = $cycle
        $tooDeep = @{ schemaVersion = 1 }
        $cursor = $tooDeep
        foreach ($index in 1..66) {
            $cursor['next'] = @{}
            $cursor = $cursor['next']
        }
        $invalidValues = @(
            @{ schemaVersion = '1' },
            @{ schemaVersion = $true },
            @{ schemaVersion = 2 },
            @{ schemaVersion = 1; cannotSerialize = { 'script content' } },
            @{ schemaVersion = 1; invalidNumber = [double]::NaN },
            @{ schemaVersion = 1; timestamp = [datetime]::UtcNow },
            $cycle,
            $tooDeep
        )
        foreach ($value in $invalidValues) {
            Assert-EzDarkFactoryThrows -ScriptBlock { Write-EzDarkFactoryJson -Path $path -Value $value } -MessagePattern 'Could not atomically write JSON'
            Assert-EzDarkFactoryEqual -Actual ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path))) -Expected ([Convert]::ToBase64String($original))
            Assert-EzDarkFactoryEqual -Actual ([System.IO.Directory]::GetFiles($directory).Length) -Expected 1
        }
        Assert-EzDarkFactoryThrows -ScriptBlock { Write-EzDarkFactoryJson -Path (Join-Path $directory 'new.json') -Value $cycle } -MessagePattern 'cycle'
        Assert-EzDarkFactoryTrue -Condition (-not [System.IO.File]::Exists((Join-Path $directory 'new.json'))) -Message 'Validation must finish before a new state file is created.'
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $directory }
}

Add-EzDarkFactoryTest -Name 'JSON failed promotion cleans its temporary file and preserves the destination directory' -ScriptBlock {
    $directory = New-EzDarkFactoryTestDirectory -Prefix 'json promotion failure'
    try {
        $destination = Join-Path $directory 'state.json'
        $null = [System.IO.Directory]::CreateDirectory($destination)
        $sentinel = Join-Path $destination 'preserve.txt'
        [System.IO.File]::WriteAllText($sentinel, 'existing destination')
        Assert-EzDarkFactoryThrows -ScriptBlock { Write-EzDarkFactoryJson -Path $destination -Value @{ schemaVersion = 1 } } -MessagePattern 'atomically write'
        Assert-EzDarkFactoryEqual -Actual ([System.IO.File]::ReadAllText($sentinel)) -Expected 'existing destination'
        Assert-EzDarkFactoryEqual -Actual ([System.IO.Directory]::GetFiles($directory).Length) -Expected 0
        Assert-EzDarkFactoryThrows -ScriptBlock { Write-EzDarkFactoryJson -Path (Join-Path (Join-Path $directory 'absent') 'state.json') -Value @{ schemaVersion = 1 } } -MessagePattern 'parent directory'
        Assert-EzDarkFactoryTrue -Condition (-not [System.IO.Directory]::Exists((Join-Path $directory 'absent'))) -Message 'JSON writes must not create unexpected parent directories.'
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $directory }
}

$lockedStateSkip = $null
if (-not $script:EzDarkFactoryIsWindowsHost) {
    $lockedStateSkip = 'Windows FileShare.None replacement semantics require a Windows host; Windows CI runs this check on both PowerShell versions.'
}
Add-EzDarkFactoryTest -Name 'JSON locked existing state is preserved byte for byte after replacement failure' -SkipReason $lockedStateSkip -ScriptBlock {
    $directory = New-EzDarkFactoryTestDirectory -Prefix 'json locked target'
    $lock = $null
    try {
        $path = Join-Path $directory 'state.json'
        $original = [System.Text.Encoding]::UTF8.GetBytes('{"schemaVersion":1,"value":"old bytes"}')
        [System.IO.File]::WriteAllBytes($path, $original)
        $lock = New-Object System.IO.FileStream($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        Assert-EzDarkFactoryThrows -ScriptBlock { Write-EzDarkFactoryJson -Path $path -Value @{ schemaVersion = 1; value = 'replacement' } } -MessagePattern 'atomically write'
        $lock.Dispose()
        $lock = $null
        Assert-EzDarkFactoryEqual -Actual ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path))) -Expected ([Convert]::ToBase64String($original))
        Assert-EzDarkFactoryEqual -Actual ([System.IO.Directory]::GetFiles($directory).Length) -Expected 1
    }
    finally {
        if ($null -ne $lock) { $lock.Dispose() }
        Remove-EzDarkFactoryTestDirectory -Path $directory
    }
}
