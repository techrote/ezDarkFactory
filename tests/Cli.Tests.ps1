function ConvertTo-EzDarkFactoryTestLiteral {
    param([AllowEmptyString()][string]$Text)
    return "'" + $Text.Replace("'", "''") + "'"
}

function Invoke-EzDarkFactoryCliForTest {
    param(
        [AllowEmptyCollection()][AllowEmptyString()][string[]]$ArgumentList = @(),
        [string]$Root = $script:EzDarkFactoryRepositoryRoot,
        [string]$WorkingDirectory = $script:EzDarkFactoryRepositoryRoot
    )
    $arguments = @($ArgumentList | ForEach-Object { ConvertTo-EzDarkFactoryTestLiteral $_ }) -join ', '
    $command = '$ezdarkfactoryCliArguments = @(' + $arguments + '); & ' + (ConvertTo-EzDarkFactoryTestLiteral (Join-Path $Root 'ezdarkfactory.ps1')) + ' @ezdarkfactoryCliArguments; exit $LASTEXITCODE'
    return Invoke-EzDarkFactoryTestPowerShell -CommandText $command -WorkingDirectory $WorkingDirectory
}

function Assert-EzDarkFactoryJsonEnvelope {
    param([object]$Result, [string]$Command, [int]$ExitCode)
    Assert-EzDarkFactoryEqual -Actual $Result.ExitCode -Expected $ExitCode
    Assert-EzDarkFactoryEqual -Actual $Result.StandardError -Expected '' -Message 'Structured output leaked diagnostics to stderr.'
    $value = $Result.StandardOutput | ConvertFrom-Json -ErrorAction Stop
    Assert-EzDarkFactoryEqual -Actual $value.schemaVersion -Expected 1
    Assert-EzDarkFactoryEqual -Actual $value.success -Expected ($ExitCode -eq 0)
    Assert-EzDarkFactoryEqual -Actual $value.command -Expected $Command
    Assert-EzDarkFactoryEqual -Actual $value.exitCode -Expected $ExitCode
    Assert-EzDarkFactoryEqual -Actual @($value.PSObject.Properties.Name | Sort-Object) -Expected @('command', 'data', 'error', 'exitCode', 'schemaVersion', 'success')
    if ($ExitCode -eq 0) {
        Assert-EzDarkFactoryTrue -Condition ($null -ne $value.data)
        Assert-EzDarkFactoryEqual -Actual $value.error -Expected $null
    }
    else {
        Assert-EzDarkFactoryEqual -Actual $value.data -Expected $null
        Assert-EzDarkFactoryTrue -Condition (-not [string]::IsNullOrWhiteSpace($value.error.message))
        Assert-EzDarkFactoryTrue -Condition (-not [string]::IsNullOrWhiteSpace($value.error.code))
    }
    return $value
}

Add-EzDarkFactoryTest -Name 'CLI: help and empty input provide human usage' -ScriptBlock {
    foreach ($arguments in @(@('help'), @())) {
        $result = Invoke-EzDarkFactoryCliForTest -ArgumentList $arguments
        Assert-EzDarkFactoryEqual -Actual $result.ExitCode -Expected 0
        Assert-EzDarkFactoryEqual -Actual $result.StandardError -Expected ''
        Assert-EzDarkFactoryTrue -Condition ($result.StandardOutput -match 'Usage:.*ezdarkfactory\.ps1')
        Assert-EzDarkFactoryTrue -Condition ($result.StandardOutput -match 'help' -and $result.StandardOutput -match 'version')
        Assert-EzDarkFactoryTrue -Condition ($result.StandardOutput -match 'doctor' -and $result.StandardOutput -match 'bootstrap' -and $result.StandardOutput -match 'base acquire' -and $result.StandardOutput -match 'base build') -Message 'Help must list all implemented host, source and prepared-base commands.'
        Assert-EzDarkFactoryTrue -Condition ($result.StandardOutput -match 'status <name>' -and $result.StandardOutput -match 'start <name>' -and $result.StandardOutput -match 'stop <name>') -Message 'Help must list implemented lifecycle commands.'
        Assert-EzDarkFactoryTrue -Condition ($result.StandardOutput -match 'ssh <name>' -and $result.StandardOutput -match 'exec <name> -- <command>' -and $result.StandardOutput -match 'copy-to <name>' -and $result.StandardOutput -match 'copy-from <name>') -Message 'Help must list implemented SSH control commands.'
        Assert-EzDarkFactoryTrue -Condition ($result.StandardOutput -match 'create <name>' -and $result.StandardOutput -match '(?m)^\s+list\s') -Message 'Help must list the EDF-008 create and list commands.'
        Assert-EzDarkFactoryTrue -Condition ($result.StandardOutput -match 'authenticated guest readiness' -and $result.StandardOutput -match 'named instances' -and $result.StandardOutput -match 'cold relocation are implemented') -Message 'Help must describe implemented coding readiness, named instances and portability.'
    }
}

Add-EzDarkFactoryTest -Name 'CLI: list of an empty registry succeeds in human and structured modes' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'cli empty registry'
    try {
        $human = Invoke-EzDarkFactoryCliForTest -ArgumentList @('list') -Root $root
        Assert-EzDarkFactoryEqual -Actual $human.ExitCode -Expected 0
        Assert-EzDarkFactoryEqual -Actual $human.StandardError -Expected ''
        Assert-EzDarkFactoryTrue -Condition ($human.StandardOutput -match 'No managed instances')

        $json = Invoke-EzDarkFactoryCliForTest -ArgumentList @('list', '-Json') -Root $root
        $value = Assert-EzDarkFactoryJsonEnvelope -Result $json -Command 'list' -ExitCode 0
        Assert-EzDarkFactoryEqual -Actual $value.data.count -Expected 0
        Assert-EzDarkFactoryEqual -Actual @($value.data.instances).Count -Expected 0
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'CLI: create validates its public option grammar before execution' -ScriptBlock {
    foreach ($case in @(
        [pscustomobject]@{ Args = @('create'); Pattern = 'requires an instance name' }
        [pscustomobject]@{ Args = @('create', '..'); Pattern = 'invalid|unsafe' }
        [pscustomobject]@{ Args = @('create', 'agent', '-Unknown', 'x'); Pattern = 'Unknown create option' }
        [pscustomobject]@{ Args = @('create', 'agent', '-Profile'); Pattern = 'requires a value' }
        [pscustomobject]@{ Args = @('create', 'agent', '-Cpus', 'abc'); Pattern = 'positive integer' }
        [pscustomobject]@{ Args = @('create', 'agent', '-Cpus', '4', '-Cpus', '8'); Pattern = 'at most once' }
    )) {
        $result = Invoke-EzDarkFactoryCliForTest -ArgumentList $case.Args
        Assert-EzDarkFactoryEqual -Actual $result.ExitCode -Expected 2
        Assert-EzDarkFactoryTrue -Condition ($result.StandardError -match $case.Pattern) -Message ('Unexpected create argument error for: ' + ($case.Args -join ' '))
    }
}

Add-EzDarkFactoryTest -Name 'CLI: human version matches the module version' -ScriptBlock {
    $result = Invoke-EzDarkFactoryCliForTest -ArgumentList @('version')
    Assert-EzDarkFactoryEqual -Actual $result.ExitCode -Expected 0
    Assert-EzDarkFactoryEqual -Actual $result.StandardError -Expected ''
    Assert-EzDarkFactoryEqual -Actual $result.StandardOutput.Trim() -Expected ('ezdarkfactory ' + (Get-EzDarkFactoryVersion))
    Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryVersion) -Expected '0.1.0'
}

$structuredCases = @(
    @{ Arguments = @('help', '-Json'); Command = 'help' },
    @{ Arguments = @('-Json', 'version'); Command = 'version' },
    @{ Arguments = @('version', '-Json'); Command = 'version' },
    @{ Arguments = @('-Json'); Command = 'help' },
    @{ Arguments = @('VeRsIoN', '-jSoN'); Command = 'version' }
)
foreach ($structuredCase in $structuredCases) {
    $testName = 'CLI: structured ' + ($structuredCase.Arguments -join ' ')
    if ($structuredCase.Arguments[0] -ceq 'VeRsIoN') { $testName += ' (case-insensitive parsing)' }
    Add-EzDarkFactoryTest -Name $testName -Data $structuredCase -ScriptBlock {
        param($case)
        $result = Invoke-EzDarkFactoryCliForTest -ArgumentList $case.Arguments
        $value = Assert-EzDarkFactoryJsonEnvelope -Result $result -Command $case.Command -ExitCode 0
        Assert-EzDarkFactoryEqual -Actual $value.data.version -Expected (Get-EzDarkFactoryVersion)
    }
}

Add-EzDarkFactoryTest -Name 'CLI: JSON is available to a same-host PowerShell pipeline' -ScriptBlock {
    $entry = ConvertTo-EzDarkFactoryTestLiteral (Join-Path $script:EzDarkFactoryRepositoryRoot 'ezdarkfactory.ps1')
    $command = '$ErrorActionPreference = ''Stop''; $value = & ' + $entry + ' version -Json | ConvertFrom-Json; if ($value.data.version -ne ''0.1.0'' -or -not $value.success) { exit 91 }; [Console]::Write($value.data.version); exit 0'
    $result = Invoke-EzDarkFactoryTestPowerShell -CommandText $command
    Assert-EzDarkFactoryEqual -Actual $result.ExitCode -Expected 0
    Assert-EzDarkFactoryEqual -Actual $result.StandardOutput -Expected '0.1.0'
    Assert-EzDarkFactoryEqual -Actual $result.StandardError -Expected ''
}

Add-EzDarkFactoryTest -Name 'CLI: direct File invocation produces clean JSON without a wrapper prelude' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'direct File [copy]'
    $process = New-Object Diagnostics.Process
    try {
        $executableName = 'pwsh'
        if ($script:EzDarkFactoryIsWindowsHost) {
            $executableName = 'pwsh.exe'
            if ($PSVersionTable.PSVersion.Major -eq 5) { $executableName = 'powershell.exe' }
        }
        $process.StartInfo.FileName = Join-Path $PSHOME $executableName
        # This source-derived absolute .ps1 path contains no quotes or trailing
        # backslash. No EncodedCommand or preference-setting test wrapper runs.
        $process.StartInfo.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + (Join-Path $root 'ezdarkfactory.ps1') + '" version -Json'
        $process.StartInfo.WorkingDirectory = $script:EzDarkFactoryRepositoryRoot
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        Assert-EzDarkFactoryTrue -Condition ($process.Start())
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            $process.Kill()
            [void]$process.WaitForExit(5000)
            throw 'Direct File CLI invocation timed out.'
        }
        Assert-EzDarkFactoryTrue -Condition ($stdout.Wait(5000) -and $stderr.Wait(5000))
        $result = [pscustomobject]@{ ExitCode = $process.ExitCode; StandardOutput = $stdout.Result; StandardError = $stderr.Result }
        $value = Assert-EzDarkFactoryJsonEnvelope -Result $result -Command 'version' -ExitCode 0
        Assert-EzDarkFactoryEqual -Actual $value.data.version -Expected '0.1.0'
    }
    finally {
        $process.Dispose()
        Remove-EzDarkFactoryTestDirectory -Path $root
    }
}

$invalidCliCases = @(
    @{ Name = 'unknown command'; Arguments = @('not-a-command') },
    @{ Name = 'future command'; Arguments = @('create') },
    @{ Name = 'malformed exec without separator'; Arguments = @('exec', 'agent', 'echo') },
    @{ Name = 'empty exec payload'; Arguments = @('exec', 'agent', '--') },
    @{ Name = 'malformed copy-to'; Arguments = @('copy-to', 'agent', 'only-one-path') },
    @{ Name = 'extra positional argument'; Arguments = @('help', 'extra') },
    @{ Name = 'unsupported switch'; Arguments = @('version', '-Unexpected') },
    @{ Name = 'missing command value'; Arguments = @('') }
)
foreach ($invalidCliCase in $invalidCliCases) {
    Add-EzDarkFactoryTest -Name ('CLI: human error for ' + $invalidCliCase.Name) -Data $invalidCliCase -ScriptBlock {
        param($case)
        $result = Invoke-EzDarkFactoryCliForTest -ArgumentList $case.Arguments
        Assert-EzDarkFactoryEqual -Actual $result.ExitCode -Expected 2
        Assert-EzDarkFactoryEqual -Actual $result.StandardOutput -Expected ''
        Assert-EzDarkFactoryTrue -Condition ($result.StandardError -match 'help') -Message 'Usage errors must direct the user to help.'
    }
}

$invalidJsonCases = @(
    @{ Name = 'unknown command'; Arguments = @('not-a-command', '-Json'); Command = 'not-a-command' },
    @{ Name = 'extra argument'; Arguments = @('-Json', 'help', 'extra'); Command = 'help' },
    @{ Name = 'duplicate JSON switch'; Arguments = @('-Json', 'version', '-Json'); Command = 'version' }
)
foreach ($invalidJsonCase in $invalidJsonCases) {
    Add-EzDarkFactoryTest -Name ('CLI: structured error for ' + $invalidJsonCase.Name) -Data $invalidJsonCase -ScriptBlock {
        param($case)
        $result = Invoke-EzDarkFactoryCliForTest -ArgumentList $case.Arguments
        $value = Assert-EzDarkFactoryJsonEnvelope -Result $result -Command $case.Command -ExitCode 2
        Assert-EzDarkFactoryTrue -Condition ($value.error.message -match 'help')
    }
}

Add-EzDarkFactoryTest -Name 'CLI: copied checkout with spaces and brackets works from an unrelated directory' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'portable [copy] with spaces'
    $elsewhere = New-EzDarkFactoryTestDirectory -Prefix 'CLI working directory'
    try {
        $result = Invoke-EzDarkFactoryCliForTest -ArgumentList @('version', '-Json') -Root $root -WorkingDirectory $elsewhere
        $value = Assert-EzDarkFactoryJsonEnvelope -Result $result -Command 'version' -ExitCode 0
        Assert-EzDarkFactoryEqual -Actual $value.data.version -Expected '0.1.0'
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root '.git')))
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root 'runtime')))
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $elsewhere 'runtime')))
    }
    finally {
        Remove-EzDarkFactoryTestDirectory -Path $root
        Remove-EzDarkFactoryTestDirectory -Path $elsewhere
    }
}

Add-EzDarkFactoryTest -Name 'CLI: a broken checkout has a clean JSON execution-failure result' -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'broken checkout'
    try {
        Copy-Item -LiteralPath (Join-Path $script:EzDarkFactoryRepositoryRoot 'ezdarkfactory.ps1') -Destination $root
        $result = Invoke-EzDarkFactoryCliForTest -ArgumentList @('version', '-Json') -Root $root
        Assert-EzDarkFactoryEqual -Actual $result.ExitCode -Expected 1
        Assert-EzDarkFactoryEqual -Actual $result.StandardError -Expected ''
        $value = $result.StandardOutput | ConvertFrom-Json -ErrorAction Stop
        Assert-EzDarkFactoryEqual -Actual $value.schemaVersion -Expected 1
        Assert-EzDarkFactoryEqual -Actual $value.success -Expected $false
        Assert-EzDarkFactoryEqual -Actual $value.exitCode -Expected 1
        Assert-EzDarkFactoryEqual -Actual $value.error.code -Expected 'execution_failed'
        Assert-EzDarkFactoryTrue -Condition ($value.error.message -match 'checkout')
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}


Add-EzDarkFactoryTest -Name 'CLI: base build is a real command and fails cleanly before mutation when QEMU is absent' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'base build CLI without runtime'
    try {
        $result = Invoke-EzDarkFactoryCliForTest -ArgumentList @('base', 'build', '-Json') -Root $root
        Assert-EzDarkFactoryEqual -Actual $result.ExitCode -Expected 1
        Assert-EzDarkFactoryEqual -Actual $result.StandardError -Expected ''
        $value = $result.StandardOutput | ConvertFrom-Json -ErrorAction Stop
        Assert-EzDarkFactoryEqual -Actual $value.success -Expected $false
        Assert-EzDarkFactoryEqual -Actual $value.error.code -Expected 'execution_failed'
        Assert-EzDarkFactoryTrue -Condition ($value.error.message -match 'bootstrap') -Message 'Missing QEMU must have actionable bootstrap remediation.'
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root 'runtime/bases'))) -Message 'Prerequisite failure must happen before base staging is created.'
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'CLI: status of an absent instance is a structured ABSENT success' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'status absent CLI'
    try {
        $result = Invoke-EzDarkFactoryCliForTest -ArgumentList @('status', 'missing-agent', '-Json') -Root $root
        $value = Assert-EzDarkFactoryJsonEnvelope -Result $result -Command 'status' -ExitCode 0
        Assert-EzDarkFactoryEqual -Actual $value.data.name -Expected 'missing-agent'
        Assert-EzDarkFactoryEqual -Actual $value.data.state -Expected 'ABSENT'
        Assert-EzDarkFactoryTrue -Condition ($value.data.reason -match 'No durable instance intent')
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'CLI: start and stop missing instances fail as execution errors, not fake success' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'lifecycle missing CLI'
    try {
        $start = Invoke-EzDarkFactoryCliForTest -ArgumentList @('start', 'missing-agent', '-Json') -Root $root
        Assert-EzDarkFactoryEqual -Actual $start.ExitCode -Expected 1
        $startValue = $start.StandardOutput | ConvertFrom-Json -ErrorAction Stop
        Assert-EzDarkFactoryEqual -Actual $startValue.error.code -Expected 'execution_failed'
        Assert-EzDarkFactoryTrue -Condition ($startValue.error.message -match 'instance.json')

        $stop = Invoke-EzDarkFactoryCliForTest -ArgumentList @('stop', 'missing-agent', '-Json') -Root $root
        Assert-EzDarkFactoryEqual -Actual $stop.ExitCode -Expected 1
        $stopValue = $stop.StandardOutput | ConvertFrom-Json -ErrorAction Stop
        Assert-EzDarkFactoryEqual -Actual $stopValue.error.code -Expected 'execution_failed'
        Assert-EzDarkFactoryTrue -Condition ($stopValue.error.message -match 'does not exist')
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'CLI: lifecycle commands require exactly one portable instance name' -ScriptBlock {
    foreach ($arguments in @(
        @('status'),
        @('start', 'one', 'extra'),
        @('stop', '..'),
        @('status', 'bad/name')
    )) {
        $result = Invoke-EzDarkFactoryCliForTest -ArgumentList $arguments
        Assert-EzDarkFactoryEqual -Actual $result.ExitCode -Expected 2
        Assert-EzDarkFactoryTrue -Condition ($result.StandardError -match 'help')
    }
}


Add-EzDarkFactoryTest -Name 'CLI: exec separator keeps remote -Json token out of global switch parsing' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'exec remote Json token'
    try {
        $result = Invoke-EzDarkFactoryCliForTest -ArgumentList @('exec', 'missing-agent', '--', 'printf', '-Json') -Root $root
        Assert-EzDarkFactoryEqual -Actual $result.ExitCode -Expected 1
        Assert-EzDarkFactoryEqual -Actual $result.StandardOutput -Expected ''
        Assert-EzDarkFactoryTrue -Condition ($result.StandardError -match 'SSH access state|does not exist|no SSH access state') -Message 'Remote -Json must not switch the ezdarkfactory wrapper into structured-output mode.'
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'CLI: interactive ssh explicitly rejects structured output' -ScriptBlock {
    $result = Invoke-EzDarkFactoryCliForTest -ArgumentList @('ssh', 'agent-one', '-Json')
    $value = Assert-EzDarkFactoryJsonEnvelope -Result $result -Command 'ssh' -ExitCode 2
    Assert-EzDarkFactoryTrue -Condition ($value.error.message -match 'Interactive ssh cannot be combined with -Json')
}


Add-EzDarkFactoryTest -Name 'CLI: remote non-zero exec result is failure without losing exit or stderr evidence' -ScriptBlock {
    $module = Get-Module EzDarkFactory
    $result = & $module {
        New-EzDarkFactoryRemoteCommandFailureResult -ExitCode 23 -StdOut 'partial output' -StdErr 'guest diagnostic'
    }
    Assert-EzDarkFactoryEqual -Actual $result.success -Expected $false
    Assert-EzDarkFactoryEqual -Actual $result.command -Expected 'exec'
    Assert-EzDarkFactoryEqual -Actual $result.exitCode -Expected 23
    Assert-EzDarkFactoryEqual -Actual $result.data -Expected $null
    Assert-EzDarkFactoryEqual -Actual $result.error.code -Expected 'remote_command_failed'
    Assert-EzDarkFactoryTrue -Condition ($result.error.message -match 'code 23' -and $result.error.message -match 'guest diagnostic' -and $result.error.message -match 'partial output')
}

Add-EzDarkFactoryTest -Name 'CLI: remote exec failure diagnostics are bounded in the standard envelope' -ScriptBlock {
    $module = Get-Module EzDarkFactory
    $result = & $module {
        New-EzDarkFactoryRemoteCommandFailureResult -ExitCode 7 -StdOut ('o' * 900) -StdErr ('e' * 3000)
    }
    Assert-EzDarkFactoryTrue -Condition ($result.error.message.Length -lt 2200) -Message 'Remote failure evidence must be useful but bounded.'
}
