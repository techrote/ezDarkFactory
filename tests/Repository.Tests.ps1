Import-Module (Join-Path $script:EzDarkFactoryRepositoryRoot 'scripts/RepositoryContract.psm1') -Force -ErrorAction Stop

function Invoke-EzDarkFactoryFixtureGit {
    param([string]$Root, [string[]]$Arguments)
    $output = @(& git -C $Root @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Fixture Git failed: $($output -join ' ')" }
}

function New-EzDarkFactoryRepositoryFixture {
    param([switch]$UseCrlf)

    $root = New-EzDarkFactoryTestDirectory -Prefix 'tracked repository fixture'
    try {
        foreach ($relative in @('.github', '.gitattributes', '.gitignore', 'README.md', 'AGENTS.md', 'RAG.md', 'THIRD-PARTY-NOTICES.md', 'docs', 'ezdarkfactory.ps1', 'src', 'config', 'manifests', 'guest', 'tests', 'scripts', 'tools')) {
            Copy-Item -LiteralPath (Join-Path $script:EzDarkFactoryRepositoryRoot $relative) -Destination $root -Recurse -Force
        }
        if ($UseCrlf) {
            foreach ($file in (Get-ChildItem -LiteralPath $root -File -Recurse -Force)) {
                $content = [IO.File]::ReadAllText($file.FullName).Replace("`r`n", "`n").Replace("`n", "`r`n")
                [IO.File]::WriteAllText($file.FullName, $content, (New-Object Text.UTF8Encoding($false)))
            }
        }
        Invoke-EzDarkFactoryFixtureGit -Root $root -Arguments @('init', '--quiet')
        Invoke-EzDarkFactoryFixtureGit -Root $root -Arguments @('config', 'core.autocrlf', 'false')
        # .gitattributes normalizes source text into the index. Allow that intended
        # CRLF conversion without warnings; real whitespace checks remain enabled.
        Invoke-EzDarkFactoryFixtureGit -Root $root -Arguments @('config', 'core.safecrlf', 'false')
        Invoke-EzDarkFactoryFixtureGit -Root $root -Arguments @('add', '--all', '--force')
        return $root
    }
    catch {
        Remove-EzDarkFactoryTestDirectory -Path $root
        throw
    }
}

function Add-EzDarkFactoryTrackedFixtureFile {
    param([string]$Root, [string]$RelativePath, [string]$Content = 'synthetic fixture')
    $path = Join-Path $Root $RelativePath
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    [IO.File]::WriteAllText($path, $Content, (New-Object Text.UTF8Encoding($false)))
    Invoke-EzDarkFactoryFixtureGit -Root $Root -Arguments @('add', '--force', '--', $RelativePath)
    return $path
}

Add-EzDarkFactoryTest -Name 'Repository: a fully tracked source-only checkout satisfies all contract checks' -ScriptBlock {
    $root = New-EzDarkFactoryRepositoryFixture
    try {
        $result = Test-EzDarkFactoryRepositoryContract -Root $root
        Assert-EzDarkFactoryTrue -Condition ($result.TrackedFiles -ge 30)
        Assert-EzDarkFactoryTrue -Condition ($result.JsonFiles -ge 2)
        Assert-EzDarkFactoryTrue -Condition ($result.PowerShellFiles -ge 10)
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Repository: ignored untracked runtime state does not contaminate the source check' -ScriptBlock {
    $root = New-EzDarkFactoryRepositoryFixture
    try {
        $runtime = Join-Path $root 'runtime'
        [void][IO.Directory]::CreateDirectory($runtime)
        [IO.File]::WriteAllText((Join-Path $runtime 'fixture.qcow2'), 'synthetic ignored fixture, not a disk')
        $null = Test-EzDarkFactoryRepositoryContract -Root $root
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Repository: CRLF materialization normalizes to LF while genuine trailing whitespace still fails' -ScriptBlock {
    $root = New-EzDarkFactoryRepositoryFixture -UseCrlf
    try {
        $readme = [IO.File]::ReadAllText((Join-Path $root 'README.md'))
        Assert-EzDarkFactoryTrue -Condition ($readme.Contains("`r`n")) -Message 'The regression fixture must actually contain Windows CRLF bytes.'
        $eol = @(& git -C $root ls-files --eol -- README.md) -join ''
        Assert-EzDarkFactoryEqual -Actual $LASTEXITCODE -Expected 0
        Assert-EzDarkFactoryTrue -Condition ($eol -match 'i/lf\s+w/crlf') -Message 'Git must store LF while the fixture working tree retains CRLF.'
        $null = Test-EzDarkFactoryRepositoryContract -Root $root
        $null = Add-EzDarkFactoryTrackedFixtureFile -Root $root -RelativePath 'notes/crlf-trailing.txt' -Content "genuine trailing space `r`n"
        Assert-EzDarkFactoryThrows -ScriptBlock { Test-EzDarkFactoryRepositoryContract -Root $root } -MessagePattern 'git diff.*check' | Out-Null
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

$forbiddenPaths = @(
    'runtime/readme.txt',
    'nested/RuNtImE/state.txt',
    'nested/.ezdarkfactory/state.txt',
    'nested/CACHE/download.txt',
    'artifacts/report.txt',
    'nested/DISK.QCOW2',
    'payload/installer.EXE',
    'payload/library.DLL',
    'payload/source.IMG',
    'payload/runtime.ZIP',
    'payload/runtime.7z',
    'payload/guest.vmdk',
    'credentials/key.PEM',
    'credentials/private.KEY',
    'credentials/id_ed25519',
    'credentials/.env.local'
)
foreach ($forbiddenPath in $forbiddenPaths) {
    Add-EzDarkFactoryTest -Name ('Repository: rejects force-added ' + $forbiddenPath) -Data $forbiddenPath -ScriptBlock {
        param($relative)
        $root = New-EzDarkFactoryRepositoryFixture
        try {
            $null = Add-EzDarkFactoryTrackedFixtureFile -Root $root -RelativePath $relative
            Assert-EzDarkFactoryThrows -ScriptBlock { Test-EzDarkFactoryRepositoryContract -Root $root } -MessagePattern 'Forbidden.*tracked' | Out-Null
        }
        finally { Remove-EzDarkFactoryTestDirectory -Path $root }
    }
}

Add-EzDarkFactoryTest -Name 'Repository: private-key headers cannot be hidden in an innocuous text filename' -ScriptBlock {
    $root = New-EzDarkFactoryRepositoryFixture
    try {
        # Assemble only synthetic headers in temporary fixtures; no credential is stored in source.
        $header = '-----BEGIN ' + 'OPENSSH PRIVATE KEY-----'
        $null = Add-EzDarkFactoryTrackedFixtureFile -Root $root -RelativePath 'notes/innocent.txt' -Content ($header + "`nsynthetic fixture`n")
        Assert-EzDarkFactoryThrows -ScriptBlock { Test-EzDarkFactoryRepositoryContract -Root $root } -MessagePattern 'Private-key content' | Out-Null
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Repository: renamed executable content cannot hide behind a text extension' -ScriptBlock {
    $root = New-EzDarkFactoryRepositoryFixture
    try {
        $path = Add-EzDarkFactoryTrackedFixtureFile -Root $root -RelativePath 'notes/payload.txt'
        [IO.File]::WriteAllBytes($path, [byte[]]@(0x4d, 0x5a, 0, 0, 1, 2, 3, 4))
        Invoke-EzDarkFactoryFixtureGit -Root $root -Arguments @('add', '--force', '--', 'notes/payload.txt')
        Assert-EzDarkFactoryThrows -ScriptBlock { Test-EzDarkFactoryRepositoryContract -Root $root } -MessagePattern 'binary/archive/disk payload' | Out-Null
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Repository: all tracked JSON files are parsed including nested uppercase extensions' -ScriptBlock {
    $root = New-EzDarkFactoryRepositoryFixture
    try {
        $null = Add-EzDarkFactoryTrackedFixtureFile -Root $root -RelativePath 'notes/nested/BROKEN.JSON' -Content '{"broken":'
        Assert-EzDarkFactoryThrows -ScriptBlock { Test-EzDarkFactoryRepositoryContract -Root $root } -MessagePattern 'JSON cannot be parsed' | Out-Null
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Repository: an empty tracked JSON file is invalid' -ScriptBlock {
    $root = New-EzDarkFactoryRepositoryFixture
    try {
        $null = Add-EzDarkFactoryTrackedFixtureFile -Root $root -RelativePath 'notes/empty.json' -Content ''
        Assert-EzDarkFactoryThrows -ScriptBlock { Test-EzDarkFactoryRepositoryContract -Root $root } -MessagePattern 'JSON file is empty' | Out-Null
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

foreach ($extension in @('ps1', 'psm1', 'psd1')) {
    Add-EzDarkFactoryTest -Name ('Repository: parses every tracked .' + $extension + ' source') -Data $extension -ScriptBlock {
        param($sourceExtension)
        $root = New-EzDarkFactoryRepositoryFixture
        try {
            $null = Add-EzDarkFactoryTrackedFixtureFile -Root $root -RelativePath ('notes/broken.' + $sourceExtension) -Content 'function Broken { '
            Assert-EzDarkFactoryThrows -ScriptBlock { Test-EzDarkFactoryRepositoryContract -Root $root } -MessagePattern 'PowerShell source cannot be parsed' | Out-Null
        }
        finally { Remove-EzDarkFactoryTestDirectory -Path $root }
    }
}

Add-EzDarkFactoryTest -Name 'Repository: authority files must be tracked even when present on disk' -ScriptBlock {
    $root = New-EzDarkFactoryRepositoryFixture
    try {
        Invoke-EzDarkFactoryFixtureGit -Root $root -Arguments @('rm', '--cached', '--quiet', '--', 'docs/rag/06-TESTING-CI-RELEASE.md')
        Assert-EzDarkFactoryThrows -ScriptBlock { Test-EzDarkFactoryRepositoryContract -Root $root } -MessagePattern 'Missing or untracked.*06-TESTING' | Out-Null
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Repository: missing working-tree source files are detected' -ScriptBlock {
    $root = New-EzDarkFactoryRepositoryFixture
    try {
        Remove-Item -LiteralPath (Join-Path $root 'src/EzDarkFactory/Paths.ps1') -Force
        Assert-EzDarkFactoryThrows -ScriptBlock { Test-EzDarkFactoryRepositoryContract -Root $root } -MessagePattern 'Tracked source file is missing' | Out-Null
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Repository: incorrect and duplicate issue catalogue mappings fail' -ScriptBlock {
    $root = New-EzDarkFactoryRepositoryFixture
    try {
        $path = Join-Path $root 'docs/programme/IMPLEMENTATION-PROGRAMME.md'
        $programme = [IO.File]::ReadAllText($path)
        [IO.File]::WriteAllText($path, $programme.Replace('https://github.com/techrote/ezDarkFactory/issues/12)', 'https://github.com/techrote/ezDarkFactory/issues/99)'))
        Assert-EzDarkFactoryThrows -ScriptBlock { Test-EzDarkFactoryRepositoryContract -Root $root } -MessagePattern 'coherent issue catalogue row.*EDF-012' | Out-Null
        $row = [regex]::Match($programme, '(?m)^\| EDF-012 .*').Value
        Assert-EzDarkFactoryTrue -Condition (-not [string]::IsNullOrEmpty($row))
        [IO.File]::WriteAllText($path, ($programme + "`n" + $row + "`n"))
        Assert-EzDarkFactoryThrows -ScriptBlock { Test-EzDarkFactoryRepositoryContract -Root $root } -MessagePattern 'coherent issue catalogue row.*EDF-012' | Out-Null
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Repository: staged whitespace errors remain a failing contract check' -ScriptBlock {
    $root = New-EzDarkFactoryRepositoryFixture
    try {
        $null = Add-EzDarkFactoryTrackedFixtureFile -Root $root -RelativePath 'notes/trailing.txt' -Content "trailing space `n"
        Assert-EzDarkFactoryThrows -ScriptBlock { Test-EzDarkFactoryRepositoryContract -Root $root } -MessagePattern 'git diff.*check' | Out-Null
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Repository: the checked-in harness has an explicit matching version and no external dependencies' -ScriptBlock {
    $tooling = Get-Content -LiteralPath (Join-Path $script:EzDarkFactoryRepositoryRoot 'tests/tooling.json') -Raw | ConvertFrom-Json
    Assert-EzDarkFactoryEqual -Actual $tooling.schemaVersion -Expected 1
    Assert-EzDarkFactoryEqual -Actual $tooling.version -Expected $script:EzDarkFactoryTestHarnessVersion
    Assert-EzDarkFactoryEqual -Actual @($tooling.externalDependencies).Count -Expected 0
}

Add-EzDarkFactoryTest -Name 'Harness: an empty suite and an actual failed assertion both exit nonzero' -ScriptBlock {
    $harnessPath = (Join-Path $script:EzDarkFactoryRepositoryRoot 'tests/TestHarness.ps1').Replace("'", "''")
    $empty = Invoke-EzDarkFactoryTestPowerShell -CommandText ('. ''' + $harnessPath + '''; Invoke-EzDarkFactoryTestSuite')
    Assert-EzDarkFactoryTrue -Condition ($empty.ExitCode -ne 0) -Message 'An empty suite returned success.'
    $failed = Invoke-EzDarkFactoryTestPowerShell -CommandText ('. ''' + $harnessPath + '''; Add-EzDarkFactoryTest -Name ''intentional failure'' -ScriptBlock { Assert-EzDarkFactoryEqual -Actual 1 -Expected 2 }; Invoke-EzDarkFactoryTestSuite')
    Assert-EzDarkFactoryTrue -Condition ($failed.ExitCode -ne 0) -Message 'A failed assertion returned success.'
    Assert-EzDarkFactoryTrue -Condition ($failed.StandardOutput -match '0 passed, 1 failed')
}
