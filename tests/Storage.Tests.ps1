function New-EzDarkFactoryStorageFixture {
    $baseFixture = New-EzDarkFactoryBaseBuildFixture
    $safe = New-EzDarkFactoryStorageLifecycleGuard -State 'proven-safe' -Source 'storage fixture: no QEMU process owns these synthetic images'
    $baseResult = Invoke-EzDarkFactoryBaseBuild -Root $baseFixture.Root -Accelerator tcg -BuildTimeoutSeconds 60 -QemuStatusProvider $baseFixture.QemuStatusProvider -SourceProvider $baseFixture.SourceProvider -QemuImgRunner $baseFixture.QemuImgRunner -GuestRunner $baseFixture.GuestRunner

    $state = [pscustomobject]@{
        Mode = 'normal'
        CreateCount = 0
        Calls = New-Object 'System.Collections.Generic.List[object]'
    }
    $baseRunner = $baseFixture.QemuImgRunner
    $stateForRunner = $state
    $runner = {
        param($argumentList)
        $arguments = @($argumentList)
        $stateForRunner.Calls.Add([string[]]$arguments)
        $command = $arguments[0]

        if ($command -ceq 'create') {
            $destination = [IO.Path]::GetFullPath($arguments[$arguments.Count - 1])
            $backingIndex = [Array]::IndexOf($arguments, '-b')
            if ($backingIndex -lt 0 -or $backingIndex + 1 -ge $arguments.Count) {
                return [pscustomobject]@{ ExitCode = 2; StdOut = ''; StdErr = 'missing backing argument' }
            }
            $backing = $arguments[$backingIndex + 1]
            $resolved = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($destination)) $backing))
            if (-not [IO.File]::Exists($resolved)) {
                return [pscustomobject]@{ ExitCode = 2; StdOut = ''; StdErr = 'fixture backing file is missing' }
            }
            $stateForRunner.CreateCount++
            $payload = [pscustomobject][ordered]@{
                kind = 'overlay'
                backing = $backing
                generation = $stateForRunner.CreateCount
            }
            [IO.File]::WriteAllText($destination, ($payload | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
            return [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
        }

        if ($command -ceq 'info') {
            $path = [IO.Path]::GetFullPath($arguments[$arguments.Count - 1])
            $payload = $null
            try {
                $text = [IO.File]::ReadAllText($path)
                if ($text.StartsWith('{', [StringComparison]::Ordinal)) {
                    $payload = $text | ConvertFrom-Json -ErrorAction Stop
                }
            }
            catch { $payload = $null }

            if ($null -ne $payload -and $payload.kind -ceq 'overlay') {
                if ($stateForRunner.Mode -ceq 'malformed-chain-json' -and $arguments -ccontains '--backing-chain') {
                    return [pscustomobject]@{ ExitCode = 0; StdOut = '{"broken":'; StdErr = '' }
                }

                $backing = [string]$payload.backing
                $resolved = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($path)) $backing))
                $format = if ($stateForRunner.Mode -ceq 'wrong-backing-format' -or
                    ($stateForRunner.Mode -ceq 'wrong-replacement-format' -and [int]$payload.generation -gt 1)) { 'raw' } else { 'qcow2' }
                $top = [pscustomobject][ordered]@{
                    filename = $path
                    format = $(if ($stateForRunner.Mode -ceq 'wrong-overlay-format') { 'raw' } else { 'qcow2' })
                    'virtual-size' = [long]17179869184
                    'backing-filename' = $backing
                    'backing-filename-format' = $format
                }
                $base = [pscustomobject][ordered]@{
                    filename = $resolved
                    format = 'qcow2'
                    'virtual-size' = [long]17179869184
                }
                if ($arguments -ccontains '--backing-chain') {
                    $chain = @($top, $base)
                    if ($stateForRunner.Mode -ceq 'second-level') {
                        $chain += [pscustomobject][ordered]@{
                            filename = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($resolved)) 'deeper.qcow2'))
                            format = 'qcow2'
                            'virtual-size' = [long]17179869184
                        }
                    }
                    return [pscustomobject]@{ ExitCode = 0; StdOut = ($chain | ConvertTo-Json -Compress); StdErr = '' }
                }
                return [pscustomobject]@{ ExitCode = 0; StdOut = ($top | ConvertTo-Json -Compress); StdErr = '' }
            }

            return & $baseRunner $arguments
        }

        if ($command -ceq 'check') {
            if ($stateForRunner.Mode -ceq 'malformed-check-json') {
                return [pscustomobject]@{ ExitCode = 0; StdOut = 'not-json'; StdErr = '' }
            }
            if ($stateForRunner.Mode -ceq 'corrupt-check') {
                return [pscustomobject]@{
                    ExitCode = 2
                    StdOut = '{"filename":"fixture","format":"qcow2","check-errors":0,"corruptions":2,"leaks":1}'
                    StdErr = 'synthetic corruption'
                }
            }
            return [pscustomobject]@{
                ExitCode = 0
                StdOut = '{"filename":"fixture","format":"qcow2","check-errors":0,"corruptions":0,"leaks":0}'
                StdErr = ''
            }
        }

        return & $baseRunner $arguments
    }.GetNewClosure()

    return [pscustomobject]@{
        BaseFixture = $baseFixture
        Root = $baseFixture.Root
        Paths = $baseFixture.Paths
        BaseId = $baseResult.baseId
        BasePath = $baseResult.path
        SafeGuard = $safe
        Runner = $runner
        State = $state
    }
}

function Remove-EzDarkFactoryStorageFixture {
    param([object]$Fixture)
    if ($null -ne $Fixture) { Remove-EzDarkFactoryBaseBuildFixture $Fixture.BaseFixture }
}

function Get-EzDarkFactoryStorageOverlayPayload {
    param([string]$Path)
    return ([IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop)
}

function Set-EzDarkFactoryStorageOverlayBacking {
    param([string]$Path, [string]$Backing)
    $payload = Get-EzDarkFactoryStorageOverlayPayload -Path $Path
    $payload.backing = $Backing
    [IO.File]::WriteAllText($Path, ($payload | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
}

Add-EzDarkFactoryTest -Name 'Storage: rejects unsafe instance names before filesystem mutation' -ScriptBlock {
    $fixture = New-EzDarkFactoryStorageFixture
    try {
        $result = New-EzDarkFactoryInstanceOverlay -Root $fixture.Root -InstanceName 'agent one' -BaseId $fixture.BaseId -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner
        throw 'fixture should reject spaces in instance names before this point'
    }
    catch {
        Assert-EzDarkFactoryTrue -Condition ($_.Exception.Message -match 'Instance name') -Message 'Instance names containing spaces must be rejected before filesystem mutation.'
    }
    finally { Remove-EzDarkFactoryStorageFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Storage: valid overlay uses explicit qcow2 backing and validates exact immutable base' -ScriptBlock {
    $fixture = New-EzDarkFactoryStorageFixture
    try {
        $baseBefore = Get-EzDarkFactoryFileDigest -Path $fixture.BasePath -Algorithm SHA256
        $result = New-EzDarkFactoryInstanceOverlay -Root $fixture.Root -InstanceName 'agent-one' -BaseId $fixture.BaseId -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner
        $validated = Test-EzDarkFactoryInstanceStorage -Root $fixture.Root -InstanceName 'agent-one' -BaseId $fixture.BaseId -QemuImgRunner $fixture.Runner

        Assert-EzDarkFactoryEqual -Actual $validated.ChainDepth -Expected 1
        Assert-EzDarkFactoryEqual -Actual $validated.BasePath -Expected $fixture.BasePath
        Assert-EzDarkFactoryEqual -Actual $validated.ResolvedBackingPath -Expected $fixture.BasePath
        Assert-EzDarkFactoryTrue -Condition (-not [IO.Path]::IsPathRooted($validated.BackingReference))
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryFileDigest -Path $fixture.BasePath -Algorithm SHA256) -Expected $baseBefore -Message 'Overlay creation must never mutate the immutable base.'

        $createCall = @($fixture.State.Calls | Where-Object { $_[0] -ceq 'create' })[-1]
        Assert-EzDarkFactoryTrue -Condition ($createCall -ccontains '-f')
        Assert-EzDarkFactoryTrue -Condition ($createCall -ccontains '-F')
        Assert-EzDarkFactoryTrue -Condition ($createCall -ccontains '-b')
        Assert-EzDarkFactoryTrue -Condition ($createCall -cnotcontains '-u') -Message 'Unsafe backing creation must never be used.'
        $fIndex = [Array]::IndexOf($createCall, '-f')
        $FIndex = [Array]::IndexOf($createCall, '-F')
        Assert-EzDarkFactoryEqual -Actual $createCall[$fIndex + 1] -Expected 'qcow2'
        Assert-EzDarkFactoryEqual -Actual $createCall[$FIndex + 1] -Expected 'qcow2'
        Assert-EzDarkFactoryEqual -Actual $result.BackingReference -Expected $validated.BackingReference
    }
    finally { Remove-EzDarkFactoryStorageFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Storage: relative backing survives complete cold root relocation without rebase' -ScriptBlock {
    $fixture = New-EzDarkFactoryStorageFixture
    $target = $null
    try {
        $created = New-EzDarkFactoryInstanceOverlay -Root $fixture.Root -InstanceName 'relocate' -BaseId $fixture.BaseId -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner
        $referenceBefore = $created.BackingReference

        $target = New-EzDarkFactoryCheckoutFixture -Prefix 'relocated complete root B [different prefix]'
        Copy-Item -LiteralPath (Join-Path $fixture.Root 'runtime') -Destination $target -Recurse -Force
        $validated = Test-EzDarkFactoryInstanceStorage -Root $target -InstanceName 'relocate' -BaseId $fixture.BaseId -QemuImgRunner $fixture.Runner

        Assert-EzDarkFactoryEqual -Actual $validated.BackingReference -Expected $referenceBefore
        Assert-EzDarkFactoryTrue -Condition ($validated.OverlayPath.StartsWith([IO.Path]::GetFullPath($target), [StringComparison]::OrdinalIgnoreCase))
        Assert-EzDarkFactoryTrue -Condition ($validated.BasePath.StartsWith([IO.Path]::GetFullPath($target), [StringComparison]::OrdinalIgnoreCase))
        $allCalls = [string]::Join([Environment]::NewLine, [string[]]@($fixture.State.Calls | ForEach-Object { $_ -join ' ' }))
        Assert-EzDarkFactoryTrue -Condition ($allCalls -notmatch '(?i)\brebase\b') -Message 'Relocation must not rebase a valid normal instance.'
    }
    finally {
        if ($null -ne $target) { Remove-EzDarkFactoryTestDirectory -Path $target }
        Remove-EzDarkFactoryStorageFixture $fixture
    }
}

Add-EzDarkFactoryTest -Name 'Storage: rejects missing backing base and base digest mismatch' -ScriptBlock {
    $fixture = New-EzDarkFactoryStorageFixture
    try {
        $null = New-EzDarkFactoryInstanceOverlay -Root $fixture.Root -InstanceName 'missing-base' -BaseId $fixture.BaseId -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner
        $attributes = (Get-Item -LiteralPath $fixture.BasePath -Force).Attributes
        [IO.File]::SetAttributes($fixture.BasePath, ($attributes -band (-bnot [IO.FileAttributes]::ReadOnly)))
        [IO.File]::AppendAllText($fixture.BasePath, 'tamper')
        [IO.File]::SetAttributes($fixture.BasePath, ((Get-Item -LiteralPath $fixture.BasePath -Force).Attributes -bor [IO.FileAttributes]::ReadOnly))
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Test-EzDarkFactoryInstanceStorage -Root $fixture.Root -InstanceName 'missing-base' -BaseId $fixture.BaseId -QemuImgRunner $fixture.Runner
        } -MessagePattern 'digest does not match' | Out-Null

        [IO.File]::SetAttributes($fixture.BasePath, ((Get-Item -LiteralPath $fixture.BasePath -Force).Attributes -band (-bnot [IO.FileAttributes]::ReadOnly)))
        Remove-Item -LiteralPath $fixture.BasePath -Force
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Test-EzDarkFactoryInstanceStorage -Root $fixture.Root -InstanceName 'missing-base' -BaseId $fixture.BaseId -QemuImgRunner $fixture.Runner
        } -MessagePattern 'incomplete|missing' | Out-Null
    }
    finally { Remove-EzDarkFactoryStorageFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Storage: missing overlay and unexpected overlay format fail closed' -ScriptBlock {
    $fixture = New-EzDarkFactoryStorageFixture
    try {
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Test-EzDarkFactoryInstanceStorage -Root $fixture.Root -InstanceName 'absent' -BaseId $fixture.BaseId -QemuImgRunner $fixture.Runner
        } -MessagePattern 'Instance overlay.*missing' | Out-Null

        $null = New-EzDarkFactoryInstanceOverlay -Root $fixture.Root -InstanceName 'wrong-format' -BaseId $fixture.BaseId -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner
        $fixture.State.Mode = 'wrong-overlay-format'
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Test-EzDarkFactoryInstanceStorage -Root $fixture.Root -InstanceName 'wrong-format' -BaseId $fixture.BaseId -QemuImgRunner $fixture.Runner
        } -MessagePattern 'overlay format must be qcow2' | Out-Null
    }
    finally { Remove-EzDarkFactoryStorageFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Storage: rejects wrong backing format and unsupported second backing level' -ScriptBlock {
    $fixture = New-EzDarkFactoryStorageFixture
    try {
        $null = New-EzDarkFactoryInstanceOverlay -Root $fixture.Root -InstanceName 'bad-chain' -BaseId $fixture.BaseId -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner
        $fixture.State.Mode = 'wrong-backing-format'
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Test-EzDarkFactoryInstanceStorage -Root $fixture.Root -InstanceName 'bad-chain' -BaseId $fixture.BaseId -QemuImgRunner $fixture.Runner
        } -MessagePattern 'backing format.*qcow2' | Out-Null

        $fixture.State.Mode = 'second-level'
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Test-EzDarkFactoryInstanceStorage -Root $fixture.Root -InstanceName 'bad-chain' -BaseId $fixture.BaseId -QemuImgRunner $fixture.Runner
        } -MessagePattern 'backing-chain depth 2' | Out-Null
    }
    finally { Remove-EzDarkFactoryStorageFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Storage: rejects backing path escape and wrong existing managed backing' -ScriptBlock {
    $fixture = New-EzDarkFactoryStorageFixture
    try {
        $created = New-EzDarkFactoryInstanceOverlay -Root $fixture.Root -InstanceName 'escape' -BaseId $fixture.BaseId -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner
        Set-EzDarkFactoryStorageOverlayBacking -Path $created.Disk -Backing '..\..\..\outside.qcow2'
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Test-EzDarkFactoryInstanceStorage -Root $fixture.Root -InstanceName 'escape' -BaseId $fixture.BaseId -QemuImgRunner $fixture.Runner
        } -MessagePattern 'outside.*managed|escapes' | Out-Null

        $wrongDirectory = Join-Path $fixture.Paths.Bases 'wrong-base'
        [void][IO.Directory]::CreateDirectory($wrongDirectory)
        $wrongFile = Join-Path $wrongDirectory 'base.qcow2'
        [IO.File]::WriteAllText($wrongFile, 'wrong base fixture')
        $relative = Get-EzDarkFactoryStorageRelativePath -FromDirectory ([IO.Path]::GetDirectoryName($created.Disk)) -TargetPath $wrongFile
        Set-EzDarkFactoryStorageOverlayBacking -Path $created.Disk -Backing $relative
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Test-EzDarkFactoryInstanceStorage -Root $fixture.Root -InstanceName 'escape' -BaseId $fixture.BaseId -QemuImgRunner $fixture.Runner
        } -MessagePattern 'recorded base.*requires' | Out-Null
    }
    finally { Remove-EzDarkFactoryStorageFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Storage: malformed qemu-img JSON fails closed' -ScriptBlock {
    $fixture = New-EzDarkFactoryStorageFixture
    try {
        $null = New-EzDarkFactoryInstanceOverlay -Root $fixture.Root -InstanceName 'json' -BaseId $fixture.BaseId -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner
        $fixture.State.Mode = 'malformed-chain-json'
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Test-EzDarkFactoryInstanceStorage -Root $fixture.Root -InstanceName 'json' -BaseId $fixture.BaseId -QemuImgRunner $fixture.Runner
        } -MessagePattern 'malformed JSON' | Out-Null
    }
    finally { Remove-EzDarkFactoryStorageFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Storage: lifecycle guard fails closed for missing, running, transitional and unknown state' -ScriptBlock {
    $fixture = New-EzDarkFactoryStorageFixture
    try {
        Assert-EzDarkFactoryThrows -ScriptBlock {
            New-EzDarkFactoryInstanceOverlay -Root $fixture.Root -InstanceName 'guard-none' -BaseId $fixture.BaseId -LifecycleGuard $null -QemuImgRunner $fixture.Runner
        } -MessagePattern 'explicit positive lifecycle evidence' | Out-Null

        foreach ($state in @('running', 'starting', 'stopping', 'unknown')) {
            $guard = New-EzDarkFactoryStorageLifecycleGuard -State $state -Source 'fixture'
            Assert-EzDarkFactoryThrows -ScriptBlock {
                New-EzDarkFactoryInstanceOverlay -Root $fixture.Root -InstanceName ('guard-' + $state) -BaseId $fixture.BaseId -LifecycleGuard $guard -QemuImgRunner $fixture.Runner
            } -MessagePattern 'requires positively proven' | Out-Null
        }
        Assert-EzDarkFactoryEqual -Actual @(Get-ChildItem -LiteralPath $fixture.Paths.Instances -Filter 'guard-*' -Directory -ErrorAction SilentlyContinue).Count -Expected 0
    }
    finally { Remove-EzDarkFactoryStorageFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Storage: stopped-only check reports healthy and corrupt metadata without repair' -ScriptBlock {
    $fixture = New-EzDarkFactoryStorageFixture
    try {
        $null = New-EzDarkFactoryInstanceOverlay -Root $fixture.Root -InstanceName 'check' -BaseId $fixture.BaseId -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner
        $healthy = Test-EzDarkFactoryStoppedImageIntegrity -Root $fixture.Root -InstanceName 'check' -BaseId $fixture.BaseId -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner
        Assert-EzDarkFactoryTrue -Condition $healthy.Healthy
        Assert-EzDarkFactoryEqual -Actual $healthy.Corruptions -Expected 0

        $fixture.State.Mode = 'corrupt-check'
        $bad = Test-EzDarkFactoryStoppedImageIntegrity -Root $fixture.Root -InstanceName 'check' -BaseId $fixture.BaseId -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner
        Assert-EzDarkFactoryTrue -Condition (-not $bad.Healthy)
        Assert-EzDarkFactoryEqual -Actual $bad.Corruptions -Expected 2
        Assert-EzDarkFactoryEqual -Actual $bad.Leaks -Expected 1

        $checkCalls = @($fixture.State.Calls | Where-Object { $_[0] -ceq 'check' })
        foreach ($call in $checkCalls) {
            Assert-EzDarkFactoryTrue -Condition ($call -cnotcontains '-r') -Message 'Integrity diagnostics must never request automatic repair.'
        }

        $fixture.State.Mode = 'malformed-check-json'
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Test-EzDarkFactoryStoppedImageIntegrity -Root $fixture.Root -InstanceName 'check' -BaseId $fixture.BaseId -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner
        } -MessagePattern 'malformed JSON' | Out-Null
    }
    finally { Remove-EzDarkFactoryStorageFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Storage: reset validates replacement before changing original overlay' -ScriptBlock {
    $fixture = New-EzDarkFactoryStorageFixture
    try {
        $created = New-EzDarkFactoryInstanceOverlay -Root $fixture.Root -InstanceName 'reset-invalid' -BaseId $fixture.BaseId -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner
        $before = [IO.File]::ReadAllText($created.Disk)
        $fixture.State.Mode = 'wrong-replacement-format'
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Reset-EzDarkFactoryInstanceOverlayStorage -Root $fixture.Root -InstanceName 'reset-invalid' -BaseId $fixture.BaseId -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner
        } -MessagePattern 'backing format' | Out-Null
        Assert-EzDarkFactoryEqual -Actual ([IO.File]::ReadAllText($created.Disk)) -Expected $before -Message 'Invalid replacement must leave original overlay untouched.'
    }
    finally { Remove-EzDarkFactoryStorageFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Storage: failed replacement promotion restores original overlay' -ScriptBlock {
    $fixture = New-EzDarkFactoryStorageFixture
    try {
        $created = New-EzDarkFactoryInstanceOverlay -Root $fixture.Root -InstanceName 'reset-restore' -BaseId $fixture.BaseId -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner
        $before = [IO.File]::ReadAllText($created.Disk)
        $moveState = [pscustomobject]@{ Count = 0 }
        $mover = {
            param($source, $destination)
            $moveState.Count++
            if ($moveState.Count -eq 2) { throw [InvalidOperationException]::new('synthetic candidate promotion failure') }
            [IO.File]::Move($source, $destination)
        }.GetNewClosure()
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Reset-EzDarkFactoryInstanceOverlayStorage -Root $fixture.Root -InstanceName 'reset-restore' -BaseId $fixture.BaseId -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner -FileMover $mover
        } -MessagePattern 'synthetic candidate promotion failure' | Out-Null
        Assert-EzDarkFactoryEqual -Actual ([IO.File]::ReadAllText($created.Disk)) -Expected $before -Message 'Failed promotion must restore the original overlay.'
        Assert-EzDarkFactoryEqual -Actual $moveState.Count -Expected 3 -Message 'Expected original->backup, failed candidate->active, then backup->active restore.'
    }
    finally { Remove-EzDarkFactoryStorageFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Storage: successful reset commits only validated replacement and preserves base bytes' -ScriptBlock {
    $fixture = New-EzDarkFactoryStorageFixture
    try {
        $baseBefore = Get-EzDarkFactoryFileDigest -Path $fixture.BasePath -Algorithm SHA256
        $created = New-EzDarkFactoryInstanceOverlay -Root $fixture.Root -InstanceName 'reset-ok' -BaseId $fixture.BaseId -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner
        $firstGeneration = (Get-EzDarkFactoryStorageOverlayPayload -Path $created.Disk).generation
        $result = Reset-EzDarkFactoryInstanceOverlayStorage -Root $fixture.Root -InstanceName 'reset-ok' -BaseId $fixture.BaseId -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner
        $secondGeneration = (Get-EzDarkFactoryStorageOverlayPayload -Path $result.Disk).generation
        Assert-EzDarkFactoryTrue -Condition ([int]$secondGeneration -gt [int]$firstGeneration)
        Assert-EzDarkFactoryTrue -Condition $result.Replaced
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryFileDigest -Path $fixture.BasePath -Algorithm SHA256) -Expected $baseBefore
        $null = Test-EzDarkFactoryInstanceStorage -Root $fixture.Root -InstanceName 'reset-ok' -BaseId $fixture.BaseId -QemuImgRunner $fixture.Runner
    }
    finally { Remove-EzDarkFactoryStorageFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Storage: source contains no normal commit, rebase, unsafe create or base write shortcut' -ScriptBlock {
    $source = [IO.File]::ReadAllText((Join-Path $script:EzDarkFactoryRepositoryRoot 'src/EzDarkFactory/Storage.ps1'))
    Assert-EzDarkFactoryTrue -Condition ($source -notmatch "(?i)'commit'|\bqemu-img\s+commit\b") -Message 'Storage implementation must not commit mutable instance state into a base.'
    Assert-EzDarkFactoryTrue -Condition ($source -notmatch "(?i)'rebase'|\bqemu-img\s+rebase\b") -Message 'Storage implementation must not automatically rebase broken chains.'
    Assert-EzDarkFactoryTrue -Condition ($source -notmatch "(?i)'create'[^\r\n]*'-u'") -Message 'Storage implementation must not use unsafe backing creation.'
}

$storageWindowsSkip = $null
if (-not $script:EzDarkFactoryIsWindowsHost) {
    $storageWindowsSkip = 'Windows drive-letter and junction semantics require a Windows host; both required Windows CI lanes execute these cases.'
}

Add-EzDarkFactoryTest -Name 'Storage: relative backing string is invariant across Windows drive-letter relocation' -SkipReason $storageWindowsSkip -ScriptBlock {
    $baseId = 'base-' + ('a' * 64)
    $fromC = 'C:\ezdarkfactory root\runtime\instances\agent'
    $baseC = 'C:\ezdarkfactory root\runtime\bases\' + $baseId + '\base.qcow2'
    $fromD = 'D:\portable ezdarkfactory\runtime\instances\agent'
    $baseD = 'D:\portable ezdarkfactory\runtime\bases\' + $baseId + '\base.qcow2'

    $relativeC = Get-EzDarkFactoryStorageRelativePath -FromDirectory $fromC -TargetPath $baseC
    $relativeD = Get-EzDarkFactoryStorageRelativePath -FromDirectory $fromD -TargetPath $baseD
    Assert-EzDarkFactoryEqual -Actual $relativeD -Expected $relativeC
    Assert-EzDarkFactoryEqual -Actual $relativeC -Expected ('..\..\bases\' + $baseId + '\base.qcow2')

    Assert-EzDarkFactoryThrows -ScriptBlock {
        Get-EzDarkFactoryStorageRelativePath -FromDirectory $fromC -TargetPath $baseD
    } -MessagePattern 'cannot cross filesystem roots' | Out-Null
}

Add-EzDarkFactoryTest -Name 'Storage: junction instance directory is refused before overlay mutation' -SkipReason $storageWindowsSkip -ScriptBlock {
    $fixture = New-EzDarkFactoryStorageFixture
    $outside = New-EzDarkFactoryTestDirectory -Prefix 'storage junction outside target'
    $junction = $null
    try {
        [void][IO.Directory]::CreateDirectory($fixture.Paths.Instances)
        $junction = Join-Path $fixture.Paths.Instances 'junction-agent'
        $null = New-Item -ItemType Junction -Path $junction -Target $outside -ErrorAction Stop
        Assert-EzDarkFactoryThrows -ScriptBlock {
            New-EzDarkFactoryInstanceOverlay -Root $fixture.Root -InstanceName 'junction-agent' -BaseId $fixture.BaseId -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner
        } -MessagePattern 'reparse point' | Out-Null
        Assert-EzDarkFactoryEqual -Actual @(Get-ChildItem -LiteralPath $outside -Force).Count -Expected 0
    }
    finally {
        if ($null -ne $junction -and (Test-Path -LiteralPath $junction)) { Remove-Item -LiteralPath $junction -Force }
        Remove-EzDarkFactoryTestDirectory -Path $outside
        Remove-EzDarkFactoryStorageFixture $fixture
    }
}

Add-EzDarkFactoryTest -Name 'Storage: integrity checks and reset refuse running or ambiguous lifecycle evidence before qemu-img mutation' -ScriptBlock {
    $fixture = New-EzDarkFactoryStorageFixture
    try {
        $null = New-EzDarkFactoryInstanceOverlay -Root $fixture.Root -InstanceName 'guard-existing' -BaseId $fixture.BaseId -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner
        foreach ($state in @('running', 'unknown')) {
            $guard = New-EzDarkFactoryStorageLifecycleGuard -State $state -Source 'fixture process-state evidence'
            $before = $fixture.State.Calls.Count
            Assert-EzDarkFactoryThrows -ScriptBlock {
                Test-EzDarkFactoryStoppedImageIntegrity -Root $fixture.Root -InstanceName 'guard-existing' -BaseId $fixture.BaseId -LifecycleGuard $guard -QemuImgRunner $fixture.Runner
            } -MessagePattern 'requires positively proven' | Out-Null
            Assert-EzDarkFactoryEqual -Actual $fixture.State.Calls.Count -Expected $before -Message 'Unsafe integrity guard must refuse before qemu-img is invoked.'

            Assert-EzDarkFactoryThrows -ScriptBlock {
                Reset-EzDarkFactoryInstanceOverlayStorage -Root $fixture.Root -InstanceName 'guard-existing' -BaseId $fixture.BaseId -LifecycleGuard $guard -QemuImgRunner $fixture.Runner
            } -MessagePattern 'requires positively proven' | Out-Null
            Assert-EzDarkFactoryEqual -Actual $fixture.State.Calls.Count -Expected $before -Message 'Unsafe reset guard must refuse before qemu-img or filesystem mutation.'
        }
    }
    finally { Remove-EzDarkFactoryStorageFixture $fixture }
}
