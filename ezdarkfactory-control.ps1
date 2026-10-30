#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RequestJson = '',
    [string]$RequestFile = '',
    [switch]$InitializeFactory
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ErrorRecordPreference = 'SilentlyContinue'
try {
    Import-Module (Join-Path $PSScriptRoot 'src/EzDarkFactory/Edf005.psm1') -Force -ErrorAction Stop
    if ($InitializeFactory) {
        if ($RequestFile -or $RequestJson) { throw 'InitializeFactory cannot be combined with a request.' }
        $value = Initialize-EzDarkFactoryIdentity -Root $PSScriptRoot
        $output = [pscustomobject][ordered]@{ schemaVersion = 1; state = 'completed'; data = $value; refusal = $null }
    }
    else {
        if ((-not $RequestJson -and -not $RequestFile) -or ($RequestJson -and $RequestFile)) {
            throw 'Supply exactly one -RequestJson or -RequestFile.'
        }
        if ($RequestFile) {
            $file = Get-Item -LiteralPath $RequestFile -ErrorAction Stop
            if ($file.Length -gt 65536) { throw 'Request file is larger than 64 KiB.' }
            $RequestJson = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
        }
        if ($RequestJson.Length -gt 65536) { throw 'Request is larger than 64 KiB.' }
        $request = ConvertFrom-EzDarkFactoryJsonText -Text $RequestJson -SchemaVersion 1 -Description 'Control request'
        $output = Invoke-EzDarkFactoryControl -Root $PSScriptRoot -Request $request
    }
    [Console]::Out.WriteLine((ConvertTo-Json -InputObject $output -Depth 64 -Compress))
    if ($output.state -cne 'completed') { exit 2 }
    exit 0
}
catch {
    # Never echo raw untrusted request contents or loader secrets into diagnostics.
    $safe = 'Control request refused before execution. Check root identity, envelope, API version and local module availability.'
    [Console]::Out.WriteLine((ConvertTo-Json -InputObject ([pscustomobject]@{
        schemaVersion = 1; state = 'refused'; data = $null
        refusal = [pscustomobject]@{ code = 'invalid_request'; message = $safe }
    }) -Depth 8 -Compress))
    exit 2
}
