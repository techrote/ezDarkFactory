# EDF-005 portable, non-UI manager. Candidate discovery reads data only; it never dot-sources candidate code.
function Get-EzDarkFactoryManagerRegistryPath {
    param([Parameter(Mandatory)][string]$Workspace)
    $home = Assert-EzDarkFactorySafePath -Path $Workspace -Description 'Portable manager workspace'
    return (Join-Path $home 'registry.json')
}

function Get-EzDarkFactoryManagerRegistry {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Workspace)
    $path = Get-EzDarkFactoryManagerRegistryPath -Workspace $Workspace
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'Portable manager workspace is not initialized. Create it explicitly, or use a factory directly by path.'
    }
    $registry = Read-EzDarkFactoryJson -Path $path -SchemaVersion 1
    if ($registry.roots -isnot [array] -or $registry.schemaVersion -ne 1) {
        throw 'Unsupported manager registry layout; manual recovery required.'
    }
    foreach ($entry in @($registry.roots)) {
        if ($entry.enrollment_id -cnotmatch '^enr_[a-f0-9]{32}$' -or
            $entry.canonical_path -isnot [string] -or
            $entry.last_factory_id -cnotmatch '^fct_[a-f0-9]{32}$' -or
            $entry.execution_authorized -isnot [bool]) {
            throw 'Manager registration is incompatible or malformed; no repair-on-read is permitted.'
        }
        $null = Assert-EzDarkFactorySafePath -Path $entry.canonical_path -Description 'Registered root'
    }
    return $registry
}

function Initialize-EzDarkFactoryManagerWorkspace {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Workspace)
    $path = Get-EzDarkFactoryManagerRegistryPath -Workspace $Workspace
    $root = [IO.Path]::GetDirectoryName($path)
    [void][IO.Directory]::CreateDirectory($root)
    $lock = Enter-EzDarkFactorySecurityLock -Path (Join-Path $root 'manager-writer.lock')
    try {
        if (Test-Path -LiteralPath $path) { return (Get-EzDarkFactoryManagerRegistry -Workspace $Workspace) }
        $registry = [pscustomobject][ordered]@{ schemaVersion = 1; roots = @() }
        Write-EzDarkFactoryJson -Path $path -Value $registry -SchemaVersion 1
        return $registry
    }
    finally { $lock.Dispose() }
}

function Get-EzDarkFactoryCandidate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)
    $path = ''
    try {
        $path = Assert-EzDarkFactorySafePath -Path $Root -Description 'Candidate root'
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            return [pscustomobject]@{ path = $path; state = 'unreachable'; factory_id = $null; api = $null; reason = 'Directory unavailable.' }
        }
        $null = Get-EzDarkFactoryRoot -Path $path
        # Only the checked-out manager code reads static JSON here. No script, executable,
        # profile, module, hook or binary from the candidate root is invoked.
        $identity = Get-EzDarkFactoryIdentity -Root $path
        return [pscustomobject]@{
            path = $path; state = 'current'; factory_id = [string]$identity.factory_id
            api = [pscustomobject]@{ major = [int]$identity.api_major; minor = [int]$identity.api_minor }
            reason = 'Compatible static identity; no candidate code executed.'
        }
    }
    catch {
        return [pscustomobject]@{
            path = $path; state = 'incompatible'; factory_id = $null; api = $null
            reason = Protect-EzDarkFactoryDiagnosticText -Text $_.Exception.Message
        }
    }
}

function Register-EzDarkFactoryManagerRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Workspace,
          [Parameter(Mandatory)][string]$Root,
          [Parameter(Mandatory)][string]$Alias,
          [switch]$AuthorizeLocalExecution)
    if (-not $AuthorizeLocalExecution) { throw 'First enrollment requires explicit authorization to execute local root control code as the current user.' }
    if ([string]::IsNullOrWhiteSpace($Alias) -or $Alias.Length -gt 128 -or $Alias -match '[\x00-\x1f\x7f]') {
        throw 'Factory alias must be 1..128 printable characters.'
    }
    $candidate = Get-EzDarkFactoryCandidate -Root $Root
    if ($candidate.state -cne 'current') { throw "Candidate cannot be enrolled: $($candidate.reason)" }
    $path = Get-EzDarkFactoryManagerRegistryPath -Workspace $Workspace
    $lock = Enter-EzDarkFactorySecurityLock -Path (Join-Path ([IO.Path]::GetDirectoryName($path)) 'manager-writer.lock')
    try {
        $registry = Get-EzDarkFactoryManagerRegistry -Workspace $Workspace
        $comparison = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
            [StringComparison]::OrdinalIgnoreCase
        } else { [StringComparison]::Ordinal }
        foreach ($entry in @($registry.roots)) {
            if ([string]::Equals([string]$entry.canonical_path, [string]$candidate.path, $comparison)) {
                throw 'Canonical root path is already registered; aliases cannot double-enroll the same directory.'
            }
        }
        $entry = [pscustomobject][ordered]@{
            enrollment_id = ('enr_' + [guid]::NewGuid().ToString('N'))
            alias = $Alias; canonical_path = $candidate.path
            last_factory_id = $candidate.factory_id
            api_major = $candidate.api.major; api_minor = $candidate.api.minor
            execution_authorized = $true
            enrolled_at = [DateTime]::UtcNow.ToString('o')
            last_verified_at = [DateTime]::UtcNow.ToString('o')
        }
        $registry.roots = @($registry.roots) + @($entry)
        Write-EzDarkFactoryJson -Path $path -Value $registry -SchemaVersion 1
        return $entry
    }
    finally { $lock.Dispose() }
}

function Unregister-EzDarkFactoryManagerRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Workspace,
          [Parameter(Mandatory)][string]$EnrollmentId)
    if ($EnrollmentId -cnotmatch '^enr_[a-f0-9]{32}$') { throw 'Enrollment ID is invalid.' }
    $path = Get-EzDarkFactoryManagerRegistryPath -Workspace $Workspace
    $lock = Enter-EzDarkFactorySecurityLock -Path (Join-Path ([IO.Path]::GetDirectoryName($path)) 'manager-writer.lock')
    try {
        $registry = Get-EzDarkFactoryManagerRegistry -Workspace $Workspace
        $matches = @($registry.roots | Where-Object { $_.enrollment_id -ceq $EnrollmentId })
        if ($matches.Count -ne 1) { throw 'Enrollment is absent or ambiguous.' }
        $registry.roots = @($registry.roots | Where-Object { $_.enrollment_id -cne $EnrollmentId })
        Write-EzDarkFactoryJson -Path $path -Value $registry -SchemaVersion 1
        # Never delete, rekey, or execute the unregistered factory.
        return [pscustomobject]@{ enrollment_id = $EnrollmentId; removed = $true; factory_deleted = $false }
    }
    finally { $lock.Dispose() }
}

function Get-EzDarkFactoryManagerObservations {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Workspace)
    $registry = Get-EzDarkFactoryManagerRegistry -Workspace $Workspace
    $records = @()
    foreach ($entry in @($registry.roots)) {
        $candidate = Get-EzDarkFactoryCandidate -Root $entry.canonical_path
        $state = [string]$candidate.state
        if ($state -ceq 'current' -and $candidate.factory_id -cne $entry.last_factory_id) { $state = 'conflict' }
        $records += [pscustomobject][ordered]@{
            schemaVersion = 1; enrollment_id = $entry.enrollment_id; alias = $entry.alias
            canonical_path = $entry.canonical_path; factory_id = $entry.last_factory_id
            observed_factory_id = $candidate.factory_id; api = $candidate.api
            state = $state; inventory_state = 'unknown'
            last_known = [pscustomobject]@{
                factory_id = $entry.last_factory_id; api_major = $entry.api_major
                api_minor = $entry.api_minor; verified_at = $entry.last_verified_at
                freshness = 'stale'
            }
            observed_at = [DateTime]::UtcNow.ToString('o'); reason = $candidate.reason
        }
    }
    foreach ($record in @($records)) {
        if ($record.state -ceq 'current') {
            $same = @($records | Where-Object {
                $_.observed_factory_id -ceq $record.observed_factory_id -and
                $_.observed_factory_id -ne $null -and
                $_.state -in @('current','conflict')
            })
            if ($same.Count -gt 1) { $record.state = 'conflict'; $record.reason = 'Two reachable enrolled roots share a factory identity; all mutations are held.' }
        }
    }
    return @($records)
}

function Enter-EzDarkFactoryManagerBudgetSlot {
    param([string]$Workspace, [ValidateRange(1,8)][int]$Limit = 2,
        [ValidateRange(1,1800)][int]$TimeoutSeconds = 5)
    $root = Assert-EzDarkFactorySafePath -Path $Workspace -Description 'Manager workspace'
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        for ($i = 0; $i -lt $Limit; $i++) {
            $file = Join-Path $root ('operation-slot-' + $i + '.lock')
            $null = Assert-EzDarkFactorySafePath -Path $file -Description 'Manager host budget'
            try {
                return [IO.File]::Open($file, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            } catch [IO.IOException] { }
        }
        Start-Sleep -Milliseconds 50
    }
    throw 'Manager host operation budget exhausted; no operation started.'
}

function Invoke-EzDarkFactoryManagerControl {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Workspace,
          [Parameter(Mandatory)][string]$EnrollmentId,
          [Parameter(Mandatory)][object]$Request,
          [ValidateRange(1,8)][int]$MaxConcurrentRoots = 2)
    $observations = @(Get-EzDarkFactoryManagerObservations -Workspace $Workspace)
    $matches = @($observations | Where-Object { $_.enrollment_id -ceq $EnrollmentId })
    if ($matches.Count -ne 1) { throw 'Enrollment ID not found.' }
    $record = $matches[0]
    if ($record.state -cne 'current') { throw "Manager refuses $($record.state) root; re-enroll or explicitly rekey/correct registration first." }
    if ($Request.factory_id -cne $record.factory_id) { throw 'Manager request factory identity differs from enrolled identity.' }
    $registry = Get-EzDarkFactoryManagerRegistry -Workspace $Workspace
    $entry = @($registry.roots | Where-Object { $_.enrollment_id -ceq $EnrollmentId })[0]
    if (-not $entry.execution_authorized) { throw 'Root execution was not explicitly authorized.' }
    # This in-process adapter uses the accepted manager module, never candidate
    # code. Future adapters may start the enrolled root script only after enrollment.
    # All mutations are handed to a factory-root child process. The manager
    # neither owns the operation's lifespan nor treats a process launch as a
    # committed operation. The child holds host budget for actual execution.
    $fleet = @(Get-EzDarkFactoryManagerObservations -Workspace $Workspace)
    $freshRows = @($fleet | Where-Object { $_.enrollment_id -ceq $EnrollmentId })
    if ($freshRows.Count -ne 1 -or $freshRows[0].state -cne 'current' -or
        $freshRows[0].observed_factory_id -cne $entry.last_factory_id) {
        throw 'Fleet identity/collision state changed before dispatch; refresh.'
    }
    $root = $entry.canonical_path
    if ($Request.command -in @('factory.info','factory.doctor','factory.portability',
        'instance.list','instance.get','instance.resources','instance.readiness',
        'instance.logs','instance.diagnose','instance.shell_descriptor','operation.get')) {
        return (Invoke-EzDarkFactoryControl -Root $root -Request $Request)
    }
    return (Start-EzDarkFactoryDetachedControlOperation -Root $root -Request $Request -ManagerWorkspace $Workspace -MaxConcurrentRoots $MaxConcurrentRoots)
}
