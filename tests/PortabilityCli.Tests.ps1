function ConvertTo-EzDarkFactoryPortabilityCliLiteral {
    param([AllowEmptyString()][string]$Text)
    return "'" + $Text.Replace("'", "''") + "'"
}

function New-EzDarkFactoryPortabilityCliFixture {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'portability CLI [isolated]'
    # Replace only operation boundaries in this disposable copied module. The
    # actual entry point, argument parser, result envelope and formatters execute
    # unchanged in child PowerShell processes. No real VM/disk operation runs.
    $stubs = @'
function Save-EzDarkFactoryCliBoundaryCall {
    param([string]$Root, [string]$Operation, [object]$Received)
    Write-EzDarkFactoryJson -Path (Join-Path $Root 'cli-boundary-call.json') -Value ([pscustomobject]@{
        schemaVersion = 1; operation = $Operation; received = $Received
    })
}
function New-EzDarkFactoryCliBoundaryInstance {
    param([string]$Name, [string]$Profile, [AllowNull()][object]$Cpus, [AllowNull()][object]$MemoryMiB,
        [object]$Received, [bool]$Sensitive = $false)
    return [pscustomobject][ordered]@{
        name = $Name; profile = $(if ($Profile) { $Profile } else { 'normal' })
        cpus = $(if ($null -ne $Cpus) { [int]$Cpus } else { 4 })
        memoryMiB = $(if ($null -ne $MemoryMiB) { [int]$MemoryMiB } else { 8192 })
        baseId = 'base-' + ('a' * 64); baseSelection = 'explicit'; sshPort = 22007
        warnings = @(); sensitiveState = $Sensitive; received = $Received
    }
}
function New-EzDarkFactoryManagedInstance {
    param($Root, $InstanceName, $BaseId, $Profile, $Cpus, $MemoryMiB)
    $received = [pscustomobject]@{ root = $Root; name = $InstanceName; baseId = $BaseId; profile = $Profile; cpus = $Cpus; memoryMiB = $MemoryMiB }
    Save-EzDarkFactoryCliBoundaryCall -Root $Root -Operation create -Received $received
    return New-EzDarkFactoryCliBoundaryInstance -Name $InstanceName -Profile $Profile -Cpus $Cpus -MemoryMiB $MemoryMiB -Received $received
}
function Copy-EzDarkFactoryManagedInstance {
    param($Root, $SourceInstanceName, $DestinationInstanceName, $Mode)
    $received = [pscustomobject]@{ root = $Root; source = $SourceInstanceName; destination = $DestinationInstanceName; mode = $Mode }
    Save-EzDarkFactoryCliBoundaryCall -Root $Root -Operation clone -Received $received
    $result = New-EzDarkFactoryCliBoundaryInstance -Name $DestinationInstanceName -Profile light -Cpus 2 -MemoryMiB 4096 -Received $received -Sensitive ($Mode -ceq 'stateful')
    $result | Add-Member -NotePropertyName mode -NotePropertyValue $Mode
    $result | Add-Member -NotePropertyName sourceName -NotePropertyValue $SourceInstanceName
    return $result
}
function Reset-EzDarkFactoryManagedInstance {
    param($Root, $InstanceName)
    $received = [pscustomobject]@{ root = $Root; name = $InstanceName }
    Save-EzDarkFactoryCliBoundaryCall -Root $Root -Operation reset -Received $received
    return [pscustomobject]@{
        name = $InstanceName; state = 'CREATED'; baseId = 'base-' + ('b' * 64)
        identityGeneration = 'c' * 32; resetBaseline = 'derived'; sensitiveState = $true
        recoveryArtifact = @('retained reset backup.qcow2'); received = $received
    }
}
function Export-EzDarkFactoryManagedInstance {
    param($Root, $InstanceName, $DestinationDirectory)
    $received = [pscustomobject]@{ root = $Root; name = $InstanceName; destinationDirectory = $DestinationDirectory }
    Save-EzDarkFactoryCliBoundaryCall -Root $Root -Operation export -Received $received
    return [pscustomobject]@{
        Directory = $DestinationDirectory; Image = Join-Path $DestinationDirectory 'disk.qcow2'
        ManifestPath = Join-Path $DestinationDirectory 'manifest.json'
        Manifest = [pscustomobject]@{ imageSha256 = 'd' * 64 }; received = $received
    }
}
function Import-EzDarkFactoryManagedInstance {
    param($Root, $InstanceName, $ImagePath, $ManifestPath, $Profile, $Cpus, $MemoryMiB)
    $received = [pscustomobject]@{ root = $Root; name = $InstanceName; imagePath = $ImagePath; manifestPath = $ManifestPath; profile = $Profile; cpus = $Cpus; memoryMiB = $MemoryMiB }
    Save-EzDarkFactoryCliBoundaryCall -Root $Root -Operation import -Received $received
    return New-EzDarkFactoryCliBoundaryInstance -Name $InstanceName -Profile $Profile -Cpus $Cpus -MemoryMiB $MemoryMiB -Received $received -Sensitive $true
}
function Test-EzDarkFactoryPortableBundle {
    param($Root)
    $received = [pscustomobject]@{ root = $Root }
    Save-EzDarkFactoryCliBoundaryCall -Root $Root -Operation 'portability check' -Received $received
    return [pscustomobject]@{ Valid = $true; Root = $Root; InstanceCount = 2; Instances = @(); received = $received }
}
'@
    [IO.File]::AppendAllText((Join-Path $root 'src/EzDarkFactory/Portability.ps1'), ("`n" + $stubs + "`n"), (New-Object Text.UTF8Encoding($false)))
    return $root
}

function Invoke-EzDarkFactoryPortabilityCliProcess {
    param([string]$Root, [AllowEmptyCollection()][AllowEmptyString()][string[]]$Arguments)
    $tokens = @($Arguments | ForEach-Object { ConvertTo-EzDarkFactoryPortabilityCliLiteral $_ }) -join ', '
    $command = '$ErrorActionPreference = ''Stop''; $cliTokens = @(' + $tokens + '); & ' +
        (ConvertTo-EzDarkFactoryPortabilityCliLiteral (Join-Path $Root 'ezdarkfactory.ps1')) + ' @cliTokens; exit $LASTEXITCODE'
    return Invoke-EzDarkFactoryTestPowerShell -CommandText $command
}

function Assert-EzDarkFactoryPortabilityCliEnvelope {
    param([object]$Result, [AllowNull()][object]$Command, [int]$ExitCode)
    Assert-EzDarkFactoryEqual -Actual $Result.ExitCode -Expected $ExitCode
    Assert-EzDarkFactoryEqual -Actual $Result.StandardError -Expected '' -Message 'JSON results must not mix stderr diagnostics with their envelope.'
    $values = @($Result.StandardOutput | ConvertFrom-Json -ErrorAction Stop)
    Assert-EzDarkFactoryEqual -Actual $values.Count -Expected 1 -Message 'Each CLI invocation must return exactly one JSON envelope.'
    $value = $values[0]
    Assert-EzDarkFactoryEqual -Actual @($value.PSObject.Properties.Name | Sort-Object) -Expected @('command', 'data', 'error', 'exitCode', 'schemaVersion', 'success')
    Assert-EzDarkFactoryEqual -Actual $value.schemaVersion -Expected 1
    Assert-EzDarkFactoryEqual -Actual $value.command -Expected $Command
    Assert-EzDarkFactoryEqual -Actual $value.exitCode -Expected $ExitCode
    Assert-EzDarkFactoryEqual -Actual $value.success -Expected ($ExitCode -eq 0)
    if ($ExitCode -eq 0) { Assert-EzDarkFactoryEqual -Actual $value.error -Expected $null }
    else {
        Assert-EzDarkFactoryEqual -Actual $value.data -Expected $null
        Assert-EzDarkFactoryTrue -Condition (-not [string]::IsNullOrWhiteSpace([string]$value.error.message))
    }
    return $value
}

Add-EzDarkFactoryTest -Name 'Portability CLI: explicit modes and path/resource tokens reach the correct operation unchanged' -ScriptBlock {
    $root = New-EzDarkFactoryPortabilityCliFixture
    try {
        $image = Join-Path $root 'inputs with spaces [copy] & dollars $/source image.qcow2'
        $manifest = Join-Path $root "O'Brien export manifest.json"
        $destination = Join-Path $root "O'Brien export [snapshot]"
        $baseId = 'base-' + ('e' * 64)
        $cases = @(
            @{ Tokens = @('cLoNe', 'Source-ONE', 'Fresh-Copy', '-mOdE', 'FRESH', '-Json'); Command = 'clone'; Expected = @{ source = 'Source-ONE'; destination = 'Fresh-Copy'; mode = 'fresh' } },
            @{ Tokens = @('-JSON', 'CLONE', 'source-two', 'saved-copy', '-MODE', 'STATEFUL'); Command = 'clone'; Expected = @{ source = 'source-two'; destination = 'saved-copy'; mode = 'stateful' } },
            @{ Tokens = @('RESET', 'Source-ONE', '-Json'); Command = 'reset'; Expected = @{ name = 'Source-ONE' } },
            @{ Tokens = @('export', 'source-two', $destination, '-Json'); Command = 'export'; Expected = @{ name = 'source-two'; destinationDirectory = $destination } },
            @{ Tokens = @('ImPoRt', 'imported', $image, '-ManifestPath', $manifest, '-PROFILE', 'custom', '-CPUS', '3', '-memorymib', '6144', '-Json'); Command = 'import'; Expected = @{ name = 'imported'; imagePath = $image; manifestPath = $manifest; profile = 'custom'; cpus = 3; memoryMiB = 6144 } },
            @{ Tokens = @('create', 'clean', '-BaseId', $baseId, '-Profile', 'light', '-Json'); Command = 'create'; Expected = @{ name = 'clean'; baseId = $baseId; profile = 'light' } },
            @{ Tokens = @('PORTABILITY', 'CHECK', '-Json'); Command = 'portability check'; Expected = @{} }
        )
        foreach ($case in $cases) {
            $result = Invoke-EzDarkFactoryPortabilityCliProcess -Root $root -Arguments $case.Tokens
            $value = Assert-EzDarkFactoryPortabilityCliEnvelope -Result $result -Command $case.Command -ExitCode 0
            Assert-EzDarkFactoryEqual -Actual $value.data.received.root -Expected $root
            foreach ($field in $case.Expected.Keys) {
                Assert-EzDarkFactoryEqual -Actual $value.data.received.$field -Expected $case.Expected[$field] -Message ("Incorrect CLI routing for $($case.Command) field '$field'.")
            }
            $call = Read-EzDarkFactoryJson -Path (Join-Path $root 'cli-boundary-call.json')
            Assert-EzDarkFactoryEqual -Actual $call.operation -Expected $case.Command
        }
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root 'runtime'))) -Message 'CLI fixture unexpectedly crossed a real storage boundary.'
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Portability CLI: ambiguous destructive syntax is refused before dispatch' -ScriptBlock {
    $root = New-EzDarkFactoryPortabilityCliFixture
    try {
        $cases = @(
            @{ tokens = @('clone', 'source', 'copy') },
            @{ tokens = @('clone', 'source', 'copy', '-Mode') },
            @{ tokens = @('clone', 'source', 'copy', '-Mode', 'automatic') },
            @{ tokens = @('clone', 'source', 'copy', '-Mode', 'fresh', '-Mode', 'stateful') },
            @{ tokens = @('clone', 'source', 'copy', '-Fresh', 'stateful') },
            @{ tokens = @('clone', 'source', '../copy', '-Mode', 'stateful') },
            @{ tokens = @('reset') },
            @{ tokens = @('reset', 'source', 'extra') },
            @{ tokens = @('reset', 'NUL') },
            @{ tokens = @('export', 'source') },
            @{ tokens = @('export', 'source', '') },
            @{ tokens = @('export', 'source', 'destination', 'extra') },
            @{ tokens = @('import', 'copy') },
            @{ tokens = @('import', 'copy', '') },
            @{ tokens = @('import', 'copy', 'disk.qcow2', '-ManifestPath') },
            @{ tokens = @('import', 'copy', 'disk.qcow2', '-Profile', 'normal', '-PROFILE', 'light') },
            @{ tokens = @('import', 'copy', 'disk.qcow2', '-Cpus', '2', '-CPUS', '3') },
            @{ tokens = @('import', 'copy', 'disk.qcow2', '-MemoryMiB', '4096', '-memorymib', '8192') },
            @{ tokens = @('import', 'copy', 'disk.qcow2', '-ManifestPath', 'a.json', '-manifestpath', 'b.json') },
            @{ tokens = @('import', 'copy', 'disk.qcow2', '-Cpus', '2.5') },
            @{ tokens = @('import', 'copy', 'disk.qcow2', '-Cpus', '-1') },
            @{ tokens = @('import', 'copy', 'disk.qcow2', '-MemoryMiB', '2147483648') },
            @{ tokens = @('import', 'copy', 'disk.qcow2', '-Profile', '') },
            @{ tokens = @('import', 'copy', 'disk.qcow2', '-BaseId', ('base-' + ('a' * 64))) },
            @{ tokens = @('create', 'copy', '-ManifestPath', 'export.json') },
            @{ tokens = @('portability') },
            @{ tokens = @('portability', 'repair') },
            @{ tokens = @('portability', 'check', '-Force') },
            @{ tokens = @('-Json', 'clone', 'source', 'copy', '-Mode', 'fresh', '-Json') }
        )
        $serialized = ConvertTo-EzDarkFactoryPortabilityCliLiteral ($cases | ConvertTo-Json -Depth 6 -Compress)
        $modulePath = ConvertTo-EzDarkFactoryPortabilityCliLiteral (Join-Path $root 'src/EzDarkFactory/EzDarkFactory.psd1')
        $rootLiteral = ConvertTo-EzDarkFactoryPortabilityCliLiteral $root
        $command = '$ErrorActionPreference = ''Stop''; Import-Module ' + $modulePath + ' -Force; $cases = ' + $serialized +
            ' | ConvertFrom-Json; $results = @($cases | ForEach-Object { Invoke-EzDarkFactoryCommand -Root ' + $rootLiteral + ' -Arguments ([string[]]$_.tokens) }); $results | ConvertTo-Json -Depth 8 -Compress; exit 0'
        $run = Invoke-EzDarkFactoryTestPowerShell -CommandText $command
        Assert-EzDarkFactoryEqual -Actual $run.ExitCode -Expected 0
        Assert-EzDarkFactoryEqual -Actual $run.StandardError -Expected ''
        # Windows PowerShell 5.1 emits a JSON array as one pipeline object.
        # Direct assignment keeps that array instead of nesting it in @(...).
        $results = $run.StandardOutput | ConvertFrom-Json -ErrorAction Stop
        Assert-EzDarkFactoryEqual -Actual $results.Count -Expected $cases.Count
        foreach ($result in $results) {
            Assert-EzDarkFactoryEqual -Actual $result.success -Expected $false
            Assert-EzDarkFactoryEqual -Actual $result.exitCode -Expected 2
            Assert-EzDarkFactoryEqual -Actual $result.data -Expected $null
            Assert-EzDarkFactoryEqual -Actual $result.error.code -Expected 'invalid_arguments'
            Assert-EzDarkFactoryTrue -Condition ($result.error.message -match 'help')
        }
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root 'cli-boundary-call.json'))) -Message 'Invalid syntax invoked a lifecycle/storage operation.'
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Portability CLI: actual entry point returns usage failure in human and JSON modes' -ScriptBlock {
    $root = New-EzDarkFactoryPortabilityCliFixture
    try {
        $human = Invoke-EzDarkFactoryPortabilityCliProcess -Root $root -Arguments @('clone', 'source', 'destination')
        Assert-EzDarkFactoryEqual -Actual $human.ExitCode -Expected 2
        Assert-EzDarkFactoryEqual -Actual $human.StandardOutput -Expected ''
        Assert-EzDarkFactoryTrue -Condition ($human.StandardError -match 'Choose the mode explicitly' -and $human.StandardError -match 'help')
        $json = Invoke-EzDarkFactoryPortabilityCliProcess -Root $root -Arguments @('import', 'destination', 'disk.qcow2', '-BaseId', 'forbidden', '-Json')
        $value = Assert-EzDarkFactoryPortabilityCliEnvelope -Result $json -Command 'import' -ExitCode 2
        Assert-EzDarkFactoryEqual -Actual $value.error.code -Expected 'invalid_arguments'
        Assert-EzDarkFactoryTrue -Condition ($value.error.message -match 'Unknown import option')
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root 'cli-boundary-call.json')))
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Portability CLI: human results explain baseline sensitivity and retained recovery material' -ScriptBlock {
    $root = New-EzDarkFactoryPortabilityCliFixture
    try {
        $cases = @(
            @{ Tokens = @('clone', 'source', 'fresh-copy', '-Mode', 'fresh'); Expected = @('Created fresh-copy', 'clone mode: fresh; source: source', 'SSH reservation: 127.0.0.1:22007'); Sensitive = $false },
            @{ Tokens = @('clone', 'source', 'saved-copy', '-Mode', 'stateful'); Expected = @('Created saved-copy', 'clone mode: stateful; source: source', 'immutable baseline may contain credentials'); Sensitive = $true },
            @{ Tokens = @('reset', 'saved-copy'); Expected = @('Reset saved-copy: CREATED', 'reset restores this snapshot baseline', 'retained reset backup.qcow2'); Sensitive = $true },
            @{ Tokens = @('export', 'source', (Join-Path $root 'saved export')); Expected = @('Exported standalone image:', 'manifest.json', ('d' * 64), 'bundle may contain credentials'); Sensitive = $true },
            @{ Tokens = @('import', 'imported', (Join-Path $root 'saved export/disk.qcow2')); Expected = @('Created imported', 'SSH reservation: 127.0.0.1:22007', 'immutable baseline may contain credentials'); Sensitive = $true },
            @{ Tokens = @('portability', 'check'); Expected = @('Cold portability validated: 2 stopped instances', 'all guests remain stopped', 'again at the destination'); Sensitive = $false }
        )
        foreach ($case in $cases) {
            $result = Invoke-EzDarkFactoryPortabilityCliProcess -Root $root -Arguments $case.Tokens
            Assert-EzDarkFactoryEqual -Actual $result.ExitCode -Expected 0
            Assert-EzDarkFactoryEqual -Actual $result.StandardError -Expected ''
            foreach ($text in $case.Expected) {
                Assert-EzDarkFactoryTrue -Condition ($result.StandardOutput.Contains($text)) -Message ("Missing user-facing portability result '$text'.")
            }
            Assert-EzDarkFactoryEqual -Actual ($result.StandardOutput -match 'sensitive state:') -Expected $case.Sensitive
        }
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Portability CLI: successful JSON stays usable in a same-host PowerShell pipeline' -ScriptBlock {
    $root = New-EzDarkFactoryPortabilityCliFixture
    try {
        $entry = ConvertTo-EzDarkFactoryPortabilityCliLiteral (Join-Path $root 'ezdarkfactory.ps1')
        $command = '$ErrorActionPreference = ''Stop''; $values = @(& ' + $entry +
            ' clone source piped-copy -Mode STATEFUL -Json | ConvertFrom-Json); if ($LASTEXITCODE -ne 0 -or $values.Count -ne 1 -or -not $values[0].success -or $values[0].data.mode -cne ''stateful'' -or $values[0].data.name -cne ''piped-copy'') { exit 91 }; [Console]::Write($values[0].data.name); exit 0'
        $result = Invoke-EzDarkFactoryTestPowerShell -CommandText $command
        Assert-EzDarkFactoryEqual -Actual $result.ExitCode -Expected 0
        Assert-EzDarkFactoryEqual -Actual $result.StandardOutput -Expected 'piped-copy'
        Assert-EzDarkFactoryEqual -Actual $result.StandardError -Expected ''
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Portability CLI: missing real instances remain execution failures without a false success envelope' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'portability CLI missing instances'
    try {
        foreach ($tokens in @(
            @('reset', 'absent', '-Json'),
            @('clone', 'absent', 'copy', '-Mode', 'stateful', '-Json'),
            @('export', 'absent', (Join-Path $root 'export'), '-Json')
        )) {
            $run = Invoke-EzDarkFactoryPortabilityCliProcess -Root $root -Arguments $tokens
            $value = Assert-EzDarkFactoryPortabilityCliEnvelope -Result $run -Command $null -ExitCode 1
            Assert-EzDarkFactoryEqual -Actual $value.error.code -Expected 'execution_failed'
            Assert-EzDarkFactoryTrue -Condition ($value.error.message -match 'instance.json|does not exist')
        }
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root 'runtime/instances/copy')))
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root 'export')))
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Portability CLI: help exposes explicit copy choices and export/import argument direction' -ScriptBlock {
    $result = Invoke-EzDarkFactoryCommand -Arguments @('help', '-Json')
    $commands = @($result.data.commands | ForEach-Object { $_.name })
    foreach ($required in @('reset <name>', 'clone <source> <destination> -Mode fresh|stateful', 'export <name> <new-directory>', 'import <name> <image> [options]', 'portability check')) {
        Assert-EzDarkFactoryTrue -Condition ($commands -ccontains $required) -Message ("Help omits the implemented command '$required'.")
    }
    $help = @(Write-EzDarkFactoryResult -Result $result) -join "`n"
    Assert-EzDarkFactoryTrue -Condition ($help -match 'same baseline with a fresh overlay' -and $help -match 'independent sensitive stateful snapshot')
    Assert-EzDarkFactoryTrue -Condition ($help -match '-ManifestPath, -Profile, -Cpus, -MemoryMiB')
    Assert-EzDarkFactoryTrue -Condition ($help -match 'docs/PORTABILITY.md')
}
