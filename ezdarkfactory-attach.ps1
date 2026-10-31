#requires -Version 5.1
# Explicit, identity-bound managed SSH attach. Never infer a target from its name.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^fct_[a-f0-9]{32}$')][string]$FactoryId,
    [Parameter(Mandatory)][ValidatePattern('^ins_[a-f0-9]{32}$')][string]$InstanceId,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$InstanceGeneration,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedRevision,
    [switch]$ProbeOnly
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    Import-Module (Join-Path $PSScriptRoot 'src/EzDarkFactory/Edf005.psm1') -Force -ErrorAction Stop
    $module = Get-Module Edf005
    $root = $PSScriptRoot
    $target = & $module {
        param($Root, $FactoryId, $InstanceId, $Generation, $Revision)
        $identity = Get-EzDarkFactoryIdentity -Root $Root
        if ($identity.factory_id -cne $FactoryId) { throw 'Managed attach refused stale factory identity.' }
        if ((Get-EzDarkFactoryControlRevision -Root $Root) -cne $Revision) {
            throw 'Managed attach refused stale control revision; refresh descriptor.'
        }
        $request = [pscustomobject]@{
            instance_id = $InstanceId; instance_generation = $Generation
            arguments = [pscustomobject]@{ name = '' }
        }
        Resolve-EzDarkFactoryControlTarget -Root $Root -Request $request
    } $root $FactoryId $InstanceId $InstanceGeneration $ExpectedRevision

    if ($ProbeOnly) {
        [Console]::Out.WriteLine((ConvertTo-Json -InputObject ([pscustomobject][ordered]@{
            schemaVersion = 1; factory_id = $FactoryId; instance_id = $InstanceId
            instance_generation = $InstanceGeneration; matched = $true; launched = $false
        }) -Compress))
        exit 0
    }
    # The accepted SSH implementation validates ready state, managed host-key
    # trust and controller key identity. No generated command bypasses it.
    $exitCode = & $module { param($root,$name) Invoke-EzDarkFactorySsh -Root $root -InstanceName $name } $root $target.name
    exit ([int]$exitCode)
}
catch {
    [Console]::Error.WriteLine('Managed SSH attach refused: identity/revision/readiness or managed trust check failed. Refresh the descriptor; no fallback to untrusted SSH.')
    exit 2
}
