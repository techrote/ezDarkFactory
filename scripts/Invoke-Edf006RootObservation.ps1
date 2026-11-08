#requires -Version 5.1
# EDF-006 trusted, read-only per-enrollment identity observation.
# One candidate root is inspected per bounded child; no candidate code executes.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Workspace,
    [Parameter(Mandatory = $true)][string]$EnrollmentId
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    if ($EnrollmentId -cnotmatch '^enr_[a-f0-9]{32}$') {
        throw 'Invalid enrollment.'
    }
    $trustedModule = Join-Path (Join-Path $PSScriptRoot '..') 'src/EzDarkFactory/Edf005.psm1'
    Import-Module -Name $trustedModule -Force -ErrorAction Stop
    $registry = Get-EzDarkFactoryManagerRegistry -Workspace $Workspace
    $entries = @($registry.roots)
    if ($entries.Count -gt 128) { throw 'Registry observation budget exceeded.' }
    $selected = @($entries | Where-Object { $_.enrollment_id -ceq $EnrollmentId })
    if ($selected.Count -ne 1 -or -not $selected[0].execution_authorized) {
        throw 'Enrollment absent, ambiguous, or unauthorized.'
    }
    $entry = $selected[0]
    # Registry metadata may be inspected for obvious duplicate identity, but
    # NO other candidate root is probed: a hung root must not hold this child.
    $duplicate = @($entries | Where-Object {
        $_.enrollment_id -cne $EnrollmentId -and
        $_.last_factory_id -ceq $entry.last_factory_id
    })
    $candidate = Get-EzDarkFactoryCandidate -Root $entry.canonical_path
    $state = [string]$candidate.state
    $reason = [string]$candidate.reason
    if ($state -ceq 'current' -and $candidate.factory_id -cne $entry.last_factory_id) {
        $state = 'conflict'
        $reason = 'Observed identity differs from the enrolled identity.'
    }
    if ($duplicate.Count -gt 0) {
        $state = 'conflict'
        $reason = 'Duplicate registered factory identity; independent fleet verification required.'
    }
    $record = [pscustomobject][ordered]@{
        schemaVersion = 1
        enrollment_id = $entry.enrollment_id
        alias = $entry.alias
        canonical_path = $entry.canonical_path
        factory_id = $entry.last_factory_id
        observed_factory_id = $candidate.factory_id
        api = $candidate.api
        state = $state
        inventory_state = 'unknown'
        last_known = [pscustomobject]@{
            factory_id = $entry.last_factory_id
            api_major = $entry.api_major
            api_minor = $entry.api_minor
            verified_at = $entry.last_verified_at
            freshness = 'stale'
        }
        observed_at = [DateTime]::UtcNow.ToString('o')
        reason = $reason
    }
    $snapshot = [pscustomobject][ordered]@{
        schemaVersion = 1
        kind = 'edf005-static-roots'
        records = @($record)
    }
    $json = ConvertTo-Json -InputObject $snapshot -Depth 16 -Compress
    if ([Text.Encoding]::UTF8.GetByteCount($json) -gt 262144) {
        throw 'Per-root static response budget exceeded.'
    }
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    [Console]::Out.WriteLine($json)
    exit 0
}
catch {
    # No root path, raw exception, guest output or credentials on stderr.
    [Console]::Error.WriteLine('EDF006_ROOT_STATIC_READ_REFUSED')
    exit 2
}
