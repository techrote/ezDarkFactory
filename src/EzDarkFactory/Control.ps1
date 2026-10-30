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

function Assert-EzDarkFactoryColdFactory {
    param([string]$Root = $script:EzDarkFactoryDefaultRoot)
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

function Get-EzDarkFactoryControlOperation {
    [CmdletBinding()]
    param([string]$Root = $script:EzDarkFactoryDefaultRoot, [Parameter(Mandatory)][string]$OperationId)
    $path = Get-EzDarkFactoryControlOperationPath -Root $Root -OperationId $OperationId
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $record = Read-EzDarkFactoryJson -Path $path -SchemaVersion 1
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

function Invoke-EzDarkFactoryControl {
    [CmdletBinding()]
    param([string]$Root = $script:EzDarkFactoryDefaultRoot, [Parameter(Mandatory)][object]$Request)
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
                'factory.portability' { $data = Test-EzDarkFactoryPortableBundle -Root $Root }
                'instance.list' {
                    $items = @()
                    foreach ($entry in @(Get-EzDarkFactoryManagedInstanceList -Root $Root)) {
                        $items += [pscustomobject]@{ target = Get-EzDarkFactoryInstanceRef -Root $Root -Name ([string]$entry.name); status = $entry }
                    }
                    $data = [pscustomobject]@{ count = $items.Count; instances = $items; revision = $caps.revision }
                }
                'operation.get' { $data = Get-EzDarkFactoryControlOperation -Root $Root -OperationId ([string]$Request.arguments.operation_id) }
                default {
                    $target = Resolve-EzDarkFactoryControlTarget -Root $Root -Request $Request
                    switch ($command) {
                        'instance.get' { $data = [pscustomobject]@{ target = $target; status = Get-EzDarkFactoryManagedInstanceStatus -Root $Root -InstanceName $target.name } }
                        'instance.resources' { $data = Get-EzDarkFactoryManagedInstanceStatus -Root $Root -InstanceName $target.name }
                        'instance.readiness' { $data = Get-EzDarkFactoryManagedInstanceStatus -Root $Root -InstanceName $target.name }
                        'instance.diagnose' { $data = Get-EzDarkFactoryInstanceDiagnosis -Root $Root -InstanceName $target.name }
                        'instance.shell_descriptor' {
                            $status = Get-EzDarkFactoryManagedInstanceStatus -Root $Root -InstanceName $target.name
                            $data = [pscustomobject]@{ kind = 'managed-ssh'; target = $target; state = $status.state
                                invocation = [pscustomobject]@{ command = 'ssh'; instance_id = $target.instance_id; instance_generation = $target.instance_generation } }
                        }
                        'instance.logs' {
                            $kind = [string]$Request.arguments.kind
                            if ($kind -cnotin @('serial','qemu')) { throw 'Log kind must be serial or qemu.' }
                            $maximum = [int]$Request.arguments.maximum_characters
                            if ($maximum -lt 1 -or $maximum -gt 8192) { throw 'Log read must be bounded to 1..8192 characters.' }
                            $logs = (Get-EzDarkFactoryInstanceRuntimePaths -Root $Root -InstanceName $target.name).Logs
                            $file = Assert-EzDarkFactorySafePath -Path (Join-Path $logs ($kind + '.log')) -Description 'Bounded guest log'
                            $value = if (Test-Path -LiteralPath $file -PathType Leaf) { Read-EzDarkFactoryBoundedText -Path $file } else { '' }
                            if ($value.Length -gt $maximum) { $value = $value.Substring($value.Length - $maximum) }
                            $data = [pscustomobject]@{ target = $target; kind = $kind; text = Protect-EzDarkFactoryDiagnosticText -Text $value -MaximumCharacters 8192 }
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
            $currentRevision = Get-EzDarkFactoryControlRevision -Root $Root
            if ($Request.expected_revision -cne $currentRevision) { throw 'Stale factory revision. Refresh all observations and reconfirm.' }
            $target = $null
            if ($command -like 'instance.*' -and $command -cnotin @('instance.create','instance.import')) {
                $target = Resolve-EzDarkFactoryControlTarget -Root $Root -Request $Request -AllowAdoption:($command -ceq 'instance.adopt')
            }
            if ($command -ceq 'factory.rekey') {
                Assert-EzDarkFactoryColdFactory -Root $Root
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
                    'instance.adopt' { Assert-EzDarkFactoryColdFactory -Root $Root; $data = New-EzDarkFactoryInstanceRef -Root $Root -Name $name }
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
                        $data = Invoke-EzDarkFactoryExec -Root $Root -InstanceName $name -Command ([string[]]$a.argv) -TimeoutSeconds ([int]$cfg.timeouts.processSeconds)
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
