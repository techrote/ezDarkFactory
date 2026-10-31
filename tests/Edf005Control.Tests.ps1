# EDF-005 real-filesystem contracts. No QEMU, guest, WHPX or physical TUI execution is claimed.
Import-Module (Join-Path $script:EzDarkFactoryRepositoryRoot 'src/EzDarkFactory/Edf005.psm1') -Force

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
    [IO.File]::WriteAllText((Join-Path $dir 'instance.json'), (ConvertTo-Json -InputObject $intent -Depth 8), (New-Object Text.UTF8Encoding($false)))
    return $intent
}

Add-EzDarkFactoryTest -Name 'EDF-005: factory identities are explicit, random, stable and portable' -ScriptBlock {
    $a = New-EzDarkFactoryCheckoutFixture -Prefix 'id Chinese 1 space'
    $b = New-EzDarkFactoryCheckoutFixture -Prefix 'id Chinese 2 space'
    $move = New-EzDarkFactoryTestDirectory -Prefix 'moved Japanese space'
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
        $record = Register-EzDarkFactoryManagerRoot -Workspace $workspace -Root $root -Alias 'Root Unicode' -AuthorizeLocalExecution
        Assert-EzDarkFactoryTrue -Condition ($record.enrollment_id -match '^enr_')
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Register-EzDarkFactoryManagerRoot -Workspace $workspace -Root (Join-Path $root '.') -Alias 'Duplicate' -AuthorizeLocalExecution
        } -MessagePattern 'already registered' | Out-Null
        $observed = @(Get-EzDarkFactoryManagerObservations -Workspace $workspace)
        Assert-EzDarkFactoryEqual -Actual $observed[0].state -Expected 'current'
        Assert-EzDarkFactoryEqual -Actual $observed[0].inventory_state -Expected 'unknown'
        Assert-EzDarkFactoryEqual -Actual $observed[0].last_known.freshness -Expected 'stale'
        $result = Unregister-EzDarkFactoryManagerRoot -Workspace $workspace -EnrollmentId $record.enrollment_id
        Assert-EzDarkFactoryTrue -Condition $result.removed
        Assert-EzDarkFactoryTrue -Condition (Test-Path -LiteralPath (Join-Path $root 'runtime/factory-identity.json'))
        $left = Get-EzDarkFactoryManagerRegistry -Workspace $workspace
        $remainingCount = @($left.roots).Count
        Assert-EzDarkFactoryEqual -Actual $remainingCount -Expected 0
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
        $failureMessage = if ($null -eq $rekey.refusal) { 'Rekey did not complete.' } else { [string]$rekey.refusal.message }
        Assert-EzDarkFactoryEqual -Actual $rekey.state -Expected 'completed' -Message $failureMessage
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
        $badIdentity = [pscustomobject]@{ schemaVersion = 1; factory_id = 'bad'; api_major = 1; api_minor = 0; created_at = 'x' }
        [IO.File]::WriteAllText($file, (ConvertTo-Json -InputObject $badIdentity -Compress))
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


Add-EzDarkFactoryTest -Name 'EDF-005: finalized previous operation remains historical when a copied factory is explicitly rekeyed' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'historical ops'
    try {
        $old = Initialize-EzDarkFactoryIdentity -Root $root
        $intent = New-Edf005SyntheticIntent -Root $root -Name 'copied-project'
        $adopt = New-Edf005Request -Root $root -Command 'instance.adopt' -Arguments ([pscustomobject]@{name='copied-project'}) -Generation $intent.identityGeneration
        $res = Invoke-EzDarkFactoryControl -Root $root -Request $adopt
        Assert-EzDarkFactoryEqual -Actual $res.state -Expected 'completed'
        $fork = New-Edf005Request -Root $root -Command 'factory.rekey'
        $result = Invoke-EzDarkFactoryControl -Root $root -Request $fork
        Assert-EzDarkFactoryEqual -Actual $result.state -Expected 'completed'
        Assert-EzDarkFactoryTrue -Condition ($result.data.factory_id -cne $old.factory_id)
        $previous = Get-EzDarkFactoryControlOperation -Root $root -OperationId $adopt.operation_id
        Assert-EzDarkFactoryEqual -Actual $previous.factory_id -Expected $old.factory_id
        Assert-EzDarkFactoryEqual -Actual $previous.state -Expected 'completed'
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'EDF-005: accepted ambiguous operation blocks rekey and cannot be blindly replayed' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture
    try {
        $identity = Initialize-EzDarkFactoryIdentity -Root $root
        $intent = New-Edf005SyntheticIntent -Root $root -Name 'ambiguous'
        $adopt = New-Edf005Request -Root $root -Command 'instance.adopt' -Arguments ([pscustomobject]@{name='ambiguous'}) -Generation $intent.identityGeneration
        $ok = Invoke-EzDarkFactoryControl -Root $root -Request $adopt
        Assert-EzDarkFactoryEqual -Actual $ok.state -Expected 'completed'
        $operationPath = Join-Path $root ('runtime/control/operations/' + $adopt.operation_id + '.json')
        $record = Get-EzDarkFactoryControlOperation -Root $root -OperationId $adopt.operation_id
        $record.state = 'accepted'; $record.result = $null; $record.finished_at = $null
        [IO.File]::WriteAllText($operationPath, (ConvertTo-Json -InputObject $record -Depth 20), (New-Object Text.UTF8Encoding($false)))
        $again = Invoke-EzDarkFactoryControl -Root $root -Request $adopt
        Assert-EzDarkFactoryEqual -Actual $again.state -Expected 'accepted'
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryControlOperation -Root $root -OperationId $adopt.operation_id).state -Expected 'accepted'
        $rekey = New-Edf005Request -Root $root -Command 'factory.rekey'
        $refusal = Invoke-EzDarkFactoryControl -Root $root -Request $rekey
        Assert-EzDarkFactoryEqual -Actual $refusal.state -Expected 'refused'
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryIdentity -Root $root).factory_id -Expected $identity.factory_id
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root ('runtime/control/operations/' + $rekey.operation_id + '.json'))))
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'EDF-005: out-of-band instance generation change invalidates stale manager confirmation' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture
    try {
        $null = Initialize-EzDarkFactoryIdentity -Root $root
        $intent = New-Edf005SyntheticIntent -Root $root -Name 'outofband'
        $adopt = New-Edf005Request -Root $root -Command 'instance.adopt' -Arguments ([pscustomobject]@{name='outofband'}) -Generation $intent.identityGeneration
        $adopted = Invoke-EzDarkFactoryControl -Root $root -Request $adopt
        Assert-EzDarkFactoryEqual -Actual $adopted.state -Expected 'completed'
        $reference = $adopted.data
        $stale = New-Edf005Request -Root $root -Command 'instance.stop' -Arguments ([pscustomobject]@{name='outofband'}) -InstanceId $reference.instance_id -Generation $reference.instance_generation
        $intent.identityGeneration = [guid]::NewGuid().ToString('N')
        [IO.File]::WriteAllText((Join-Path $root 'runtime/instances/outofband/instance.json'), (ConvertTo-Json -InputObject $intent -Depth 8), (New-Object Text.UTF8Encoding($false)))
        $attempt = Invoke-EzDarkFactoryControl -Root $root -Request $stale
        Assert-EzDarkFactoryEqual -Actual $attempt.state -Expected 'refused'
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root ('runtime/control/operations/' + $stale.operation_id + '.json'))))
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryInstanceRef -Root $root -Name 'outofband').instance_generation -Expected $intent.identityGeneration
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'EDF-005: bounded guest log sanitizes control sequences without executing guest text' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture
    try {
        $null = Initialize-EzDarkFactoryIdentity -Root $root
        $intent = New-Edf005SyntheticIntent -Root $root -Name 'logreader'
        $adopt = New-Edf005Request -Root $root -Command 'instance.adopt' -Arguments ([pscustomobject]@{name='logreader'}) -Generation $intent.identityGeneration
        $ref = (Invoke-EzDarkFactoryControl -Root $root -Request $adopt).data
        $logs = Join-Path $root 'runtime/instances/logreader/logs'
        [void][IO.Directory]::CreateDirectory($logs)
        [IO.File]::WriteAllText((Join-Path $logs 'serial.log'), (('q' * 15000) + [char]27 + '[31m'), (New-Object Text.UTF8Encoding($false)))
        $args = [pscustomobject]@{ name = 'logreader'; kind = 'serial'; maximum_characters = 256 }
        $request = New-Edf005Request -Root $root -Command 'instance.logs' -Arguments $args -InstanceId $ref.instance_id -Generation $ref.instance_generation
        $result = Invoke-EzDarkFactoryControl -Root $root -Request $request
        Assert-EzDarkFactoryEqual -Actual $result.state -Expected 'completed'
        Assert-EzDarkFactoryTrue -Condition ($result.data.text.Length -le 256)
        Assert-EzDarkFactoryTrue -Condition (-not $result.data.text.Contains([string][char]27))
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root ('runtime/control/operations/' + $request.operation_id + '.json'))))
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'EDF-005: Unicode root path, missing root and peer isolation are static-only observations' -ScriptBlock {
    $a = New-EzDarkFactoryCheckoutFixture -Prefix ('unicode-' + [string][char]0x4e9c)
    $b = New-EzDarkFactoryCheckoutFixture -Prefix 'unaffected factory'
    $workspace = New-EzDarkFactoryTestDirectory
    try {
        $ia = Initialize-EzDarkFactoryIdentity -Root $a
        $ib = Initialize-EzDarkFactoryIdentity -Root $b
        $null = Initialize-EzDarkFactoryManagerWorkspace -Workspace $workspace
        $null = Register-EzDarkFactoryManagerRoot -Workspace $workspace -Root $a -Alias 'missing' -AuthorizeLocalExecution
        $null = Register-EzDarkFactoryManagerRoot -Workspace $workspace -Root $b -Alias 'healthy' -AuthorizeLocalExecution
        Remove-EzDarkFactoryTestDirectory -Path $a
        $seen = @(Get-EzDarkFactoryManagerObservations -Workspace $workspace)
        $missing = @($seen | Where-Object { $_.factory_id -ceq $ia.factory_id })[0]
        $healthy = @($seen | Where-Object { $_.factory_id -ceq $ib.factory_id })[0]
        Assert-EzDarkFactoryEqual -Actual $missing.state -Expected 'unreachable'
        Assert-EzDarkFactoryEqual -Actual $healthy.state -Expected 'current'
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryIdentity -Root $b).factory_id -Expected $ib.factory_id
    }
    finally {
        Remove-EzDarkFactoryTestDirectory -Path $a
        Remove-EzDarkFactoryTestDirectory -Path $b
        Remove-EzDarkFactoryTestDirectory -Path $workspace
    }
}

Add-EzDarkFactoryTest -Name 'EDF-005: second PowerShell process reads relocated factory without a manager or TUI' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'process boundary'
    try {
        $identity = Initialize-EzDarkFactoryIdentity -Root $root
        $module = Join-Path $root 'src/EzDarkFactory/Edf005.psm1'
        $safeModule = $module.Replace("'", "''")
        $safeRoot = $root.Replace("'", "''")
        $command = "Import-Module '$safeModule' -Force -ErrorAction Stop; " +
            "if ((Get-EzDarkFactoryIdentity -Root '$safeRoot').factory_id -cne '$($identity.factory_id)') { throw 'wrong factory' }; Write-Output 'EDF005_CHILD_PASS'"
        $child = Invoke-EzDarkFactoryTestPowerShell -CommandText $command -WorkingDirectory $root
        Assert-EzDarkFactoryEqual -Actual $child.ExitCode -Expected 0 -Message $child.StandardError
        Assert-EzDarkFactoryTrue -Condition $child.StandardOutput.Contains('EDF005_CHILD_PASS')
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}


Add-EzDarkFactoryTest -Name 'EDF-005: standalone JSON control launcher round-trips version and factory ID across a real child process' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'standalone JSON child'
    try {
        $identity = Initialize-EzDarkFactoryIdentity -Root $root
        Copy-Item -LiteralPath (Join-Path $script:EzDarkFactoryRepositoryRoot 'ezdarkfactory-control.ps1') -Destination $root -Force
        $request = New-Edf005Request -Root $root -Command 'factory.info'
        $json = ConvertTo-Json -InputObject $request -Depth 12 -Compress
        $requestFile = Join-Path $root 'edf005-request-fixture.json'
        [IO.File]::WriteAllText($requestFile, $json, (New-Object Text.UTF8Encoding($false)))
        $launcher = Join-Path $root 'ezdarkfactory-control.ps1'
        $code = '& "' + $launcher + '" -RequestFile "' + $requestFile + '"'
        $child = Invoke-EzDarkFactoryTestPowerShell -CommandText $code -WorkingDirectory $root
        $diagnostic = 'stdout=' + $child.StandardOutput + '; stderr=' + $child.StandardError
        Assert-EzDarkFactoryEqual -Actual $child.ExitCode -Expected 0 -Message $diagnostic
        $response = $child.StandardOutput.Trim() | ConvertFrom-Json
        Assert-EzDarkFactoryEqual -Actual $response.state -Expected 'completed'
        Assert-EzDarkFactoryEqual -Actual $response.operation_id -Expected $request.operation_id
        Assert-EzDarkFactoryEqual -Actual $response.factory_id -Expected $identity.factory_id
        Assert-EzDarkFactoryEqual -Actual $response.api.major -Expected 1
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'EDF-005: invalid command fields, unsupported minor version and wrong operation replay are refused without effects' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture
    try {
        $identity = Initialize-EzDarkFactoryIdentity -Root $root
        $checks = @('extra-argument','minor-version','missing-capability','wrong-scope')
        foreach ($kind in $checks) {
            $request = New-Edf005Request -Root $root -Command 'factory.rekey'
            switch ($kind) {
                'extra-argument' { $request.arguments = [pscustomobject]@{ script = 'do not run' } }
                'minor-version' { $request.api.minor = 55 }
                'missing-capability' { $request.capabilities = @('unknown.command') }
                'wrong-scope' { $request.instance_id = 'ins_' + ('0' * 32) }
            }
            $response = Invoke-EzDarkFactoryControl -Root $root -Request $request
            Assert-EzDarkFactoryEqual -Actual $response.state -Expected 'refused'
            Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root ('runtime/control/operations/' + $request.operation_id + '.json'))))
            Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryIdentity -Root $root).factory_id -Expected $identity.factory_id
        }
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}


# Process-boundary concurrency fixtures use the exact local module and independent
# OS processes; they are not simulated QEMU or a mocked operation-success oracle.
function Add-Edf005WorkerEntrypoints {
    param([string]$Root)
    foreach ($file in @('ezdarkfactory-worker.ps1','ezdarkfactory-attach.ps1')) {
        Copy-Item -LiteralPath (Join-Path $script:EzDarkFactoryRepositoryRoot $file) -Destination $Root -Force
    }
}

function Wait-Edf005RootReceipt {
    param([string]$Root, [string]$OperationId, [int]$TimeoutSeconds = 40)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $result = Get-EzDarkFactoryControlOperationResult -Root $Root -OperationId $OperationId
        if ($null -ne $result -and $result.state -in @('completed','refused','accepted')) { return $result }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'A root-owned operation did not publish an accepted or terminal receipt within the test deadline.'
}

function Enter-Edf005TestBudgetBlock {
    param([string]$Workspace, [int]$Limit = 2)
    $leases = New-Object 'System.Collections.Generic.List[object]'
    try {
        for ($i = 0; $i -lt $Limit; $i++) {
            $file = Join-Path $Workspace ('operation-slot-' + $i + '.lock')
            $leases.Add([IO.File]::Open($file, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None))
        }
        return @($leases.ToArray())
    }
    catch {
        foreach ($lease in $leases) { $lease.Dispose() }
        throw
    }
}

function Start-Edf005ControlChild {
    param([string]$Root, [object]$Request, [string]$Workspace = '', [string]$EnrollmentId = '')
    $module = Join-Path $Root 'src/EzDarkFactory/Edf005.psm1'
    $payload = ConvertTo-Json -InputObject $Request -Depth 16 -Compress
    $base64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload))
    $cmd = '$ProgressPreference="SilentlyContinue"; Import-Module "' + $module +
        '" -Force -ErrorAction Stop; $req=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String("' +
        $base64 + '")) | ConvertFrom-Json; '
    if ($Workspace) {
        $cmd += '$response=Invoke-EzDarkFactoryManagerControl -Workspace "' + $Workspace +
            '" -EnrollmentId "' + $EnrollmentId + '" -Request $req; '
    }
    else { $cmd += '$response=Invoke-EzDarkFactoryControl -Root "' + $Root + '" -Request $req; ' }
    $cmd += '$response | ConvertTo-Json -Depth 16 -Compress'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    $exe = if ($PSVersionTable.PSVersion.Major -eq 5) { Join-Path $PSHOME 'powershell.exe' } else { Join-Path $PSHOME 'pwsh.exe' }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $exe
    $start.Arguments = '-NoLogo -NoProfile -NonInteractive -EncodedCommand ' + $encoded
    $start.WorkingDirectory = $Root
    $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    if (-not $process.Start()) { throw 'Could not launch concurrent PowerShell child.' }
    return $process
}

function Receive-Edf005ControlChild {
    param([Diagnostics.Process]$Process)
    $stdout = $Process.StandardOutput.ReadToEndAsync()
    $stderr = $Process.StandardError.ReadToEndAsync()
    if (-not $Process.WaitForExit(20000)) {
        $Process.Kill()
        throw 'Concurrent control child exceeded its bounded 20s deadline.'
    }
    if (-not $stdout.Wait(3000) -or -not $stderr.Wait(3000)) { throw 'Concurrent control child output did not drain.' }
    if ($Process.ExitCode -ne 0) { throw ('Concurrent child exited '+ $Process.ExitCode + ': ' + $stderr.Result) }
    return ($stdout.Result.Trim() | ConvertFrom-Json)
}

Add-EzDarkFactoryTest -Name 'EDF-005: two independent registered roots execute concurrently under bounded host budget' -ScriptBlock {
    $a = New-EzDarkFactoryCheckoutFixture -Prefix 'concurrent root A'
    $b = New-EzDarkFactoryCheckoutFixture -Prefix 'concurrent root B'
    $workspace = New-EzDarkFactoryTestDirectory -Prefix 'concurrent manager'
    $children = @()
    $leases = @()
    try {
        Add-Edf005WorkerEntrypoints -Root $a
        Add-Edf005WorkerEntrypoints -Root $b
        $originalA = Initialize-EzDarkFactoryIdentity -Root $a
        $originalB = Initialize-EzDarkFactoryIdentity -Root $b
        $null = Initialize-EzDarkFactoryManagerWorkspace -Workspace $workspace
        $ra = Register-EzDarkFactoryManagerRoot -Workspace $workspace -Root $a -Alias 'A' -AuthorizeLocalExecution
        $rb = Register-EzDarkFactoryManagerRoot -Workspace $workspace -Root $b -Alias 'B' -AuthorizeLocalExecution
        # Prevent either worker from entering the mutation while the
        # manager processes are alive. This proves true OS-child survival
        # rather than merely fast inline execution.
        $leases = @(Enter-Edf005TestBudgetBlock -Workspace $workspace)
        $op = [guid]::NewGuid().ToString('N')
        $requestA = New-Edf005Request -Root $a -Command 'factory.rekey' -Id $op
        $requestB = New-Edf005Request -Root $b -Command 'factory.rekey' -Id $op
        $children = @(
            (Start-Edf005ControlChild -Root $a -Request $requestA -Workspace $workspace -EnrollmentId $ra.enrollment_id),
            (Start-Edf005ControlChild -Root $b -Request $requestB -Workspace $workspace -EnrollmentId $rb.enrollment_id)
        )
        $first = Receive-Edf005ControlChild -Process $children[0]
        $second = Receive-Edf005ControlChild -Process $children[1]
        Assert-EzDarkFactoryEqual -Actual $first.state -Expected 'dispatched'
        Assert-EzDarkFactoryEqual -Actual $second.state -Expected 'dispatched'
        Assert-EzDarkFactoryTrue -Condition (-not $first.accepted)
        Assert-EzDarkFactoryTrue -Condition (-not $second.accepted)
        # Manager processes are gone. Both separate workers must remain
        # blocked on the host-budget leases before acceptance.
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryControlOperationResult -Root $a -OperationId $op).state -Expected 'submitted'
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryControlOperationResult -Root $b -OperationId $op).state -Expected 'submitted'
        foreach ($lease in $leases) { $lease.Dispose() }
        $leases = @()
        # Only now may the root-local children accept and complete. No
        # manager process is present to drive, poll or restart them.
        $receiptA = Wait-Edf005RootReceipt -Root $a -OperationId $op
        $receiptB = Wait-Edf005RootReceipt -Root $b -OperationId $op
        Assert-EzDarkFactoryEqual -Actual $receiptA.state -Expected 'completed'
        Assert-EzDarkFactoryEqual -Actual $receiptB.state -Expected 'completed'
        Assert-EzDarkFactoryTrue -Condition ((Get-EzDarkFactoryIdentity -Root $a).factory_id -cne (Get-EzDarkFactoryIdentity -Root $b).factory_id)
        Assert-EzDarkFactoryTrue -Condition ((Get-EzDarkFactoryIdentity -Root $a).factory_id -cne $originalA.factory_id)
        Assert-EzDarkFactoryTrue -Condition ((Get-EzDarkFactoryIdentity -Root $b).factory_id -cne $originalB.factory_id)
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryControlOperation -Root $a -OperationId $op).factory_id -Expected $originalA.factory_id
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryControlOperation -Root $b -OperationId $op).factory_id -Expected $originalB.factory_id
    }
    finally {
        foreach ($lease in $leases) { if ($null -ne $lease) { $lease.Dispose() } }
        foreach ($process in $children) { if ($null -ne $process) { if (-not $process.HasExited) { $process.Kill() }; $process.Dispose() } }
        Remove-EzDarkFactoryTestDirectory -Path $a
        Remove-EzDarkFactoryTestDirectory -Path $b
        Remove-EzDarkFactoryTestDirectory -Path $workspace
    }
}

Add-EzDarkFactoryTest -Name 'EDF-005: concurrent duplicate operation in same root has one minted identity and one durable result' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'duplicate operation'
    $children = @()
    try {
        $null = Initialize-EzDarkFactoryIdentity -Root $root
        $intent = New-Edf005SyntheticIntent -Root $root -Name 'duplicate'
        $req = New-Edf005Request -Root $root -Command 'instance.adopt' -Arguments ([pscustomobject]@{name='duplicate'}) -Generation $intent.identityGeneration
        $children = @(
            (Start-Edf005ControlChild -Root $root -Request $req),
            (Start-Edf005ControlChild -Root $root -Request $req)
        )
        $one = Receive-Edf005ControlChild -Process $children[0]
        $two = Receive-Edf005ControlChild -Process $children[1]
        Assert-EzDarkFactoryEqual -Actual $one.state -Expected 'completed'
        Assert-EzDarkFactoryEqual -Actual $two.state -Expected 'completed'
        Assert-EzDarkFactoryEqual -Actual $one.data.instance_id -Expected $two.data.instance_id
        $ref = Get-EzDarkFactoryInstanceRef -Root $root -Name 'duplicate'
        Assert-EzDarkFactoryEqual -Actual $ref.instance_id -Expected $one.data.instance_id
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryControlOperation -Root $root -OperationId $req.operation_id).state -Expected 'completed'
        $journal = @(Get-ChildItem -LiteralPath (Join-Path $root 'runtime/control/operations') -Filter '*.json')
        Assert-EzDarkFactoryEqual -Actual $journal.Count -Expected 1
    }
    finally {
        foreach ($process in $children) { if ($null -ne $process) { if (-not $process.HasExited) { $process.Kill() }; $process.Dispose() } }
        Remove-EzDarkFactoryTestDirectory -Path $root
    }
}


Add-EzDarkFactoryTest -Name 'EDF-005: diagnosed instance observations use public typed read-only lifecycle state' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'diagnostic observation'
    try {
        $null = Initialize-EzDarkFactoryIdentity -Root $root
        $intent = New-Edf005SyntheticIntent -Root $root -Name 'diagnosed'
        $adopt = New-Edf005Request -Root $root -Command 'instance.adopt' -Arguments ([pscustomobject]@{name='diagnosed'}) -Generation $intent.identityGeneration
        $target = (Invoke-EzDarkFactoryControl -Root $root -Request $adopt).data
        $baseline = Get-EzDarkFactoryControlRevision -Root $root
        $req = New-Edf005Request -Root $root -Command 'instance.diagnose' -Arguments ([pscustomobject]@{name='diagnosed'}) -InstanceId $target.instance_id -Generation $target.instance_generation
        $res = Invoke-EzDarkFactoryControl -Root $root -Request $req
        Assert-EzDarkFactoryEqual -Actual $res.state -Expected 'completed'
        Assert-EzDarkFactoryEqual -Actual $res.data.target.instance_id -Expected $target.instance_id
        Assert-EzDarkFactoryTrue -Condition (-not $res.data.repair_attempted)
        Assert-EzDarkFactoryTrue -Condition ($res.data.reason.Length -le 2048)
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryControlRevision -Root $root) -Expected $baseline
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root ('runtime/control/operations/' + $req.operation_id + '.json'))))
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}


Add-EzDarkFactoryTest -Name 'EDF-005: shell descriptor returns exact argv and attach helper fails closed on stale generation' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'shell descriptor'
    try {
        Add-Edf005WorkerEntrypoints -Root $root
        $id = Initialize-EzDarkFactoryIdentity -Root $root
        $intent = New-Edf005SyntheticIntent -Root $root -Name 'shellref'
        $adopt = New-Edf005Request -Root $root -Command 'instance.adopt' -Arguments ([pscustomobject]@{name='shellref'}) -Generation $intent.identityGeneration
        $ref = (Invoke-EzDarkFactoryControl -Root $root -Request $adopt).data
        $req = New-Edf005Request -Root $root -Command 'instance.shell_descriptor' -Arguments ([pscustomobject]@{name='shellref'}) -InstanceId $ref.instance_id -Generation $ref.instance_generation
        $response = Invoke-EzDarkFactoryControl -Root $root -Request $req
        Assert-EzDarkFactoryEqual -Actual $response.state -Expected 'completed'
        $descriptor = $response.data
        Assert-EzDarkFactoryEqual -Actual $descriptor.kind -Expected 'managed-ssh-attach'
        Assert-EzDarkFactoryEqual -Actual $descriptor.factory_id -Expected $id.factory_id
        Assert-EzDarkFactoryEqual -Actual $descriptor.instance_id -Expected $ref.instance_id
        Assert-EzDarkFactoryTrue -Condition (-not $descriptor.ready)
        Assert-EzDarkFactoryEqual -Actual $descriptor.command.argv[0] -Expected '-NoLogo'
        Assert-EzDarkFactoryEqual -Actual $descriptor.command.argv[3] -Expected (Join-Path $root 'ezdarkfactory-attach.ps1')
        $argv = @($descriptor.command.argv) + @('-ProbeOnly')
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $descriptor.command.executable
        # Probe validates the actual root-local launcher without QEMU/SSH.
        $start.Arguments = '-NoLogo -NoProfile -NonInteractive -File "' + $argv[3] + '" -FactoryId "' +
            $id.factory_id + '" -InstanceId "' + $ref.instance_id + '" -InstanceGeneration "' +
            $ref.instance_generation + '" -ExpectedRevision "' + $argv[11] + '" -ProbeOnly'
        $start.WorkingDirectory = $root; $start.UseShellExecute = $false; $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
        $proc = New-Object Diagnostics.Process
        $proc.StartInfo = $start
        try {
            Assert-EzDarkFactoryTrue -Condition $proc.Start()
            $stdout = $proc.StandardOutput.ReadToEndAsync()
            $stderr = $proc.StandardError.ReadToEndAsync()
            Assert-EzDarkFactoryTrue -Condition ($proc.WaitForExit(12000)) -Message 'Managed attach probe timed out.'
            Assert-EzDarkFactoryEqual -Actual $proc.ExitCode -Expected 0 -Message $stderr.Result
            $probe = $stdout.Result.Trim() | ConvertFrom-Json
            Assert-EzDarkFactoryEqual -Actual $probe.instance_id -Expected $ref.instance_id
            Assert-EzDarkFactoryTrue -Condition (-not $probe.launched)
        }
        finally { if (-not $proc.HasExited) { $proc.Kill() }; $proc.Dispose() }
        $stale = New-Edf005Request -Root $root -Command 'instance.shell_descriptor' -Arguments ([pscustomobject]@{name='shellref'}) -InstanceId $ref.instance_id -Generation ('0' * 32)
        Assert-EzDarkFactoryEqual -Actual (Invoke-EzDarkFactoryControl -Root $root -Request $stale).state -Expected 'refused'
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'EDF-005: root-owned dispatched adoption survives manager process exit and never auto-replays' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'root owned detached'
    $workspace = New-EzDarkFactoryTestDirectory -Prefix 'root owned manager'
    $leases = @()
    try {
        Add-Edf005WorkerEntrypoints -Root $root
        $null = Initialize-EzDarkFactoryIdentity -Root $root
        $intent = New-Edf005SyntheticIntent -Root $root -Name 'resident'
        $null = Initialize-EzDarkFactoryManagerWorkspace -Workspace $workspace
        $entry = Register-EzDarkFactoryManagerRoot -Workspace $workspace -Root $root -Alias 'resident' -AuthorizeLocalExecution
        $leases = @(Enter-Edf005TestBudgetBlock -Workspace $workspace)
        $request = New-Edf005Request -Root $root -Command 'instance.adopt' -Arguments ([pscustomobject]@{name='resident'}) -Generation $intent.identityGeneration
        $parent = Start-Edf005ControlChild -Root $root -Request $request -Workspace $workspace -EnrollmentId $entry.enrollment_id
        try { $submitted = Receive-Edf005ControlChild -Process $parent }
        finally { if (-not $parent.HasExited) { $parent.Kill() }; $parent.Dispose() }
        Assert-EzDarkFactoryEqual -Actual $submitted.state -Expected 'dispatched'
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryControlOperationResult -Root $root -OperationId $request.operation_id).state -Expected 'submitted'
        foreach ($lease in $leases) { $lease.Dispose() }
        $leases = @()
        $result = Wait-Edf005RootReceipt -Root $root -OperationId $request.operation_id
        Assert-EzDarkFactoryEqual -Actual $result.state -Expected 'completed'
        $identity = Get-EzDarkFactoryInstanceRef -Root $root -Name 'resident'
        Assert-EzDarkFactoryTrue -Condition ($identity.instance_id -cmatch '^ins_[a-f0-9]{32}$')
        $again = Start-EzDarkFactoryDetachedControlOperation -Root $root -Request $request -ManagerWorkspace $workspace
        Assert-EzDarkFactoryEqual -Actual $again.state -Expected 'existing'
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryInstanceRef -Root $root -Name 'resident').instance_id -Expected $identity.instance_id
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root ('runtime/control/submissions/' + $request.operation_id + '.json'))))
    }
    finally {
        foreach ($lease in $leases) { if ($null -ne $lease) { $lease.Dispose() } }
        Remove-EzDarkFactoryTestDirectory -Path $root
        Remove-EzDarkFactoryTestDirectory -Path $workspace
    }
}

Add-EzDarkFactoryTest -Name 'EDF-005: detached worker reconciles stale preconditions without an operation journal or replay' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'detached stale'
    try {
        Add-Edf005WorkerEntrypoints -Root $root
        $null = Initialize-EzDarkFactoryIdentity -Root $root
        $intent = New-Edf005SyntheticIntent -Root $root -Name 'staleworker'
        $req = New-Edf005Request -Root $root -Command 'instance.adopt' -Arguments ([pscustomobject]@{name='staleworker'}) -Generation $intent.identityGeneration
        $subdir = Join-Path $root 'runtime/control/submissions'
        [void][IO.Directory]::CreateDirectory($subdir)
        $requestPath = Join-Path $subdir ($req.operation_id + '.json')
        [IO.File]::WriteAllText($requestPath, (ConvertTo-Json -InputObject $req -Depth 16 -Compress), (New-Object Text.UTF8Encoding($false)))
        $intent.identityGeneration = [guid]::NewGuid().ToString('N')
        [IO.File]::WriteAllText((Join-Path $root 'runtime/instances/staleworker/instance.json'), (ConvertTo-Json -InputObject $intent -Depth 16 -Compress), (New-Object Text.UTF8Encoding($false)))
        Invoke-EzDarkFactoryDetachedControlWorker -Root $root -OperationId $req.operation_id
        $result = Get-EzDarkFactoryControlOperationResult -Root $root -OperationId $req.operation_id
        Assert-EzDarkFactoryEqual -Actual $result.state -Expected 'refused'
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root ('runtime/control/operations/' + $req.operation_id + '.json'))))
        Assert-EzDarkFactoryTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $root 'runtime/instances/staleworker/control-instance.json')))
        $duplicate = Start-EzDarkFactoryDetachedControlOperation -Root $root -Request $req
        Assert-EzDarkFactoryEqual -Actual $duplicate.state -Expected 'existing'
        Assert-EzDarkFactoryEqual -Actual $duplicate.reconciliation.state -Expected 'refused'
        Assert-EzDarkFactoryEqual -Actual (Get-EzDarkFactoryControlOperationResult -Root $root -OperationId $req.operation_id).state -Expected 'refused'
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}
