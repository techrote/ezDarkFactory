#requires -Version 5.1
# EDF-006 trusted metadata-only read; never probe registered candidate roots.
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Workspace)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    $trustedModule = Join-Path (Join-Path $PSScriptRoot '..') 'src/EzDarkFactory/Edf005.psm1'
    Import-Module -Name $trustedModule -Force -ErrorAction Stop
    $registry = Get-EzDarkFactoryManagerRegistryMetadata -Workspace $Workspace
    $entries = @($registry.roots)
    $rows = @()
    foreach ($entry in $entries) {
        # A metadata duplicate holds both enrollments even before probing.
        $duplicates = @($entries | Where-Object {
            $_.last_factory_id -ceq $entry.last_factory_id
        }).Count -gt 1
        $state = if ($duplicates) { 'conflict' }
                 elseif (-not $entry.execution_authorized) { 'incompatible' }
                 else { 'unknown' }
        $rows += [pscustomobject][ordered]@{
            schemaVersion = 1
            enrollment_id = $entry.enrollment_id
            alias = $entry.alias
            canonical_path = $entry.canonical_path
            factory_id = $entry.last_factory_id
            observed_factory_id = $null
            api = $null
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
            reason = 'Registry-only identity; per-root verification pending.'
        }
    }
    $snapshot = [pscustomobject][ordered]@{
        schemaVersion = 1
        kind = 'edf005-static-roots'
        records = @($rows)
    }
    $json = ConvertTo-Json -InputObject $snapshot -Depth 16 -Compress
    if ([Text.Encoding]::UTF8.GetByteCount($json) -gt 262144) {
        throw 'Observation response budget exceeded.'
    }
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    [Console]::Out.WriteLine($json)
    exit 0
}
catch {
    [Console]::Error.WriteLine('EDF006_STATIC_READ_REFUSED')
    exit 2
}
