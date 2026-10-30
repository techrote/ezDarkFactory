function ConvertTo-EzDarkFactoryConfigurationMap {
    param([AllowNull()][object]$Value)

    if ($Value -is [System.Collections.IDictionary]) {
        $map = [ordered]@{}
        foreach ($key in $Value.get_Keys()) {
            $map[$key] = ConvertTo-EzDarkFactoryConfigurationMap -Value $Value[$key]
        }
        return $map
    }
    if ($Value -is [pscustomobject]) {
        $map = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $map[$property.Name] = ConvertTo-EzDarkFactoryConfigurationMap -Value $property.Value
        }
        return $map
    }
    # Keep arrays intact so validation can reject them instead of silently unwrapping them.
    if ($Value -is [array]) { return ,$Value }
    return $Value
}

function Assert-EzDarkFactoryConfigurationKeys {
    param([object]$Value, [string[]]$Keys, [string]$Location)

    if ($Value -isnot [System.Collections.IDictionary]) {
        throw "Configuration '$Location' must be a JSON object. Restore its documented fields."
    }
    foreach ($key in $Value.get_Keys()) {
        if ($Keys -cnotcontains $key) {
            throw "Unknown configuration field '$Location.$key'. Remove it or use a documented field name."
        }
    }
    foreach ($key in $Keys) {
        if (@($Value.get_Keys()) -cnotcontains $key) {
            throw "Missing configuration field '$Location.$key'. Restore config/defaults.json from the checkout."
        }
    }
}

function Assert-EzDarkFactoryConfigurationInteger {
    param([AllowNull()][object]$Value, [long]$Minimum, [long]$Maximum, [string]$Location)

    $isInteger = $Value -is [int] -or $Value -is [long] -or $Value -is [short] -or
        $Value -is [byte] -or $Value -is [uint32] -or $Value -is [uint64] -or
        $Value -is [uint16] -or $Value -is [sbyte]
    if (-not $isInteger -or $Value -lt $Minimum -or $Value -gt $Maximum) {
        throw "Configuration '$Location' must be an integer from $Minimum to $Maximum. Correct the configuration and retry."
    }
}

function Assert-EzDarkFactoryConfiguration {
    param([object]$Value)

    Assert-EzDarkFactoryConfigurationKeys $Value @('schemaVersion', 'defaultProfile', 'profiles', 'ssh', 'timeouts') 'config'
    Assert-EzDarkFactoryConfigurationInteger $Value.schemaVersion 1 1 'schemaVersion'
    Assert-EzDarkFactoryConfigurationKeys $Value.profiles @('light', 'normal', 'heavy') 'profiles'
    if ($Value.defaultProfile -isnot [string] -or @('light', 'normal', 'heavy') -cnotcontains $Value.defaultProfile) {
        throw "Configuration 'defaultProfile' must be light, normal or heavy. Choose an existing profile."
    }
    foreach ($name in @('light', 'normal', 'heavy')) {
        $profile = $Value.profiles[$name]
        Assert-EzDarkFactoryConfigurationKeys $profile @('cpus', 'memoryMiB') "profiles.$name"
        Assert-EzDarkFactoryConfigurationInteger $profile.cpus 1 256 "profiles.$name.cpus"
        Assert-EzDarkFactoryConfigurationInteger $profile.memoryMiB 512 1048576 "profiles.$name.memoryMiB"
    }
    Assert-EzDarkFactoryConfigurationKeys $Value.ssh @('portRangeStart', 'portRangeEnd') 'ssh'
    Assert-EzDarkFactoryConfigurationInteger $Value.ssh.portRangeStart 1024 65535 'ssh.portRangeStart'
    Assert-EzDarkFactoryConfigurationInteger $Value.ssh.portRangeEnd 1024 65535 'ssh.portRangeEnd'
    if ($Value.ssh.portRangeStart -gt $Value.ssh.portRangeEnd) {
        throw "Configuration 'ssh.portRangeStart' must not exceed portRangeEnd. Correct the port range and retry."
    }
    Assert-EzDarkFactoryConfigurationKeys $Value.timeouts @('processSeconds') 'timeouts'
    Assert-EzDarkFactoryConfigurationInteger $Value.timeouts.processSeconds 1 3600 'timeouts.processSeconds'
}

function Merge-EzDarkFactoryConfigurationMap {
    param([System.Collections.IDictionary]$Defaults, [System.Collections.IDictionary]$Override, [string]$Location = 'config')

    foreach ($key in $Override.get_Keys()) {
        if (@($Defaults.get_Keys()) -cnotcontains $key) {
            throw "Unknown configuration field '$Location.$key'. Remove it or use a documented field name."
        }
        if ($Defaults[$key] -is [System.Collections.IDictionary]) {
            if ($Override[$key] -isnot [System.Collections.IDictionary]) {
                throw "Configuration '$Location.$key' must be a JSON object. Supply a nested override, not a replacement scalar or array."
            }
            Merge-EzDarkFactoryConfigurationMap -Defaults $Defaults[$key] -Override $Override[$key] -Location "$Location.$key"
        }
        else {
            $Defaults[$key] = $Override[$key]
        }
    }
}

function Get-EzDarkFactoryConfiguration {
    [CmdletBinding()]
    param([string]$Root = $script:EzDarkFactoryDefaultRoot)

    $paths = Get-EzDarkFactoryPaths -Root $Root
    $configuration = ConvertTo-EzDarkFactoryConfigurationMap (Read-EzDarkFactoryJson -Path $paths.Defaults)
    Assert-EzDarkFactoryConfiguration -Value $configuration
    if (Test-Path -LiteralPath $paths.UserConfig) {
        $userConfiguration = ConvertTo-EzDarkFactoryConfigurationMap (Read-EzDarkFactoryJson -Path $paths.UserConfig)
        Merge-EzDarkFactoryConfigurationMap -Defaults $configuration -Override $userConfiguration
        Assert-EzDarkFactoryConfiguration -Value $configuration
    }
    # Every load creates a fresh value; callers cannot mutate a cached global default.
    return [pscustomobject]$configuration
}
