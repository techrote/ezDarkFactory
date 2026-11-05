#requires -Version 5.1
# EDF-006: SOURCE/FAST-CI read-only bridge to the accepted EDF-005 manager API.
# Never imports scripts from a discovered/candidate factory root.
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Workspace)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    $trustedModule = Join-Path (Join-Path $PSScriptRoot '..') 'src/EzDarkFactory/Edf005.psm1'
    Import-Module -Name $trustedModule -Force -ErrorAction Stop
    $registry = Get-EzDarkFactoryManagerRegistry -Workspace $Workspace
    if (@($registry.roots).Count -gt 128) { throw 'Observation budget exceeded.' }
    $rows = @(Get-EzDarkFactoryManagerObservations -Workspace $Workspace)
    if ($rows.Count -gt 128) { throw 'Observation budget exceeded.' }
    $snapshot = [pscustomobject][ordered]@{
        schemaVersion = 1
        kind = 'edf005-static-roots'
        records = @($rows)
    }
    $json = ConvertTo-Json -InputObject $snapshot -Depth 16 -Compress
    if ([Text.Encoding]::UTF8.GetByteCount($json) -gt 262144) {
        throw 'Observation response budget exceeded.'
    }
    [Console]::Out.WriteLine($json)
    exit 0
}
catch {
    # No raw workspace path, guest data, exception string or credentials on stderr.
    [Console]::Error.WriteLine('EDF006_STATIC_READ_REFUSED')
    exit 2
}
