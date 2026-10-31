# EDF-005: per-factory typed control plane. This module never creates state on import or observation.
function Get-EzDarkFactoryIdentityPath {
    param([string]$Root = $script:EzDarkFactoryDefaultRoot)
    return (Join-Path (Get-EzDarkFactoryPaths -Root $Root).Runtime 'factory-identity.json')
}

function Assert-EzDarkFactoryIdentityDocument {
    param([object]$Document)
    if ($null -eq $Document) { throw 'Factory identity document is absent.' }
    $fields = @($Document.PSObject.Properties | ForEach-Object { $_.Name })
    $required = @('schemaVersion', 'factory_id', 'api_major', 'api_minor', 'created_at')
    if ($fields.Count -ne $required.Count -or @($required | Where-Object { $fields -cnotcontains $_ }).Count -ne 0) {
        throw 'Factory identity contains missing or unsupported fields; migration is explicit.'
    }
    if (@([int], [long]) -notcontains $Document.schemaVersion.GetType() -or $Document.schemaVersion -ne 1 -or
        $Document.factory_id -isnot [string] -or $Document.factory_id -cnotmatch '^fct_[a-f0-9]{32}$' -or
        @([int], [long]) -notcontains $Document.api_major.GetType() -or $Document.api_major -ne 1 -or
        @([int], [long]) -notcontains $Document.api_minor.GetType() -or $Document.api_minor -lt 0 -or $Document.api_minor -gt 0 -or
        $Document.created_at -isnot [string] -or $Document.created_at -cnotmatch '^\d{4}-\d\d-\d\dT') {
        throw 'Factory identity format/API is incompatible; no automatic rekey or migration is permitted.'
    }
}

function Get-EzDarkFactoryIdentity {
    [CmdletBinding()]
    param([string]$Root = $script:EzDarkFactoryDefaultRoot)
    $path = Get-EzDarkFactoryIdentityPath -Root $Root
    $null = Assert-EzDarkFactorySafePath -Path $path -Description 'Factory identity'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'Factory identity is uninitialized. Explicitly run Initialize-EzDarkFactoryIdentity; reads never create an identity.'
    }
    $document = Read-EzDarkFactoryJson -Path $path -SchemaVersion 1
    Assert-EzDarkFactoryIdentityDocument -Document $document
    return $document
}

function Enter-EzDarkFactoryControlLock {
    param([string]$Root = $script:EzDarkFactoryDefaultRoot)
    $paths = Get-EzDarkFactoryPaths -Root $Root
    $lockPath = Join-Path $paths.Locks 'control-root.lock'
    return (Enter-EzDarkFactorySecurityLock -Path $lockPath)
}

function Assert-EzDarkFactoryNoPendingControl {
    param([string]$Root, [string]$IgnoreOperationId = '')
    $paths = Get-EzDarkFactoryPaths -Root $Root
    $submissionDir = Assert-EzDarkFactorySafePath -Path (Join-Path $paths.Runtime 'control/submissions') -Description 'Pending control submissions'
    if (Test-Path -LiteralPath $submissionDir -PathType Container) {
        $entries = @(Get-ChildItem -LiteralPath $submissionDir -File -Filter '*.json' -Force)
        if ($entries.Count -gt 4) { throw 'Detached submission limit exceeded; explicit reconciliation required.' }
        foreach ($file in $entries) {
            if ($file.BaseName -cne $IgnoreOperationId) {
                throw 'A submitted root operation has not been reconciled; cold identity/portability is blocked.'
            }
        }
    }
    $operationDir = Assert-EzDarkFactorySafePath -Path (Join-Path $paths.Runtime 'control/operations') -Description 'Pending control receipts'
    if (Test-Path -LiteralPath $operationDir -PathType Container) {
        $entries = @(Get-ChildItem -LiteralPath $operationDir -File -Filter '*.json' -Force)
        if ($entries.Count -gt 4096) { throw 'Root operation history exceeds the bounded registry; archive terminal receipts explicitly before more mutation.' }
        foreach ($file in $entries) {
            $full = Assert-EzDarkFactorySafePath -Path $file.FullName -Description 'Cold operation receipt'
            if ($file.BaseName -cne $IgnoreOperationId) {
                $receipt = Read-EzDarkFactoryJson -Path $full -SchemaVersion 1
                if ($receipt.state -cnotin @('completed','refused')) {
                    throw 'An accepted/ambiguous root operation blocks cold identity and portability.'
                }
            }
        }
    }
}

function Assert-EzDarkFactoryColdFactory {
    param([string]$Root = $script:EzDarkFactoryDefaultRoot, [string]$IgnoreOperationId = '')
    Assert-EzDarkFactoryNoPendingControl -Root $Root -IgnoreOperationId $IgnoreOperationId
    # A base-build QEMU may exist without an instance intent. Reuse the
    # inherited cold-portability process-ownership rule before rekey/adoption.
    $paths = Get-EzDarkFactoryPaths -Root $Root
    foreach ($process in @(Get-EzDarkFactoryObservedQemuProcesses)) {
        if ([string]::IsNullOrWhiteSpace([string]$process.ExecutablePath)) {
            throw 'Cannot prove a cold factory while QEMU process executable ownership is unknown.'
        }
        if (Test-EzDarkFactoryStoragePathInside -Path $process.ExecutablePath -Directory $paths.Qemu) {
            throw 'Factory identity change requires all managed QEMU processes, including base builders, to be stopped.'
        }
    }
    foreach ($intent in @(Get-EzDarkFactoryInstanceRegistry -Root $Root)) {
        $name = [string]$intent.name
        $paths = Get-EzDarkFactoryInstanceRuntimePaths -Root $Root -InstanceName $name
        if (Test-Path -LiteralPath $paths.Operation) {
            throw "Instance '$name' has an unresolved lifecycle journal; factory identity changes are blocked."
        }
        $guard = Get-EzDarkFactoryInstanceStorageLifecycleGuard -Root $Root -InstanceName $name
        Assert-EzDarkFactoryStorageLifecycleGuard -LifecycleGuard $guard -Operation 'Factory identity change'
    }
}

function Initialize-EzDarkFactoryIdentity {
    [CmdletBinding()]
    param([string]$Root = $script:EzDarkFactoryDefaultRoot)
    $null = Get-EzDarkFactoryRoot -Path $Root
    $lock = Enter-EzDarkFactoryControlLock -Root $Root
    try {
        $path = Get-EzDarkFactoryIdentityPath -Root $Root
        if (Test-Path -LiteralPath $path) {
            # A malformed identity is NOT a reason to generate a replacement.
            return (Get-EzDarkFactoryIdentity -Root $Root)
        }
        Assert-EzDarkFactoryColdFactory -Root $Root
        $dir = [IO.Path]::GetDirectoryName($path)
        $null = Assert-EzDarkFactorySafePath -Path $dir -Description 'Factory runtime'
        [void][IO.Directory]::CreateDirectory($dir)
        $value = [pscustomobject][ordered]@{
            schemaVersion = 1; factory_id = ('fct_' + [guid]::NewGuid().ToString('N'))
            api_major = 1; api_minor = 0; created_at = [DateTime]::UtcNow.ToString('o')
        }
        Write-EzDarkFactoryJson -Path $path -Value $value -SchemaVersion 1
        return (Get-EzDarkFactoryIdentity -Root $Root)
    }
    finally { $lock.Dispose() }
}

function Get-EzDarkFactoryControlRevision {
    [CmdletBinding()]
    param([string]$Root = $script:EzDarkFactoryDefaultRoot)
    $paths = Get-EzDarkFactoryPaths -Root $Root
    $files = New-Object 'System.Collections.Generic.List[string]'
    $files.Add((Get-EzDarkFactoryIdentityPath -Root $Root))
    if (Test-Path -LiteralPath $paths.Instances -PathType Container) {
        $null = Assert-EzDarkFactorySafePath -Path $paths.Instances -Description 'Revision instances directory'
        foreach ($dir in @(Get-ChildItem -LiteralPath $paths.Instances -Directory -Force | Sort-Object Name)) {
            Assert-EzDarkFactoryStorageInstanceName -Name $dir.Name
            foreach ($part in @('instance.json', 'control-instance.json', 'runtime.json', 'lifecycle-operation.json', 'access.json')) {
                $files.Add((Join-Path $dir.FullName $part))
            }
            $files.Add((Join-Path $dir.FullName 'ssh/access.json'))
        }
    }
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $text = New-Object Text.StringBuilder
        foreach ($path in $files) {
            $full = Assert-EzDarkFactorySafePath -Path $path -Description 'Control revision source'
            [void]$text.Append($full.Substring($paths.Root.Length).Replace('\','/')).Append(':')
            if ([IO.File]::Exists($full)) {
                $info = New-Object IO.FileInfo($full)
                if ($info.Length -gt 1048576) { throw 'Control revision input exceeds 1 MiB; refuse an unbounded or malformed state file.' }
                $bytes = [IO.File]::ReadAllBytes($full)
                [void]$text.Append(([BitConverter]::ToString($hash.ComputeHash($bytes))).Replace('-','').ToLowerInvariant())
            }
            else { [void]$text.Append('missing') }
            [void]$text.Append([char]10)
        }
        return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($text.ToString())))).Replace('-','').ToLowerInvariant()
    }
    finally { $hash.Dispose() }
}

function Get-EzDarkFactoryControlCapabilities {
    [CmdletBinding()]
    param([string]$Root = $script:EzDarkFactoryDefaultRoot)
    $identity = Get-EzDarkFactoryIdentity -Root $Root
    return [pscustomobject][ordered]@{
        schemaVersion = 1; factory_id = $identity.factory_id
        api = [pscustomobject]@{ major = 1; minor = 0 }
        capabilities = @(
            'factory.info', 'factory.doctor', 'factory.portability', 'factory.rekey',
            'instance.list', 'instance.get', 'instance.resources', 'instance.readiness',
            'instance.logs', 'instance.diagnose', 'instance.adopt', 'instance.create',
            'instance.start', 'instance.stop', 'instance.reset', 'instance.clone',
            'instance.export', 'instance.import', 'instance.exec', 'instance.shell_descriptor',
            'instance.copy_to', 'instance.copy_from', 'operation.get'
        )
        revision = Get-EzDarkFactoryControlRevision -Root $Root
    }
}

function Get-EzDarkFactoryInstanceRef {
    [CmdletBinding()]
    param([string]$Root = $script:EzDarkFactoryDefaultRoot, [Parameter(Mandatory)][string]$Name)
    $intent = Get-EzDarkFactoryInstanceIntent -Root $Root -InstanceName $Name
    $file = Join-Path (Get-EzDarkFactoryInstanceRuntimePaths -Root $Root -InstanceName $Name).Directory 'control-instance.json'
    $null = Assert-EzDarkFactorySafePath -Path $file -Description 'Instance identity'
    $id = $null
    if (Test-Path -LiteralPath $file) {
        $ref = Read-EzDarkFactoryJson -Path $file -SchemaVersion 1
        $keys = @($ref.PSObject.Properties | ForEach-Object { $_.Name })
        if ($keys.Count -ne 3 -or @(@('schemaVersion', 'instance_id', 'created_at') | Where-Object { $keys -cnotcontains $_ }).Count -gt 0 -or
            $ref.instance_id -isnot [string] -or $ref.instance_id -cnotmatch '^ins_[a-f0-9]{32}$') {
            throw "Instance '$Name' has incompatible control identity; no silent replacement is allowed."
        }
        $id = [string]$ref.instance_id
    }
    return [pscustomobject][ordered]@{
        factory_id = (Get-EzDarkFactoryIdentity -Root $Root).factory_id
        instance_id = $id; instance_generation = $(if ($intent.schemaVersion -eq 2) { [string]$intent.identityGeneration } else { $null })
        name = $Name; adoption_required = ($null -eq $id)
    }
}

function New-EzDarkFactoryInstanceRef {
    param([string]$Root, [string]$Name)
    $ref = Get-EzDarkFactoryInstanceRef -Root $Root -Name $Name
    if ($null -ne $ref.instance_id) { throw "Instance '$Name' already has a durable control identity." }
    if ($null -eq $ref.instance_generation) { throw 'Legacy instance lacks a durable generation; explicit supported migration is required.' }
    $file = Join-Path (Get-EzDarkFactoryInstanceRuntimePaths -Root $Root -InstanceName $Name).Directory 'control-instance.json'
    $record = [pscustomobject][ordered]@{
        schemaVersion = 1; instance_id = ('ins_' + [guid]::NewGuid().ToString('N'))
        created_at = [DateTime]::UtcNow.ToString('o')
    }
    Write-EzDarkFactoryJson -Path $file -Value $record -SchemaVersion 1
    return (Get-EzDarkFactoryInstanceRef -Root $Root -Name $Name)
}

function Resolve-EzDarkFactoryControlTarget {
    param([string]$Root, [object]$Request, [bool]$AllowAdoption = $false)
    $id = [string]$Request.instance_id
    $generation = [string]$Request.instance_generation
    $name = [string]$Request.arguments.name
    if ($AllowAdoption) {
        Assert-EzDarkFactoryStorageInstanceName -Name $name
        $ref = Get-EzDarkFactoryInstanceRef -Root $Root -Name $name
        if (-not $ref.adoption_required -or $ref.instance_generation -cne $generation -or $id -cne '') {
            throw 'Adoption requires an unadopted name and exact current generation; refresh first.'
        }
        return $ref
    }
    if ($id -cnotmatch '^ins_[a-f0-9]{32}$' -or $generation -cnotmatch '^[a-f0-9]{32}$') {
        throw 'Opaque instance ID and current generation are required; display name is not authority.'
    }
    foreach ($intent in @(Get-EzDarkFactoryInstanceRegistry -Root $Root)) {
        $candidate = Get-EzDarkFactoryInstanceRef -Root $Root -Name ([string]$intent.name)
        if ($candidate.instance_id -ceq $id) {
            if ($candidate.instance_generation -cne $generation) { throw 'Stale instance generation; refresh and reconfirm.' }
            if (-not [string]::IsNullOrWhiteSpace($name) -and $name -cne $candidate.name) { throw 'Instance display name differs from target identity.' }
            return $candidate
        }
    }
    throw 'Instance ID is unknown or not adopted; no mutation was attempted.'
}

function Get-EzDarkFactoryControlRequestDigest {
    param([object]$Request)
    $payload = ConvertTo-Json -InputObject $Request -Depth 30 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-EzDarkFactoryControlOperationPath {
    param([string]$Root, [string]$OperationId)
    if ($OperationId -cnotmatch '^[a-f0-9]{32}$') { throw 'Operation ID must be 32 lowercase hex characters.' }
    $path = Join-Path (Get-EzDarkFactoryPaths -Root $Root).Runtime ('control/operations/' + $OperationId + '.json')
    return (Assert-EzDarkFactorySafePath -Path $path -Description 'Operation journal')
}

# Concurrent read-only observers may briefly hit a Windows sharing violation
# while Write-EzDarkFactoryJson atomically publishes a terminal receipt. Use a
# delete-share-compatible, bounded read; retry only IO acquisition races.
# Never retry the underlying operation and never treat a malformed receipt as
# success. The upper bound is 20 attempts x 25 ms (under ~500 ms).
function Read-EzDarkFactoryControlReceiptJson {
    param([Parameter(Mandatory)][string]$Path)
    $full = Assert-EzDarkFactorySafePath -Path $Path -Description 'Control receipt'
    $share = [IO.FileShare]([int][IO.FileShare]::ReadWrite -bor [int][IO.FileShare]::Delete)
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        $stream = $null
        try {
            $stream = [IO.File]::Open($full, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
            if ($stream.Length -gt 1048576) { throw 'Control receipt exceeds its 1-MiB read limit.' }
            $data = New-Object byte[] ([int]$stream.Length)
            $count = 0
            while ($count -lt $data.Length) {
                $read = $stream.Read($data, $count, $data.Length - $count)
                if ($read -le 0) { throw 'Control receipt truncated during a bounded read.' }
                $count += $read
            }
            $text = (New-Object Text.UTF8Encoding($false, $true)).GetString($data, 0, $count)
            return (ConvertFrom-EzDarkFactoryJsonText -Text $text -SchemaVersion 1 -Description 'Control receipt')
        }
        catch [IO.IOException] {
            # Deletion is a state transition for the caller, not a sharing
            # retry budget against a path that no longer exists.
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw }
            if ($attempt -eq 19) { throw }
            Start-Sleep -Milliseconds 25
        }
        finally { if ($null -ne $stream) { $stream.Dispose() } }
    }
    throw 'Control receipt could not be read after the bounded sharing-violation budget.'
}

function Get-EzDarkFactoryControlOperation {
    [CmdletBinding()]
    param([string]$Root = $script:EzDarkFactoryDefaultRoot, [Parameter(Mandatory)][string]$OperationId)
    $path = Get-EzDarkFactoryControlOperationPath -Root $Root -OperationId $OperationId
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $record = Read-EzDarkFactoryControlReceiptJson -Path $path
    if ($record.operation_id -cne $OperationId) { throw 'Operation record identity mismatch.' }
    return $record
}

function New-EzDarkFactoryControlResponse {
    param([object]$Request, [string]$FactoryId, [string]$State, [object]$Data = $null,
        [string]$Code = '', [string]$Message = '')
    $effectiveId = [string]$Request.instance_id
    $effectiveGeneration = [string]$Request.instance_generation
    if ($null -ne $Data -and [string]$Request.command -in @('instance.create','instance.import','instance.adopt')) {
        $ref = $null
        if ($Data.PSObject.Properties['target']) { $ref = $Data.target }
        elseif ($Data.PSObject.Properties['instance_id']) { $ref = $Data }
        if ($null -ne $ref -and $ref.PSObject.Properties['instance_id'] -and $ref.PSObject.Properties['instance_generation']) {
            $effectiveId = [string]$ref.instance_id
            $effectiveGeneration = [string]$ref.instance_generation
        }
    }
    return [pscustomobject][ordered]@{
        schemaVersion = 1; api = [pscustomobject]@{ major = 1; minor = 0 }
        factory_id = $FactoryId
        operation_id = [string]$Request.operation_id
        command = [string]$Request.command
        instance_id = $effectiveId
        instance_generation = $effectiveGeneration
        state = $State; data = $Data
        progress = [pscustomobject]@{ stage = $State; terminal = ($State -in @('completed','refused')) }
        refusal = $(if ($Code) { [pscustomobject]@{ code = $Code; message = (Protect-EzDarkFactoryDiagnosticText -Text $Message) } } else { $null })
    }
}

function Assert-EzDarkFactoryControlRequest {
    param([object]$Request)
    if ($null -eq $Request -or $Request -isnot [pscustomobject]) { throw 'Control request must be a plain JSON object.' }
    $expected = @('schemaVersion','api','factory_id','operation_id','command','capabilities','expected_revision','instance_id','instance_generation','arguments')
    $fields = @($Request.PSObject.Properties | ForEach-Object { $_.Name })
    if ($fields.Count -ne $expected.Count -or @($expected | Where-Object { $fields -cnotcontains $_ }).Count -ne 0) {
        throw 'Control request has missing or unknown envelope fields.'
    }
    if (@($Request.api.PSObject.Properties | ForEach-Object { $_.Name }).Count -ne 2 -or
        @(@('major','minor') | Where-Object { @($Request.api.PSObject.Properties.Name) -cnotcontains $_ }).Count -gt 0) {
        throw 'Control API version must have exactly major and minor.'
    }
    if (($Request.schemaVersion -isnot [int] -and $Request.schemaVersion -isnot [long]) -or $Request.schemaVersion -ne 1 -or
        $null -eq $Request.api -or ($Request.api.major -isnot [int] -and $Request.api.major -isnot [long]) -or
        ($Request.api.minor -isnot [int] -and $Request.api.minor -isnot [long]) -or
        $Request.api.major -ne 1 -or $Request.api.minor -gt 0 -or $Request.api.minor -lt 0) {
        throw 'Unsupported control API/schema version; no downgrade is permitted.'
    }
    if ($Request.factory_id -isnot [string] -or $Request.factory_id -cnotmatch '^fct_[a-f0-9]{32}$' -or
        $Request.operation_id -isnot [string] -or $Request.operation_id -cnotmatch '^[a-f0-9]{32}$' -or
        $Request.command -isnot [string] -or $Request.command.Length -gt 64 -or
        $Request.capabilities -isnot [array] -or $Request.expected_revision -isnot [string] -or
        $Request.instance_id -isnot [string] -or $Request.instance_generation -isnot [string] -or
        $Request.arguments -isnot [pscustomobject]) {
        throw 'Control request identity, operation ID or typed fields are malformed.'
    }
    $argumentFields = @{
        'factory.info' = @(); 'factory.doctor' = @(); 'factory.portability' = @(); 'factory.rekey' = @()
        'instance.list' = @(); 'operation.get' = @('operation_id')
        'instance.get' = @('name'); 'instance.resources' = @('name')
        'instance.readiness' = @('name'); 'instance.diagnose' = @('name')
        'instance.shell_descriptor' = @('name'); 'instance.logs' = @('name','kind','maximum_characters')
        'instance.adopt' = @('name'); 'instance.create' = @('name','profile','base_id')
        'instance.import' = @('name','image_path','manifest_path','profile')
        'instance.start' = @('name'); 'instance.stop' = @('name'); 'instance.reset' = @('name')
        'instance.clone' = @('name','destination_name','mode')
        'instance.export' = @('name','destination_directory')
        'instance.exec' = @('name','argv')
        'instance.copy_to' = @('name','host_path','guest_path')
        'instance.copy_from' = @('name','host_path','guest_path')
    }
    if (-not $argumentFields.ContainsKey($Request.command)) { throw 'Unknown control command.' }
    $actualArgs = @($Request.arguments.PSObject.Properties | ForEach-Object { $_.Name })
    $requiredArgs = @($argumentFields[[string]$Request.command])
    if ($actualArgs.Count -ne $requiredArgs.Count -or
        @($requiredArgs | Where-Object { $actualArgs -cnotcontains $_ }).Count -gt 0) {
        throw 'Typed arguments must have exactly the declared fields.'
    }
    foreach ($property in $Request.arguments.PSObject.Properties) {
        $value = $property.Value
        if ($property.Name -ceq 'argv') { continue }
        if ($property.Name -ceq 'maximum_characters') {
            if (($value -isnot [int] -and $value -isnot [long]) -or $value -lt 1 -or $value -gt 8192) {
                throw 'Log limit must be an integer from 1 to 8192.'
            }
        }
        elseif ($value -isnot [string] -or $value.Length -gt 4096 -or $value -match '[\x00-\x1f\x7f]') {
            throw ('Typed argument ' + $property.Name + ' must be a bounded control-character-free string.')
        }
    }
    if ($Request.expected_revision -cne '' -and $Request.expected_revision -cnotmatch '^[a-f0-9]{64}$') {
        throw 'Expected revision must be an exact 64-character lowercase SHA-256 or empty for observations.'
    }
    if ($Request.command -ceq 'instance.clone' -and $Request.arguments.mode -cnotin @('fresh','stateful')) {
        throw 'Clone mode must be exactly fresh or stateful.'
    }
    if ($Request.command -like 'factory.*' -or $Request.command -ceq 'instance.list' -or
        $Request.command -ceq 'instance.create' -or $Request.command -ceq 'instance.import' -or
        $Request.command -ceq 'operation.get') {
        if ($Request.instance_id -cne '' -or $Request.instance_generation -cne '') {
            throw 'Factory/creation/reconciliation command must not claim an existing instance target.'
        }
    }
    if ($Request.command -ceq 'instance.exec' -and
        (@($Request.arguments.argv).Count -gt 64 -or
         @($Request.arguments.argv | Where-Object { $_ -isnot [string] -or $_.Length -gt 4096 }).Count -gt 0)) {
        throw 'Exec argv must be bounded strings.'
    }
    if (@($Request.capabilities).Count -gt 32 -or @($Request.capabilities | Where-Object { $_ -isnot [string] -or $_ -cnotmatch '^[a-z_.]{1,64}$' }).Count -gt 0) {
        throw 'Capabilities must be a bounded array of declared capability IDs.'
    }
}


# The dispatch spool lives under the authoritative root. It is deliberately
# separate from operation receipts: a launched child is not yet an accepted VM
# mutation until Invoke-EzDarkFactoryControl publishes its accepted record.
function Get-EzDarkFactoryControlSubmissionPath {
    param([string]$Root, [string]$OperationId)
    if ($OperationId -cnotmatch '^[a-f0-9]{32}$') { throw 'Invalid detached operation identifier.' }
    $paths = Get-EzDarkFactoryPaths -Root $Root
    return (Assert-EzDarkFactorySafePath -Path (Join-Path $paths.Runtime ('control/submissions/' + $OperationId + '.json')) -Description 'Detached control submission')
}

function Get-EzDarkFactoryControlDispatchResultPath {
    param([string]$Root, [string]$OperationId)
    if ($OperationId -cnotmatch '^[a-f0-9]{32}$') { throw 'Invalid detached operation identifier.' }
    $paths = Get-EzDarkFactoryPaths -Root $Root
    return (Assert-EzDarkFactorySafePath -Path (Join-Path $paths.Runtime ('control/dispatch-results/' + $OperationId + '.json')) -Description 'Detached precondition result')
}

function Get-EzDarkFactoryControlOperationResult {
    [CmdletBinding()]
    param([string]$Root = $script:EzDarkFactoryDefaultRoot, [Parameter(Mandatory)][string]$OperationId)
    $dispatchPath = Get-EzDarkFactoryControlDispatchResultPath -Root $Root -OperationId $OperationId
    $submission = Get-EzDarkFactoryControlSubmissionPath -Root $Root -OperationId $OperationId
    # A terminal result is published BEFORE the transient submission is
    # removed. Reconcile a bounded number of complete authority snapshots
    # rather than assuming Test-Path and subsequent Open are atomic.
    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        $receipt = Get-EzDarkFactoryControlOperation -Root $Root -OperationId $OperationId
        if ($null -ne $receipt) { return $receipt }
        if (Test-Path -LiteralPath $dispatchPath -PathType Leaf) {
            try { $record = Read-EzDarkFactoryControlReceiptJson -Path $dispatchPath }
            catch {
                if (-not (Test-Path -LiteralPath $dispatchPath -PathType Leaf)) {
                    Start-Sleep -Milliseconds 15
                    continue
                }
                throw
            }
            if ($record.operation_id -cne $OperationId -or $record.state -cne 'refused' -or
                $record.request_sha256 -cnotmatch '^[a-f0-9]{64}$') {
                throw 'Malformed detached precondition result; explicit reconciliation required.'
            }
            return $record
        }
        if (Test-Path -LiteralPath $submission -PathType Leaf) {
            try { $pending = Read-EzDarkFactoryControlReceiptJson -Path $submission }
            catch {
                if (-not (Test-Path -LiteralPath $submission -PathType Leaf)) {
                    Start-Sleep -Milliseconds 15
                    continue
                }
                throw
            }
            Assert-EzDarkFactoryControlRequest -Request $pending
            if ($pending.operation_id -cne $OperationId) { throw 'Detached submission identity mismatch.' }
            return [pscustomobject][ordered]@{
                schemaVersion = 1; factory_id = [string]$pending.factory_id
                operation_id = $OperationId
                request_sha256 = Get-EzDarkFactoryControlRequestDigest -Request $pending
                state = 'submitted'; accepted = $false
                progress = [pscustomobject]@{ stage = 'awaiting-root-receipt'; terminal = $false }
            }
        }
        if ($attempt -lt 4) { Start-Sleep -Milliseconds 15 }
    }
    return $null
}

function Start-EzDarkFactoryDetachedControlOperation {
    [CmdletBinding()]
    param([string]$Root = $script:EzDarkFactoryDefaultRoot,
        [Parameter(Mandatory)][object]$Request,
        [string]$ManagerWorkspace = '',
        [ValidateRange(1,8)][int]$MaxConcurrentRoots = 2)
    Assert-EzDarkFactoryControlRequest -Request $Request
    $rootPath = Get-EzDarkFactoryRoot -Path $Root
    $workerPath = Assert-EzDarkFactorySafePath -Path (Join-Path $rootPath 'ezdarkfactory-worker.ps1') -Description 'Detached root worker'
    if (-not (Test-Path -LiteralPath $workerPath -PathType Leaf)) {
        throw 'Detached worker script is missing from this factory; no operation was submitted.'
    }
    if ($ManagerWorkspace) {
        $null = Get-EzDarkFactoryManagerRegistry -Workspace $ManagerWorkspace
    }
    $command = [string]$Request.command
    if ($command -in @('factory.info','factory.doctor','factory.portability','instance.list','instance.get',
        'instance.resources','instance.readiness','instance.logs','instance.diagnose','instance.shell_descriptor','operation.get')) {
        throw 'The detached worker accepts mutations only. Observations stay read-only and unjournaled.'
    }
    $lock = Enter-EzDarkFactoryControlLock -Root $rootPath
    try {
        $factory = Get-EzDarkFactoryIdentity -Root $rootPath
        if ($factory.factory_id -cne $Request.factory_id) { throw 'Stale factory ID; detached mutation refused before submission.' }
        $caps = Get-EzDarkFactoryControlCapabilities -Root $rootPath
        if ($caps.capabilities -cnotcontains $command -or
            @($Request.capabilities | Where-Object { $caps.capabilities -cnotcontains $_ }).Count -ne 0) {
            throw 'Unadvertised capability; detached mutation refused.'
        }
        $digest = Get-EzDarkFactoryControlRequestDigest -Request $Request
        $existing = Get-EzDarkFactoryControlOperationResult -Root $rootPath -OperationId $Request.operation_id
        if ($null -ne $existing) {
            if ($existing.request_sha256 -cne $digest -or $existing.factory_id -cne $factory.factory_id) {
                throw 'Operation ID previously belongs to a different request/factory.'
            }
            # Never spawn a second worker for a completed, failed or ambiguous ID.
            return [pscustomobject][ordered]@{
                schemaVersion = 1; api = [pscustomobject]@{ major = 1; minor = 0 }
                state = 'existing'; operation_id = $Request.operation_id
                factory_id = $factory.factory_id; accepted = ($existing.state -ceq 'accepted')
                reconciliation = $existing
            }
        }
        $requestPath = Get-EzDarkFactoryControlSubmissionPath -Root $rootPath -OperationId $Request.operation_id
        if (Test-Path -LiteralPath $requestPath) {
            throw 'A previous detached request has unresolved launch/receipt status; do not replay it.'
        }
        Assert-EzDarkFactoryNoPendingControl -Root $rootPath -IgnoreOperationId $Request.operation_id
        $current = Get-EzDarkFactoryControlRevision -Root $rootPath
        if ($Request.expected_revision -cne $current) { throw 'Stale root revision; detached mutation refused before submission.' }
        if ($command -like 'instance.*' -and $command -cnotin @('instance.create','instance.import')) {
            $null = Resolve-EzDarkFactoryControlTarget -Root $rootPath -Request $Request -AllowAdoption:($command -ceq 'instance.adopt')
        }
        if ($command -ceq 'factory.rekey') { Assert-EzDarkFactoryColdFactory -Root $rootPath -IgnoreOperationId $Request.operation_id }
        # The worker runs in an intentionally non-authoritative CWD. Relative
        # host paths must never resolve against that process or the manager's
        # current directory; pin a reviewed absolute safe host path instead.
        foreach ($field in @('host_path','image_path','manifest_path','destination_directory')) {
            $property = $Request.arguments.PSObject.Properties[$field]
            if ($null -ne $property -and -not [string]::IsNullOrEmpty([string]$property.Value)) {
                $hostPath = [string]$property.Value
                if (-not [IO.Path]::IsPathRooted($hostPath)) {
                    throw ('Detached host path ' + $field + ' must be absolute before the worker launches.')
                }
                $null = Assert-EzDarkFactorySafePath -Path $hostPath -Description ('Detached host path ' + $field)
            }
        }
        $payload = ConvertTo-Json -InputObject $Request -Depth 32 -Compress
        if ([Text.Encoding]::UTF8.GetByteCount($payload) -gt 65536) { throw 'Detached request exceeds the 64-KiB bound.' }
        Assert-EzDarkFactoryCredentialFreeText -Text $payload -Description 'Detached root request'
        $requestDirectory = [IO.Path]::GetDirectoryName($requestPath)
        [void][IO.Directory]::CreateDirectory($requestDirectory)
        # This transient file can contain argv/paths. Restrict the parent before
        # publishing, and authenticate a single-link private file afterward.
        # No insecure fallback is permitted on either Windows engine.
        Set-EzDarkFactoryPrivateAcl -Path $requestDirectory -Directory
        # Bounded per-root submission queue; active operations belong to the
        # child process, not the manager UI or hidden machine-local state.
        $outstanding = @(Get-ChildItem -LiteralPath $requestDirectory -File -Filter '*.json' -Force)
        if ($outstanding.Count -ge 4) { throw 'This factory has four unresolved submitted operations; reconcile before submitting more.' }
        try {
            Write-EzDarkFactoryJson -Path $requestPath -Value $Request -SchemaVersion 1
            Set-EzDarkFactoryPrivateAcl -Path $requestPath
        }
        catch {
            if (Test-Path -LiteralPath $requestPath -PathType Leaf) {
                Remove-Item -LiteralPath $requestPath -Force -ErrorAction Stop
            }
            throw 'Could not protect detached request data; no operation was launched.'
        }

        $child = $null
        $started = $false
        $workerProcessId = 0
        try {
            $powerShell = if ($PSVersionTable.PSVersion.Major -eq 5) { Join-Path $PSHOME 'powershell.exe' } else { Join-Path $PSHOME 'pwsh.exe' }
            if (-not (Test-Path -LiteralPath $powerShell -PathType Leaf)) { throw 'PowerShell child executable is missing.' }
            $escapedWorker = $workerPath.Replace("'", "''")
            $cmd = "& '" + $escapedWorker + "' -OperationId '" + [string]$Request.operation_id + "'"
            if ($ManagerWorkspace) {
                $escapedWorkspace = (Assert-EzDarkFactorySafePath -Path $ManagerWorkspace -Description 'Manager workspace').Replace("'", "''")
                $cmd += " -ManagerWorkspace '" + $escapedWorkspace + "' -MaxConcurrentRoots " + $MaxConcurrentRoots
            }
            $start = New-Object Diagnostics.ProcessStartInfo
            $start.FileName = $powerShell
            # A detached worker must not pin the factory folder as its
            # process CWD after its durable result is already finalized.
            # No authority or state is stored in this host working directory.
            $start.WorkingDirectory = [IO.Path]::GetTempPath()
            $start.UseShellExecute = $false
            $start.CreateNoWindow = $true
            $start.RedirectStandardOutput = $true
            $start.RedirectStandardError = $true
            $start.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' +
                [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
            $child = New-Object Diagnostics.Process
            $child.StartInfo = $start
            $started = $child.Start()
            if (-not $started) { throw 'Operating system refused to start the detached control worker.' }
            $workerProcessId = [int]$child.Id
        }
        catch {
            if (-not $started -and (Test-Path -LiteralPath $requestPath -PathType Leaf)) {
                # No child was created. Do not retain a falsely accepted request.
                Remove-Item -LiteralPath $requestPath -Force -ErrorAction Stop
            }
            throw
        }
        finally { if ($null -ne $child) { $child.Dispose() } }
        # 'dispatched' is NOT 'accepted'. Consumers reconcile the root-local
        # operation.get response; they never retry solely because UI closed.
        return [pscustomobject][ordered]@{
            schemaVersion = 1; api = [pscustomobject]@{ major = 1; minor = 0 }
            state = 'dispatched'; factory_id = $factory.factory_id
            operation_id = [string]$Request.operation_id; command = $command
            instance_id = [string]$Request.instance_id; instance_generation = [string]$Request.instance_generation
            accepted = $false; reconciliation = 'operation.get'
            # Advisory launch telemetry only, never ownership or kill authority.
            worker_pid = $workerProcessId
        }
    }
    finally { $lock.Dispose() }
}

function Invoke-EzDarkFactoryDetachedControlWorker {
    param([string]$Root, [string]$OperationId, [string]$ManagerWorkspace = '',
        [ValidateRange(1,8)][int]$MaxConcurrentRoots = 2)
    $submission = Get-EzDarkFactoryControlSubmissionPath -Root $Root -OperationId $OperationId
    $request = Read-EzDarkFactoryJson -Path $submission -SchemaVersion 1
    if ($request.operation_id -cne $OperationId) { throw 'Detached request filename and operation identity differ.' }
    $budget = $null
    $result = $null
    try {
        if ($ManagerWorkspace) {
            # Own the host-budget lock for the *entire* underlying mutation. It
            # remains held even when the TUI or manager process has exited.
            $budget = Enter-EzDarkFactoryManagerBudgetSlot -Workspace $ManagerWorkspace -Limit $MaxConcurrentRoots -TimeoutSeconds 600
            # A newly reachable copied root can collide while this worker
            # waits for host budget. Re-check the *whole* enrolled fleet
            # immediately before a root-owned operation can be accepted.
            $fleet = @(Get-EzDarkFactoryManagerObservations -Workspace $ManagerWorkspace)
            $canonical = Get-EzDarkFactoryRoot -Path $Root
            $pathComparison = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
                [StringComparison]::OrdinalIgnoreCase
            } else { [StringComparison]::Ordinal }
            $matches = @($fleet | Where-Object {
                [string]::Equals([string]$_.canonical_path, $canonical, $pathComparison)
            })
            if ($matches.Count -ne 1 -or $matches[0].state -cne 'current' -or
                $matches[0].factory_id -cne $request.factory_id -or
                $matches[0].observed_factory_id -cne $request.factory_id) {
                throw 'Enrolled factory identity or fleet collision changed before detached execution; reconcile, never replay.'
            }
        }
        $result = Invoke-EzDarkFactoryControl -Root $Root -Request $request -DetachedWorker
    }
    catch {
        $result = New-EzDarkFactoryControlResponse -Request $request -FactoryId ([string]$request.factory_id) -State 'refused' -Code 'worker_failed' -Message $_.Exception.Message
    }
    finally { if ($null -ne $budget) { $budget.Dispose() } }
    $receipt = Get-EzDarkFactoryControlOperation -Root $Root -OperationId $OperationId
    if ($null -eq $receipt) {
        # A stale/invalidated confirmation has no mutation journal. Publish a
        # separate bounded refusal so manager restart can reconcile its result.
        $dispatchPath = Get-EzDarkFactoryControlDispatchResultPath -Root $Root -OperationId $OperationId
        $parent = [IO.Path]::GetDirectoryName($dispatchPath)
        [void][IO.Directory]::CreateDirectory($parent)
        $record = [pscustomobject][ordered]@{
            schemaVersion = 1; operation_id = $OperationId
            request_sha256 = Get-EzDarkFactoryControlRequestDigest -Request $request
            factory_id = [string]$request.factory_id
            state = 'refused'; refusal = $result.refusal
            finished_at = [DateTime]::UtcNow.ToString('o')
        }
        Write-EzDarkFactoryJson -Path $dispatchPath -Value $record -SchemaVersion 1
    }
    if ($result.state -in @('completed','refused')) {
        # If the worker dies before cleanup, the request file is retained for
        # explicit reconciliation but must never authorize automatic replay.
        $null = Assert-EzDarkFactorySafePath -Path $submission -Description 'Terminal request cleanup'
        Remove-Item -LiteralPath $submission -Force -ErrorAction Stop
    }
}

function Get-EzDarkFactoryManagedShellDescriptor {
    param([string]$Root, [object]$Target)
    $rootPath = Get-EzDarkFactoryRoot -Path $Root
    $launcher = Assert-EzDarkFactorySafePath -Path (Join-Path $rootPath 'ezdarkfactory-attach.ps1') -Description 'Managed shell launcher'
    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { throw 'Managed shell launcher missing from factory root.' }
    # A RUNNING QEMU process is not SSH READY authority. Resolve readiness
    # from the same authenticated launch/access contract as instance.readiness.
    $readiness = Get-EzDarkFactoryControlReadiness -Root $rootPath -Target $Target
    $shell = if ($PSVersionTable.PSVersion.Major -eq 5) { Join-Path $PSHOME 'powershell.exe' } else { Join-Path $PSHOME 'pwsh.exe' }
    if (-not (Test-Path -LiteralPath $shell -PathType Leaf)) { throw 'Managed shell host PowerShell is unavailable.' }
    $revision = Get-EzDarkFactoryControlRevision -Root $rootPath
    return [pscustomobject][ordered]@{
        schemaVersion = 1; kind = 'managed-ssh-attach'; factory_id = $Target.factory_id
        instance_id = $Target.instance_id; instance_generation = $Target.instance_generation
        state = [string]$readiness.lifecycle; ready = ($readiness.readiness -ceq 'ready')
        command = [pscustomobject][ordered]@{
            executable = $shell
            argv = [string[]]@('-NoLogo','-NoProfile','-File',$launcher,
                '-FactoryId',[string]$Target.factory_id,
                '-InstanceId',[string]$Target.instance_id,
                '-InstanceGeneration',[string]$Target.instance_generation,
                '-ExpectedRevision',$revision)
        }
        warning = 'Explicit attach only; the launcher rechecks factory/revision/generation and managed SSH trust before opening a guest session.'
    }
}

function Read-EzDarkFactoryControlLogTail {
    param([Parameter(Mandatory)][string]$Path,
        [ValidateRange(1,8192)][int]$MaximumCharacters)
    $full = Assert-EzDarkFactorySafePath -Path $Path -Description 'Managed log tail'
    $stream = [IO.File]::Open($full, [IO.FileMode]::Open, [IO.FileAccess]::Read,
        [IO.FileShare]::ReadWrite)
    try {
        # Seeking before decoding bounds both I/O and memory even when QEMU
        # logs are many GiB. The first partial UTF-8 sequence is replacement
        # data, never executable terminal control.
        $limit = [int][Math]::Min(32768, $MaximumCharacters * 4 + 32)
        $length = [long]$stream.Length
        $offset = [long][Math]::Max(0, $length - $limit)
        if ($offset -gt 0) { $null = $stream.Seek($offset, [IO.SeekOrigin]::Begin) }
        $bytes = New-Object byte[] $limit
        $count = 0
        while ($count -lt $bytes.Length) {
            $n = $stream.Read($bytes, $count, $bytes.Length - $count)
            if ($n -eq 0) { break }
            $count += $n
        }
        $text = (New-Object Text.UTF8Encoding($false, $false)).GetString($bytes, 0, $count)
        $truncated = ($offset -gt 0 -or $text.Length -gt $MaximumCharacters)
        if ($text.Length -gt $MaximumCharacters) {
            $text = $text.Substring($text.Length - $MaximumCharacters)
        }
        $clean = Protect-EzDarkFactoryDiagnosticText -Text $text -MaximumCharacters 8192
        if ($clean.Length -gt $MaximumCharacters) {
            $clean = $clean.Substring(0, $MaximumCharacters)
            $truncated = $true
        }
        return [pscustomobject][ordered]@{
            text = $clean; truncated = [bool]$truncated; source_bytes = $length
        }
    }
    finally { $stream.Dispose() }
}

function Get-EzDarkFactoryControlReadiness {
    param([string]$Root, [object]$Target)
    $status = Get-EzDarkFactoryManagedInstanceStatus -Root $Root -InstanceName ([string]$Target.name)
    $readiness = 'not-ready'
    $reason = 'Instance has no currently verified RUNNING lifecycle.'
    if ($status.state -ceq 'RUNNING') {
        $readiness = 'unknown'
        try {
            # The accepted access-state contract checks current launch ID,
            # reviewed provisioning identity and authenticated READY evidence.
            $null = Get-EzDarkFactorySshAccessState -Root $Root -InstanceName $Target.name -RequireReady
            $readiness = 'ready'
            $reason = 'Authenticated SSH READY evidence matches the current launch.'
        }
        catch { $reason = Protect-EzDarkFactoryDiagnosticText -Text $_.Exception.Message -MaximumCharacters 1024 }
    }
    return [pscustomobject][ordered]@{
        schemaVersion = 1; target = $Target; lifecycle = [string]$status.state
        readiness = $readiness
        reason = Protect-EzDarkFactoryDiagnosticText -Text $reason -MaximumCharacters 1024
    }
}

function Get-EzDarkFactoryControlDiagnosis {
    [CmdletBinding()]
    param([string]$Root = $script:EzDarkFactoryDefaultRoot,
          [Parameter(Mandatory)][object]$Target)
    # EDF-005 diagnostics deliberately use the accepted read-only runtime
    # status observer; no speculative QMP, repair, or storage operation occurs.
    $status = Get-EzDarkFactoryManagedInstanceStatus -Root $Root -InstanceName ([string]$Target.name)
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        target = $Target
        state = [string]$status.state
        reason = Protect-EzDarkFactoryDiagnosticText -Text ([string]$status.reason) -MaximumCharacters 2048
        readiness = $(if ($status.state -ceq 'RUNNING') { 'unknown' } else { 'not-ready' })
        resource_profile = [pscustomobject][ordered]@{
            cpus = $status.cpus
            memoryMiB = $status.memoryMiB
            profile = $status.profile
        }
        repair_attempted = $false
    }
}

function Invoke-EzDarkFactoryControl {
    [CmdletBinding()]
    param([string]$Root = $script:EzDarkFactoryDefaultRoot, [Parameter(Mandatory)][object]$Request,
        [switch]$DetachedWorker)
    $factoryId = ''
    try {
        Assert-EzDarkFactoryControlRequest -Request $Request
        $identity = Get-EzDarkFactoryIdentity -Root $Root
        $factoryId = [string]$identity.factory_id
        if ($Request.factory_id -cne $factoryId) { throw 'Stale factory identity. No operation was executed.' }
        $caps = Get-EzDarkFactoryControlCapabilities -Root $Root
        if ($caps.capabilities -cnotcontains [string]$Request.command -or
            @($Request.capabilities | Where-Object { $caps.capabilities -cnotcontains $_ }).Count -gt 0) {
            throw 'Unadvertised command/capability; no operation was executed.'
        }
        $command = [string]$Request.command
        $readOnly = $command -in @('factory.info','factory.doctor','factory.portability','instance.list','instance.get',
            'instance.resources','instance.readiness','instance.logs','instance.diagnose','instance.shell_descriptor','operation.get')
        if ($readOnly) {
            $data = $null
            switch ($command) {
                'factory.info' { $data = $caps }
                'factory.doctor' { $data = Get-EzDarkFactoryDoctorReport -Root $Root }
                'factory.portability' {
                    # A cold-copy PASS must be atomic with the same root
                    # mutation lock, not merely a preflight snapshot.
                    $coldLock = Enter-EzDarkFactoryControlLock -Root $Root
                    try {
                        Assert-EzDarkFactoryNoPendingControl -Root $Root
                        $data = Test-EzDarkFactoryPortableBundle -Root $Root
                    }
                    finally { $coldLock.Dispose() }
                }
                'instance.list' {
                    $items = @()
                    foreach ($entry in @(Get-EzDarkFactoryManagedInstanceList -Root $Root)) {
                        $items += [pscustomobject]@{ target = Get-EzDarkFactoryInstanceRef -Root $Root -Name ([string]$entry.name); status = $entry }
                    }
                    $data = [pscustomobject]@{ count = $items.Count; instances = $items; revision = $caps.revision }
                }
                'operation.get' { $data = Get-EzDarkFactoryControlOperationResult -Root $Root -OperationId ([string]$Request.arguments.operation_id) }
                default {
                    $target = Resolve-EzDarkFactoryControlTarget -Root $Root -Request $Request
                    switch ($command) {
                        'instance.get' { $data = [pscustomobject]@{ target = $target; status = Get-EzDarkFactoryManagedInstanceStatus -Root $Root -InstanceName $target.name } }
                        'instance.resources' { $data = Get-EzDarkFactoryManagedInstanceStatus -Root $Root -InstanceName $target.name }
                        'instance.readiness' { $data = Get-EzDarkFactoryControlReadiness -Root $Root -Target $target }
                        'instance.diagnose' { $data = Get-EzDarkFactoryControlDiagnosis -Root $Root -Target $target }
                        'instance.shell_descriptor' { $data = Get-EzDarkFactoryManagedShellDescriptor -Root $Root -Target $target }
                        'instance.logs' {
                            $kind = [string]$Request.arguments.kind
                            if ($kind -cnotin @('serial','qemu')) { throw 'Log kind must be serial or qemu.' }
                            $maximum = [int]$Request.arguments.maximum_characters
                            if ($maximum -lt 1 -or $maximum -gt 8192) { throw 'Log read must be bounded to 1..8192 characters.' }
                            $logs = (Get-EzDarkFactoryInstanceRuntimePaths -Root $Root -InstanceName $target.name).Logs
                            $file = Assert-EzDarkFactorySafePath -Path (Join-Path $logs ($kind + '.log')) -Description 'Bounded guest log'
                            $tail = if (Test-Path -LiteralPath $file -PathType Leaf) {
                                Read-EzDarkFactoryControlLogTail -Path $file -MaximumCharacters $maximum
                            } else {
                                [pscustomobject]@{ text = ''; truncated = $false; source_bytes = 0 }
                            }
                            $data = [pscustomobject]@{
                                target = $target; kind = $kind
                                text = [string]$tail.text; truncated = [bool]$tail.truncated
                                source_bytes = [long]$tail.source_bytes
                            }
                        }
                    }
                }
            }
            return (New-EzDarkFactoryControlResponse -Request $Request -FactoryId $factoryId -State 'completed' -Data $data)
        }

        $lock = Enter-EzDarkFactoryControlLock -Root $Root
        try {
            # Idempotency/recovery is checked BEFORE any command, including stale confirmations.
            $old = Get-EzDarkFactoryControlOperation -Root $Root -OperationId $Request.operation_id
            $digest = Get-EzDarkFactoryControlRequestDigest -Request $Request
            if ($null -ne $old) {
                if ($old.factory_id -cne $factoryId -or $old.command -cne $command -or
                    $old.request_sha256 -cne $digest -or $old.instance_id -cne $Request.instance_id -or
                    $old.instance_generation -cne $Request.instance_generation) {
                    throw 'Operation ID was previously used with a different target or factory.'
                }
                return (New-EzDarkFactoryControlResponse -Request $Request -FactoryId $factoryId -State ([string]$old.state) -Data $old.result -Code ([string]$old.refusal_code) -Message ([string]$old.refusal_message))
            }
            # Distinguish an OS-child submission from a direct synchronous
            # request. Only a worker reading the exact root-owned submitted
            # envelope can transition that mutation to durable acceptance.
            $dispatchPath = Get-EzDarkFactoryControlDispatchResultPath -Root $Root -OperationId $Request.operation_id
            if (Test-Path -LiteralPath $dispatchPath -PathType Leaf) {
                throw 'This detached operation already has a terminal precondition result; never replay its ID.'
            }
            $submissionPath = Get-EzDarkFactoryControlSubmissionPath -Root $Root -OperationId $Request.operation_id
            if ($DetachedWorker) {
                if (-not (Test-Path -LiteralPath $submissionPath -PathType Leaf)) {
                    throw 'Detached execution requires a matching root-local submission envelope.'
                }
                $submitted = Read-EzDarkFactoryJson -Path $submissionPath -SchemaVersion 1
                if ((Get-EzDarkFactoryControlRequestDigest -Request $submitted) -cne $digest -or
                    $submitted.operation_id -cne $Request.operation_id) {
                    throw 'Detached submission was modified after launch; fail closed.'
                }
            }
            elseif (Test-Path -LiteralPath $submissionPath) {
                throw 'An already-submitted worker owns this operation ID; reconcile, never replay.'
            }
            Assert-EzDarkFactoryNoPendingControl -Root $Root -IgnoreOperationId $Request.operation_id
            $currentRevision = Get-EzDarkFactoryControlRevision -Root $Root
            if ($Request.expected_revision -cne $currentRevision) { throw 'Stale factory revision. Refresh all observations and reconfirm.' }
            $target = $null
            if ($command -like 'instance.*' -and $command -cnotin @('instance.create','instance.import')) {
                $target = Resolve-EzDarkFactoryControlTarget -Root $Root -Request $Request -AllowAdoption:($command -ceq 'instance.adopt')
            }
            if ($command -ceq 'factory.rekey') {
                Assert-EzDarkFactoryColdFactory -Root $Root -IgnoreOperationId $Request.operation_id
                $operationRoot = Join-Path (Get-EzDarkFactoryPaths -Root $Root).Runtime 'control/operations'
                if (Test-Path -LiteralPath $operationRoot) {
                    $existing = @(Get-ChildItem -LiteralPath $operationRoot -Filter '*.json' -File -Force)
                    foreach ($entry in $existing) {
                        $full = Assert-EzDarkFactorySafePath -Path $entry.FullName -Description 'Prior operation reconciliation'
                        $prior = Read-EzDarkFactoryJson -Path $full -SchemaVersion 1
                        if ($prior.state -cnotin @('completed','refused')) {
                            throw 'Rekey is blocked by an accepted/ambiguous prior operation. Reconcile it before copying/forking.'
                        }
                    }
                    # Historical finalized receipts retain their original factory_id
                    # and exact source context. They must never be rewritten as
                    # results of the new fork identity.
                }
            }
            $operationPath = Get-EzDarkFactoryControlOperationPath -Root $Root -OperationId $Request.operation_id
            $operationDir = [IO.Path]::GetDirectoryName($operationPath)
            [void][IO.Directory]::CreateDirectory($operationDir)
            $receipt = [pscustomobject][ordered]@{
                schemaVersion = 1; factory_id = $factoryId; operation_id = [string]$Request.operation_id
                request_sha256 = $digest
                command = $command; instance_id = [string]$Request.instance_id
                instance_generation = [string]$Request.instance_generation
                expected_revision = [string]$Request.expected_revision
                state = 'accepted'; created_at = [DateTime]::UtcNow.ToString('o')
                progress = [pscustomobject]@{ stage = 'accepted'; terminal = $false }
                finished_at = $null; result = $null; refusal_code = ''; refusal_message = ''
            }
            Write-EzDarkFactoryJson -Path $operationPath -Value $receipt -SchemaVersion 1
            try {
                $a = $Request.arguments
                $data = $null
                $name = ''
                if ($null -ne $target) { $name = [string]$target.name }
                elseif ($command -in @('instance.create','instance.import')) { $name = [string]$a.name }
                switch ($command) {
                    'factory.rekey' {
                        $preimage = Join-Path (Get-EzDarkFactoryPaths -Root $Root).Runtime ('control/rekey-' + $Request.operation_id + '.json')
                        Write-EzDarkFactoryJson -Path $preimage -Value $identity -SchemaVersion 1
                        $replacement = [pscustomobject][ordered]@{
                            schemaVersion = 1; factory_id = ('fct_' + [guid]::NewGuid().ToString('N'))
                            api_major = 1; api_minor = 0; created_at = [DateTime]::UtcNow.ToString('o')
                        }
                        Write-EzDarkFactoryJson -Path (Get-EzDarkFactoryIdentityPath -Root $Root) -Value $replacement -SchemaVersion 1
                        $data = [pscustomobject]@{ previous_factory_id = $factoryId; factory_id = $replacement.factory_id; preimage = 'control/rekey-' + $Request.operation_id + '.json' }
                    }
                    'instance.adopt' { Assert-EzDarkFactoryColdFactory -Root $Root -IgnoreOperationId $Request.operation_id; $data = New-EzDarkFactoryInstanceRef -Root $Root -Name $name }
                    'instance.create' {
                        Assert-EzDarkFactoryStorageInstanceName -Name $name
                        $data = New-EzDarkFactoryManagedInstance -Root $Root -InstanceName $name -Profile ([string]$a.profile) -BaseId ([string]$a.base_id)
                        $ref = New-EzDarkFactoryInstanceRef -Root $Root -Name $name
                        $data = [pscustomobject]@{ instance = $data; target = $ref }
                    }
                    'instance.import' {
                        Assert-EzDarkFactoryStorageInstanceName -Name $name
                        $data = Import-EzDarkFactoryManagedInstance -Root $Root -InstanceName $name -ImagePath ([string]$a.image_path) -ManifestPath ([string]$a.manifest_path) -Profile ([string]$a.profile)
                        $ref = New-EzDarkFactoryInstanceRef -Root $Root -Name $name
                        $data = [pscustomobject]@{ instance = $data; target = $ref }
                    }
                    'instance.start' {
                        $cfg = Get-EzDarkFactoryConfiguration -Root $Root
                        $data = Start-EzDarkFactoryReadyInstance -Root $Root -InstanceName $name -Accelerator whpx -ReadyTimeoutSeconds ([int]$cfg.timeouts.processSeconds)
                    }
                    'instance.stop' {
                        $cfg = Get-EzDarkFactoryConfiguration -Root $Root
                        $data = Stop-EzDarkFactoryInstance -Root $Root -InstanceName $name -ShutdownTimeoutSeconds ([int]$cfg.timeouts.processSeconds)
                    }
                    'instance.reset' { $data = Reset-EzDarkFactoryManagedInstance -Root $Root -InstanceName $name }
                    'instance.clone' {
                        $data = Copy-EzDarkFactoryManagedInstance -Root $Root -SourceInstanceName $name -DestinationInstanceName ([string]$a.destination_name) -Mode ([string]$a.mode)
                        $ref = New-EzDarkFactoryInstanceRef -Root $Root -Name ([string]$a.destination_name)
                        $data = [pscustomobject]@{ instance = $data; target = $ref }
                    }
                    'instance.export' { $data = Export-EzDarkFactoryManagedInstance -Root $Root -InstanceName $name -DestinationDirectory ([string]$a.destination_directory) }
                    'instance.exec' {
                        $cfg = Get-EzDarkFactoryConfiguration -Root $Root
                        if ($a.argv -isnot [array] -or @($a.argv).Count -lt 1 -or @($a.argv).Count -gt 64) { throw 'Exec requires 1..64 typed argv strings.' }
                        $executed = Invoke-EzDarkFactoryExec -Root $Root -InstanceName $name -Command ([string[]]$a.argv) -TimeoutSeconds ([int]$cfg.timeouts.processSeconds)
                        # Guest output is untrusted and must not turn a root-local
                        # operation record into an unbounded terminal transcript.
                        $data = [pscustomobject]@{
                            name = $name; exitCode = [int]$executed.exitCode
                            stdout = Protect-EzDarkFactoryDiagnosticText -Text ([string]$executed.stdout) -MaximumCharacters 8192
                            stderr = Protect-EzDarkFactoryDiagnosticText -Text ([string]$executed.stderr) -MaximumCharacters 8192
                        }
                    }
                    'instance.copy_to' {
                        $cfg = Get-EzDarkFactoryConfiguration -Root $Root
                        $data = Invoke-EzDarkFactoryCopyToGuest -Root $Root -InstanceName $name -HostPath ([string]$a.host_path) -GuestPath ([string]$a.guest_path) -TimeoutSeconds ([int]$cfg.timeouts.processSeconds)
                    }
                    'instance.copy_from' {
                        $cfg = Get-EzDarkFactoryConfiguration -Root $Root
                        $data = Invoke-EzDarkFactoryCopyFromGuest -Root $Root -InstanceName $name -GuestPath ([string]$a.guest_path) -HostPath ([string]$a.host_path) -TimeoutSeconds ([int]$cfg.timeouts.processSeconds)
                    }
                    default { throw 'Unknown typed mutation.' }
                }
                $receipt.state = 'completed'
                $receipt.result = $data
            }
            catch {
                $receipt.state = 'refused'
                $receipt.refusal_code = 'operation_failed'
                $receipt.refusal_message = Protect-EzDarkFactoryDiagnosticText -Text $_.Exception.Message
            }
            $receipt.finished_at = [DateTime]::UtcNow.ToString('o')
            $receipt.progress = [pscustomobject]@{ stage = $receipt.state; terminal = $true }
            # A failed journal publication leaves the accepted record ambiguous; retry must not replay.
            Write-EzDarkFactoryJson -Path $operationPath -Value $receipt -SchemaVersion 1
            return (New-EzDarkFactoryControlResponse -Request $Request -FactoryId $factoryId -State $receipt.state -Data $receipt.result -Code $receipt.refusal_code -Message $receipt.refusal_message)
        }
        finally { $lock.Dispose() }
    }
    catch {
        return (New-EzDarkFactoryControlResponse -Request $Request -FactoryId $factoryId -State 'refused' -Code 'precondition_failed' -Message $_.Exception.Message)
    }
}
