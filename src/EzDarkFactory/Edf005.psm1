#requires -Version 5.1
Set-StrictMode -Version 2.0

$script:EzDarkFactoryDefaultRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$script:EzDarkFactoryVersion = (Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'EzDarkFactory.psd1')).PrivateData.EzDarkFactoryVersion

# An explicit list prevents an unexpected file in this directory being executed on import.
foreach ($source in @('Security.ps1', 'Paths.ps1', 'Json.ps1', 'Configuration.ps1', 'Process.ps1', 'Download.ps1', 'QemuIntegrity.ps1', 'Qemu.ps1', 'Doctor.ps1', 'SourceImage.ps1', 'SeedServer.ps1', 'BaseRecipe.ps1', 'BaseBuilder.ps1', 'Storage.ps1', 'Snapshots.ps1', 'Runtime.ps1', 'Registry.ps1', 'Profiles.ps1', 'Ssh.ps1', 'Keys.ps1', 'Portability.ps1', 'Recovery.ps1', 'Cli.ps1')) {
    . (Join-Path $PSScriptRoot $source)
}

# EDF-005 composed adapter: inherited sources retain their original Git blobs.
. (Join-Path $PSScriptRoot 'Control.ps1')
. (Join-Path $PSScriptRoot 'Manager.ps1')

Export-ModuleMember -Function @(
    'Get-EzDarkFactoryIdentity', 'Initialize-EzDarkFactoryIdentity', 'Get-EzDarkFactoryControlRevision',
    'Get-EzDarkFactoryControlCapabilities', 'Get-EzDarkFactoryInstanceRef', 'Get-EzDarkFactoryControlOperation',
    'Invoke-EzDarkFactoryControl', 'Initialize-EzDarkFactoryManagerWorkspace', 'Get-EzDarkFactoryManagerRegistry',
    'Get-EzDarkFactoryCandidate', 'Register-EzDarkFactoryManagerRoot', 'Unregister-EzDarkFactoryManagerRoot',
    'Get-EzDarkFactoryManagerObservations', 'Invoke-EzDarkFactoryManagerControl',
    'Start-EzDarkFactoryDetachedControlOperation', 'Get-EzDarkFactoryControlOperationResult',
    'Invoke-EzDarkFactoryDetachedControlWorker', 'Get-EzDarkFactoryManagedShellDescriptor'
)
