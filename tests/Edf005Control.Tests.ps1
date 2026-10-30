# EDF-005 real-filesystem contracts. No QEMU, guest, WHPX or physical TUI execution is claimed.
function New-Edf005Request {
    param([string]$Root, [string]$Command, [object]$Arguments = $null,
        [string]$Id = '', [string]$InstanceId = '', [string]$Generation = '')
    if (-not $Arguments) { $Arguments = [pscustomobject]@{} }
    if (-not $Id) { $Id = [guid]::NewGuid().ToString('N') }
    $caps = Get-EzDarkFactoryControlCapabilities -Root $Root
    return [pscustomobject][ordered]@{
        schemaVersion = 1; api = [pscustomobject]@{ major = 1; minor = 0 }
        factory_id = $caps.factory_id; operation_id = $Id
        command = $Command; capabilities = @($Command)
        expected_revision = $caps.revision; instance_id = $InstanceId
        instance_generation = $Generation; arguments = $Arguments
    }
}

function New-Edf005SyntheticIntent {
    param([string]$Root, [string]$Name = 'shared-project')
    $dir = Join-Path $Root ('runtime/instances/' + $Name)
    [void][IO.Directory]::CreateDirectory($dir)
    $intent = [pscustomobject][ordered]@{
        schemaVersion = 2; name = $Name; baseId = ('base-' + ('a' * 64))
        profile = 'normal'; cpus = 2; memoryMiB = 4096; sshPort = 22555
        createdAt = [DateTime]::UtcNow.ToString('o'); provisioningProfile = 'fresh-project'
        provisioningVersion = 1; identityGeneration = [guid]::NewGuid().ToString('N')
    }
    Write-EzDarkFactoryJson -Path (Join-Path $dir 'instance.json') -Value $intent -SchemaVersion 2
    return $intent
}

Add-EzDarkFactoryTest -Name 'EDF-005: factory identities are explicit, random, stable and portable' -ScriptBlock {
    $a = New-EzDarkFactoryCheckoutFixture -Prefix 'id 壹 space'
    $b = New-EzDarkFactoryCheckoutFixture -Prefix 'id 乙 space'
    $move = New-EzDarkFactoryTestDirectory -Prefix 'moved 亜'
    try {
        Assert-EzDarkFactoryThrows -ScriptBlock { Get-EzDarkFactoryIdentity -Root $a } -MessagePattern 'uninitialized' | Out-Null
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $a 'runtime')))
        $ia = Initialize-EzDarkFactoryIdentity -Root $a
        $ib = Initialize-EzDarkFactoryIdentity -Root $b
        Assert-EzDarkFactoryTrue -Condition ($ia.factory_id -cne $ib.factory_id)
        Assert-EzDarkFactoryEqual -Actual (Initialize-EzDarkFactoryIdentity -Root $a).factory_id -Expected $ia.factory_id
        Get-ChildItem -LiteralPath $a -Force | Copy-Item -Destination $move -Recurse -Force
        Remove-EzDarkFactoryTestDirectory -Path $a
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryIdentity -Root $move).factory_id -Expected $ia.factory_id
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryControlCapabilities -Root $move).api.major -Expected 1
    }
    finally {
        Remove-EzDarkFactoryTestDirectory -Path $a
        Remove-EzDarkFactoryTestDirectory -Path $b
        Remove-EzDarkFactoryTestDirectory -Path $move
    }
}

Add-EzDarkFactoryTest -Name 'EDF-005: static discovery executes no candidate code and never initializes roots' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture
    try {
        [IO.File]::WriteAllText((Join-Path $root 'candidate-hook.ps1'), 'throw "executed"')
        $candidate = Get-EzDarkFactoryCandidate -Root $root
        Assert-EzDarkFactoryEqual -Actual $candidate.state -Expected 'incompatible'
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root 'runtime')))
        $null = Initialize-EzDarkFactoryIdentity -Root $root
        $before = Get-EzDarkFactoryControlRevision -Root $root
        $candidate = Get-EzDarkFactoryCandidate -Root $root
        Assert-EzDarkFactoryEqual -Actual $candidate.state -Expected 'current'
        $after = Get-EzDarkFactoryControlRevision -Root $root
        Assert-EzDarkFactoryEqual -Actual $after -Expected $before
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root 'runtime/control')))
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'EDF-005: portable registry requires enrollment consent and refuses duplicate path' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture
    $workspace = New-EzDarkFactoryTestDirectory -Prefix 'manager portable state'
    try {
        $null = Initialize-EzDarkFactoryIdentity -Root $root
        $null = Initialize-EzDarkFactoryManagerWorkspace -Workspace $workspace
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Register-EzDarkFactoryManagerRoot -Workspace $workspace -Root $root -Alias 'A'
        } -MessagePattern 'explicit authorization' | Out-Null
        $record = Register-EzDarkFactoryManagerRoot -Workspace $workspace -Root $root -Alias 'Root Α' -AuthorizeLocalExecution
        Assert-EzDarkFactoryTrue -Condition ($record.enrollment_id -match '^enr_')
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Register-EzDarkFactoryManagerRoot -Workspace $workspace -Root (Join-Path $root '.') -Alias 'Duplicate' -AuthorizeLocalExecution
        } -MessagePattern 'already registered' | Out-Null
        $observed = @(Get-EzDarkFactoryManagerObservations -Workspace $workspace)
        Assert-EzDarkFactoryEqual -Actual $observed[0].state -Expected 'current'
        $result = Unregister-EzDarkFactoryManagerRoot -Workspace $workspace -EnrollmentId $record.enrollment_id
        Assert-EzDarkFactoryTrue -Condition $result.removed
        Assert-EzDarkFactoryTrue -Condition (Test-Path -LiteralPath (Join-Path $root 'runtime/factory-identity.json'))
        $left = Get-EzDarkFactoryManagerRegistry -Workspace $workspace
        Assert-EzDarkFactoryEqual -Actual @($left.roots).Count -Expected 0
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root; Remove-EzDarkFactoryTestDirectory -Path $workspace }
}

Add-EzDarkFactoryTest -Name 'EDF-005: duplicate reachable identity conflicts and explicit rekey preserves source' -ScriptBlock {
    $a = New-EzDarkFactoryCheckoutFixture -Prefix 'root A'
    $b = New-EzDarkFactoryCheckoutFixture -Prefix 'root B'
    $workspace = New-EzDarkFactoryTestDirectory -Prefix 'manager collisions'
    try {
        $initial = Initialize-EzDarkFactoryIdentity -Root $a
        $null = Initialize-EzDarkFactoryIdentity -Root $b
        $null = Initialize-EzDarkFactoryManagerWorkspace -Workspace $workspace
        $regA = Register-EzDarkFactoryManagerRoot -Workspace $workspace -Root $a -Alias 'A' -AuthorizeLocalExecution
        $regB = Register-EzDarkFactoryManagerRoot -Workspace $workspace -Root $b -Alias 'B' -AuthorizeLocalExecution
        [IO.File]::Copy((Join-Path $a 'runtime/factory-identity.json'),(Join-Path $b 'runtime/factory-identity.json'),$true)
        $seen = @(Get-EzDarkFactoryManagerObservations -Workspace $workspace)
        Assert-EzDarkFactoryEqual -Actual $seen.Count -Expected 2
        Assert-EzDarkFactoryEqual -Actual $seen[0].state -Expected 'conflict'
        Assert-EzDarkFactoryEqual -Actual $seen[1].state -Expected 'conflict'
        $info = New-Edf005Request -Root $a -Command 'factory.info'
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Invoke-EzDarkFactoryManagerControl -Workspace $workspace -EnrollmentId $regA.enrollment_id -Request $info
        } -MessagePattern 'refuses conflict' | Out-Null
        $request = New-Edf005Request -Root $b -Command 'factory.rekey'
        $rekey = Invoke-EzDarkFactoryControl -Root $b -Request $request
        Assert-EzDarkFactoryEqual -Actual $rekey.state -Expected 'completed'
        Assert-EzDarkFactoryTrue -Condition ($rekey.data.factory_id -cne $initial.factory_id)
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryIdentity -Root $a).factory_id -Expected $initial.factory_id
        Assert-EzDarkFactoryTrue -Condition (Test-Path -LiteralPath (Join-Path $b ('runtime/control/rekey-' + $request.operation_id + '.json')))
        $null = Unregister-EzDarkFactoryManagerRoot -Workspace $workspace -EnrollmentId $regB.enrollment_id
        $null = Register-EzDarkFactoryManagerRoot -Workspace $workspace -Root $b -Alias 'Fork B' -AuthorizeLocalExecution
        foreach ($record in @(Get-EzDarkFactoryManagerObservations -Workspace $workspace)) {
            Assert-EzDarkFactoryEqual -Actual $record.state -Expected 'current'
        }
    }
    finally {
        Remove-EzDarkFactoryTestDirectory -Path $a
        Remove-EzDarkFactoryTestDirectory -Path $b
        Remove-EzDarkFactoryTestDirectory -Path $workspace
    }
}

Add-EzDarkFactoryTest -Name 'EDF-005: wrong major, factory ID and revision refuse before durable mutation' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture
    try {
        $null = Initialize-EzDarkFactoryIdentity -Root $root
        foreach ($kind in @('major','factory','revision')) {
            $request = New-Edf005Request -Root $root -Command 'factory.rekey'
            switch ($kind) {
                'major' { $request.api.major = 8 }
                'factory' { $request.factory_id = 'fct_' + ('0' * 32) }
                'revision' { $request.expected_revision = 'invalid-old-revision' }
            }
            $result = Invoke-EzDarkFactoryControl -Root $root -Request $request
            Assert-EzDarkFactoryEqual -Actual $result.state -Expected 'refused'
            Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root ('runtime/control/operations/' + $request.operation_id + '.json'))))
        }
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root 'runtime/control/rekey')))
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'EDF-005: typed adoption is exactly targeted, idempotent and isolated across roots' -ScriptBlock {
    $a = New-EzDarkFactoryCheckoutFixture -Prefix 'instance A'
    $b = New-EzDarkFactoryCheckoutFixture -Prefix 'instance B'
    try {
        $null = Initialize-EzDarkFactoryIdentity -Root $a
        $null = Initialize-EzDarkFactoryIdentity -Root $b
        $intentA = New-Edf005SyntheticIntent -Root $a
        $null = New-Edf005SyntheticIntent -Root $b
        $bRevision = Get-EzDarkFactoryControlRevision -Root $b
        $request = New-Edf005Request -Root $a -Command 'instance.adopt' -Arguments ([pscustomobject]@{name='shared-project'}) -Generation $intentA.identityGeneration
        $accepted = Invoke-EzDarkFactoryControl -Root $a -Request $request
        Assert-EzDarkFactoryEqual -Actual $accepted.state -Expected 'completed'
        Assert-EzDarkFactoryTrue -Condition ($accepted.data.instance_id -match '^ins_')
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryControlRevision -Root $b) -Expected $bRevision
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $b 'runtime/instances/shared-project/control-instance.json')))
        $again = Invoke-EzDarkFactoryControl -Root $a -Request $request
        Assert-EzDarkFactoryEqual -Actual $again.state -Expected 'completed'
        Assert-EzDarkFactoryEqual -Actual $again.data.instance_id -Expected $accepted.data.instance_id
        $receipt = Get-EzDarkFactoryControlOperation -Root $a -OperationId $request.operation_id
        Assert-EzDarkFactoryEqual -Actual $receipt.state -Expected 'completed'
        $stale = New-Edf005Request -Root $a -Command 'instance.stop' -Arguments ([pscustomobject]@{name='shared-project'}) -InstanceId $accepted.data.instance_id -Generation ('0' * 32)
        $refusal = Invoke-EzDarkFactoryControl -Root $a -Request $stale
        Assert-EzDarkFactoryEqual -Actual $refusal.state -Expected 'refused'
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $a ('runtime/control/operations/' + $stale.operation_id + '.json'))))
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryInstanceRef -Root $a -Name 'shared-project').instance_id -Expected $accepted.data.instance_id
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $a; Remove-EzDarkFactoryTestDirectory -Path $b }
}

Add-EzDarkFactoryTest -Name 'EDF-005: malformed identity fails closed without generating a replacement' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture
    try {
        $null = Initialize-EzDarkFactoryIdentity -Root $root
        $file = Join-Path $root 'runtime/factory-identity.json'
        [IO.File]::WriteAllText($file, '{"schemaVersion":1,"factory_id":"bad","api_major":1,"api_minor":0,"created_at":"x"}')
        Assert-EzDarkFactoryThrows -ScriptBlock { Initialize-EzDarkFactoryIdentity -Root $root } -MessagePattern 'identity' | Out-Null
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryCandidate -Root $root).state -Expected 'incompatible'
        Assert-EzDarkFactoryTrue -Condition ([IO.File]::ReadAllText($file).Contains('"bad"'))
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'EDF-005: candidate and typed reads do not create operation records' -ScriptBlock {
    $a = New-EzDarkFactoryCheckoutFixture
    try {
        $null = Initialize-EzDarkFactoryIdentity -Root $a
        foreach ($cmd in @('factory.info','instance.list')) {
            $request = New-Edf005Request -Root $a -Command $cmd
            $result = Invoke-EzDarkFactoryControl -Root $a -Request $request
            Assert-EzDarkFactoryEqual -Actual $result.state -Expected 'completed'
        }
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $a 'runtime/control/operations')))
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $a }
}
