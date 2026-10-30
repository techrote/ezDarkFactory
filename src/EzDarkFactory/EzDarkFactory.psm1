#requires -Version 5.1
Set-StrictMode -Version 2.0

$script:EzDarkFactoryDefaultRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$script:EzDarkFactoryVersion = (Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'EzDarkFactory.psd1')).PrivateData.EzDarkFactoryVersion

# An explicit list prevents an unexpected file in this directory being executed on import.
foreach ($source in @('Security.ps1', 'Paths.ps1', 'Json.ps1', 'Configuration.ps1', 'Process.ps1', 'Download.ps1', 'QemuIntegrity.ps1', 'Qemu.ps1', 'Doctor.ps1', 'SourceImage.ps1', 'SeedServer.ps1', 'BaseRecipe.ps1', 'BaseBuilder.ps1', 'Storage.ps1', 'Snapshots.ps1', 'Runtime.ps1', 'Registry.ps1', 'Profiles.ps1', 'Ssh.ps1', 'Keys.ps1', 'Portability.ps1', 'Recovery.ps1', 'Cli.ps1', 'Control.ps1', 'Manager.ps1')) {
    . (Join-Path $PSScriptRoot $source)
}

Export-ModuleMember -Function @(
    'Get-EzDarkFactoryVersion', 'Get-EzDarkFactoryRoot', 'Get-EzDarkFactoryPaths', 'Get-EzDarkFactoryConfiguration',
    'Read-EzDarkFactoryJson', 'Write-EzDarkFactoryJson', 'Invoke-EzDarkFactoryProcess',
    'Get-EzDarkFactoryFileDigest', 'Get-EzDarkFactoryVerifiedArtifact',
    'Get-EzDarkFactoryQemuManifest', 'Install-EzDarkFactoryQemuRuntime', 'Get-EzDarkFactoryManagedQemuStatus', 'Get-EzDarkFactoryQemuToolPath',
    'Get-EzDarkFactoryDoctorReport', 'Get-EzDarkFactoryInstanceDiagnosis',
    'Get-EzDarkFactorySourceImageManifest', 'Invoke-EzDarkFactorySourceImageAcquire', 'Get-EzDarkFactoryVerifiedSourceImage',
    'Start-EzDarkFactorySeedServer', 'Invoke-EzDarkFactorySeedServerPending', 'Stop-EzDarkFactorySeedServer',
    'Get-EzDarkFactoryBaseRecipe', 'Get-EzDarkFactoryBaseProvisioningDigest', 'New-EzDarkFactoryBaseSeedData', 'New-EzDarkFactoryBaseQemuArguments',
    'Invoke-EzDarkFactoryBaseBuild', 'Test-EzDarkFactoryPreparedBase',
    'Get-EzDarkFactoryInstanceStoragePaths', 'Get-EzDarkFactoryStorageRelativePath', 'New-EzDarkFactoryStorageLifecycleGuard',
    'Get-EzDarkFactoryStorageImageInfo', 'Get-EzDarkFactoryStorageBackingChain', 'Test-EzDarkFactoryInstanceOverlay', 'Test-EzDarkFactoryInstanceStorage',
    'New-EzDarkFactoryInstanceOverlay', 'Test-EzDarkFactoryStoppedImageIntegrity', 'Reset-EzDarkFactoryInstanceOverlayStorage',
    'New-EzDarkFactoryDerivedBase', 'Export-EzDarkFactoryInstanceStorage', 'Import-EzDarkFactoryStandaloneBase',
    'Test-EzDarkFactoryQcow2Header', 'Assert-EzDarkFactorySnapshotBaseManifest', 'Assert-EzDarkFactoryExportManifest',
    'Get-EzDarkFactoryInstanceRuntimePaths', 'New-EzDarkFactoryInstanceIntent', 'Get-EzDarkFactoryInstanceIntent',
    'Resolve-EzDarkFactoryInstanceResources', 'Get-EzDarkFactoryPreparedBaseSelection', 'Get-EzDarkFactoryInstanceRegistry',
    'Get-EzDarkFactoryAllocatedSshPorts', 'Assert-EzDarkFactoryInstanceSshPortReservation', 'New-EzDarkFactoryManagedInstance',
    'Get-EzDarkFactoryManagedInstanceStatus', 'Get-EzDarkFactoryManagedInstanceList',
    'Get-EzDarkFactoryArgumentFingerprint', 'Get-EzDarkFactoryRuntimeFirmwarePaths', 'New-EzDarkFactoryRuntimeQemuArguments',
    'Get-EzDarkFactoryInstanceStatus', 'Get-EzDarkFactoryInstanceStorageLifecycleGuard', 'Start-EzDarkFactoryInstance', 'Stop-EzDarkFactoryInstance',
    'Get-EzDarkFactoryOpenSshTools', 'Get-EzDarkFactorySshPaths', 'Get-EzDarkFactoryControllerSshIdentity',
    'Get-EzDarkFactoryAvailableSshPort', 'Get-EzDarkFactoryCodingProfile', 'New-EzDarkFactoryInstanceSeedData', 'New-EzDarkFactorySshCommandArguments', 'New-EzDarkFactoryScpCommandArguments',
    'ConvertFrom-EzDarkFactoryReadinessProbe', 'Get-EzDarkFactorySshAccessState', 'Start-EzDarkFactoryReadyInstance',
    'Invoke-EzDarkFactorySsh', 'Invoke-EzDarkFactoryExec', 'Invoke-EzDarkFactoryCopyToGuest', 'Invoke-EzDarkFactoryCopyFromGuest',
    'Reset-EzDarkFactoryManagedInstance', 'Copy-EzDarkFactoryManagedInstance', 'Export-EzDarkFactoryManagedInstance',
    'Import-EzDarkFactoryManagedInstance', 'Test-EzDarkFactoryPortableBundle',
    'Invoke-EzDarkFactoryCommand', 'Write-EzDarkFactoryResult',
    'Get-EzDarkFactoryIdentity', 'Initialize-EzDarkFactoryIdentity', 'Get-EzDarkFactoryControlRevision',
    'Get-EzDarkFactoryControlCapabilities', 'Get-EzDarkFactoryInstanceRef', 'Get-EzDarkFactoryControlOperation',
    'Invoke-EzDarkFactoryControl', 'Initialize-EzDarkFactoryManagerWorkspace', 'Get-EzDarkFactoryManagerRegistry',
    'Get-EzDarkFactoryCandidate', 'Register-EzDarkFactoryManagerRoot', 'Unregister-EzDarkFactoryManagerRoot',
    'Get-EzDarkFactoryManagerObservations', 'Invoke-EzDarkFactoryManagerControl'
)
