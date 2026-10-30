#requires -Version 5.1
# Deliberately parse $args ourselves so invalid switches also get stable exit/JSON output.
# Legacy module autoload emits progress records even for help/version. Suppress
# those at the source before any cmdlet import can contaminate captured output.
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
$jsonRequested = $false
$afterCommandSeparator = $false
foreach ($argument in $args) {
    if ($argument -ceq '--') { $afterCommandSeparator = $true; continue }
    if (-not $afterCommandSeparator -and $argument -ieq '-Json') { $jsonRequested = $true }
}

try {
    Import-Module (Join-Path $PSScriptRoot 'src/EzDarkFactory/EzDarkFactory.psd1') -Force -ErrorAction Stop
    # EDF-005 reviewed supersession: official direct-CLI mutations on identity-enabled
    # roots share the typed manager's root-scoped lock. Pure reads and legacy
    # uninitialized factories remain side-effect-free and backward compatible.
    $commandParts = @($args | Where-Object { $_ -is [string] -and $_ -notin @('-Json','--') })
    $verb = if ($commandParts.Count -gt 0) { [string]$commandParts[0] } else { '' }
    $subverb = if ($commandParts.Count -gt 1) { [string]$commandParts[1] } else { '' }
    $mutating = ($verb -in @('bootstrap','create','clone','reset','export','import','start',
        'stop','exec','copy-to','copy-from')) -or ($verb -eq 'base' -and $subverb -in @('acquire','build'))
    $controlLock = $null
    try {
        if ($mutating -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'runtime/factory-identity.json') -PathType Leaf)) {
            Import-Module (Join-Path $PSScriptRoot 'src/EzDarkFactory/Edf005.psm1') -Force -ErrorAction Stop
            $controlModule = Get-Module Edf005
            $controlLock = & $controlModule {
                param([string]$Root)
                $null = Get-EzDarkFactoryIdentity -Root $Root
                Enter-EzDarkFactoryControlLock -Root $Root
            } $PSScriptRoot
        }
        $result = Invoke-EzDarkFactoryCommand -Arguments $args -Root $PSScriptRoot
        Write-EzDarkFactoryResult -Result $result -Json:$jsonRequested
        exit $result.exitCode
    }
    finally { if ($null -ne $controlLock) { $controlLock.Dispose() } }
}
catch {
    # This fallback also covers a broken/missing module. Never mix diagnostics into JSON.
    $message = "ezdarkfactory could not complete the command: $($_.Exception.Message) Restore a complete checkout or correct the reported configuration, then retry."
    $module = Get-Module EzDarkFactory
    if ($null -ne $module) {
        $message = & $module { param($text) Protect-EzDarkFactoryDiagnosticText -Text $text } $message
    }
    else { $message = 'ezdarkfactory could not load its control plane. Restore a complete checkout; raw loader diagnostics are not included in structured output.' }
    if ($jsonRequested) {
        $failure = [ordered]@{
            schemaVersion = 1
            success = $false
            command = $null
            exitCode = 1
            data = $null
            error = [ordered]@{ code = 'execution_failed'; message = $message }
        }
        Write-Output ($failure | ConvertTo-Json -Depth 8 -Compress)
    }
    else {
        [Console]::Error.WriteLine($message)
    }
    exit 1
}
