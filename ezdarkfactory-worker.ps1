#requires -Version 5.1
# A self-owned, root-local operation worker. No manager service or TUI required.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$OperationId,
    [string]$ManagerWorkspace = '',
    [ValidateRange(1,8)][int]$MaxConcurrentRoots = 2
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    Import-Module (Join-Path $PSScriptRoot 'src/EzDarkFactory/Edf005.psm1') -Force -ErrorAction Stop
    Invoke-EzDarkFactoryDetachedControlWorker -Root $PSScriptRoot -OperationId $OperationId -ManagerWorkspace $ManagerWorkspace -MaxConcurrentRoots $MaxConcurrentRoots
    exit 0
}
catch {
    # No raw exceptions or guest output may escape through an inherited console.
    # Any existing accepted journal/request is preserved, not replayed.
    exit 2
}
