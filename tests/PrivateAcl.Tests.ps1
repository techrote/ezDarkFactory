# Real Windows ACL fixtures. Synthetic bytes only; no account or privilege changes.
$privateAclWindowsSkip = if ($script:EzDarkFactoryIsWindowsHost) { '' } else { 'Private DACL regression requires a Windows filesystem; the separate hosted standard-user lanes are authoritative.' }

function Set-EzDarkFactoryTestAclDescriptor {
    param([string]$Path, [object]$Descriptor, [switch]$Directory)
    $item = if ($Directory) { [IO.DirectoryInfo]::new($Path) } else { [IO.FileInfo]::new($Path) }
    if ($PSVersionTable.PSVersion.Major -le 5) { $item.SetAccessControl($Descriptor) }
    else { [IO.FileSystemAclExtensions]::SetAccessControl($item, $Descriptor) }
}

function Assert-EzDarkFactoryTestPrivateAcl {
    param([string]$Path, [switch]$Directory)
    # Observe the OS descriptor independently of the product's readback path.
    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    Assert-EzDarkFactoryEqual $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value $sid
    Assert-EzDarkFactoryTrue $acl.AreAccessRulesProtected
    Assert-EzDarkFactoryEqual $rules.Count 1
    Assert-EzDarkFactoryEqual $rules[0].IdentityReference.Value $sid
    Assert-EzDarkFactoryEqual ([string]$rules[0].AccessControlType) 'Allow'
    Assert-EzDarkFactoryEqual ([string]$rules[0].FileSystemRights) 'FullControl'
    Assert-EzDarkFactoryTrue (-not $rules[0].IsInherited)
    Assert-EzDarkFactoryEqual ([string]$rules[0].PropagationFlags) 'None'
    $expectedInheritance = if ($Directory) { 'ContainerInherit, ObjectInherit' } else { 'None' }
    Assert-EzDarkFactoryEqual ([string]$rules[0].InheritanceFlags) $expectedInheritance
}

function Add-EzDarkFactoryTestBroadDirectoryAce {
    param([string]$Path, [string]$Sid)
    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $identity = [Security.Principal.SecurityIdentifier]::new($Sid)
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($identity, 'FullControl',
        'ContainerInherit, ObjectInherit', 'None', 'Allow'))
    Set-EzDarkFactoryTestAclDescriptor -Path $Path -Descriptor $acl -Directory
}

Add-EzDarkFactoryTest -Name 'Private ACL: inherited broad file access is removed and repeated protection preserves bytes' -SkipReason $privateAclWindowsSkip -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'inherited ACL [literal]'
    try {
        Add-EzDarkFactoryTestBroadDirectoryAce -Path $root -Sid 'S-1-1-0'
        $file = Join-Path $root 'synthetic [private].txt'
        [IO.File]::WriteAllText($file, 'synthetic private bytes; never a credential')
        $before = Get-Acl -LiteralPath $file
        $group = $before.GetGroup([Security.Principal.SecurityIdentifier]).Value
        $rules = @($before.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
        Assert-EzDarkFactoryTrue (@($rules | Where-Object { $_.IdentityReference.Value -ceq 'S-1-1-0' -and $_.IsInherited }).Count -gt 0)
        foreach ($iteration in 1..2) {
            & (Get-Module EzDarkFactory) { param($p) Protect-EzDarkFactoryControllerPrivateKey -Path $p } $file
            Assert-EzDarkFactoryTestPrivateAcl -Path $file
            Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText($file)) 'synthetic private bytes; never a credential'
            Assert-EzDarkFactoryEqual (Get-Acl -LiteralPath $file).GetGroup([Security.Principal.SecurityIdentifier]).Value $group
        }
    }
    finally { Remove-EzDarkFactoryTestDirectory $root }
}

Add-EzDarkFactoryTest -Name 'Private ACL: directory broad ACEs are removed and protected reapplication remains private' -SkipReason $privateAclWindowsSkip -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'directory ACL'
    try {
        Add-EzDarkFactoryTestBroadDirectoryAce -Path $root -Sid 'S-1-1-0'
        $directory = Join-Path $root 'synthetic key directory'
        [void][IO.Directory]::CreateDirectory($directory)
        Add-EzDarkFactoryTestBroadDirectoryAce -Path $directory -Sid 'S-1-5-11'
        $before = Get-Acl -LiteralPath $directory
        $group = $before.GetGroup([Security.Principal.SecurityIdentifier]).Value
        $rules = @($before.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
        Assert-EzDarkFactoryTrue (@($rules | Where-Object { $_.IdentityReference.Value -ceq 'S-1-1-0' -and $_.IsInherited }).Count -gt 0)
        Assert-EzDarkFactoryTrue (@($rules | Where-Object { $_.IdentityReference.Value -ceq 'S-1-5-11' -and -not $_.IsInherited }).Count -gt 0)
        foreach ($iteration in 1..2) {
            & (Get-Module EzDarkFactory) { param($p) Set-EzDarkFactoryPrivateAcl -Path $p -Directory } $directory
            Assert-EzDarkFactoryTestPrivateAcl -Path $directory -Directory
            Assert-EzDarkFactoryEqual (Get-Acl -LiteralPath $directory).GetGroup([Security.Principal.SecurityIdentifier]).Value $group
        }
        $child = Join-Path $directory 'new synthetic child.txt'
        [IO.File]::WriteAllText($child, 'fixture')
        $childAcl = Get-Acl -LiteralPath $child
        $childRules = @($childAcl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
        Assert-EzDarkFactoryEqual $childRules.Count 1
        Assert-EzDarkFactoryTrue $childRules[0].IsInherited
        Assert-EzDarkFactoryEqual $childRules[0].IdentityReference.Value ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
        Assert-EzDarkFactoryEqual ([string]$childRules[0].FileSystemRights) 'FullControl'
    }
    finally { Remove-EzDarkFactoryTestDirectory $root }
}

Add-EzDarkFactoryTest -Name 'Private ACL: wrong object types and missing targets refuse before mutation' -SkipReason $privateAclWindowsSkip -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'wrong ACL target'
    try {
        $file = Join-Path $root 'unchanged.txt'; [IO.File]::WriteAllText($file, 'sentinel')
        $fileAcl = (Get-Acl -LiteralPath $file).Sddl
        $directoryAcl = (Get-Acl -LiteralPath $root).Sddl
        Assert-EzDarkFactoryThrows { & (Get-Module EzDarkFactory) { param($p) Set-EzDarkFactoryPrivateAcl -Path $p -Directory } $file } -MessagePattern 'requested file or directory type' | Out-Null
        Assert-EzDarkFactoryThrows { & (Get-Module EzDarkFactory) { param($p) Set-EzDarkFactoryPrivateAcl -Path $p } $root } -MessagePattern 'requested file or directory type' | Out-Null
        $missing = Join-Path $root 'missing.txt'
        Assert-EzDarkFactoryThrows { & (Get-Module EzDarkFactory) { param($p) Set-EzDarkFactoryPrivateAcl -Path $p } $missing } -MessagePattern 'existing object' | Out-Null
        Assert-EzDarkFactoryEqual (Get-Acl -LiteralPath $file).Sddl $fileAcl
        Assert-EzDarkFactoryEqual (Get-Acl -LiteralPath $root).Sddl $directoryAcl
        Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText($file)) 'sentinel'
        Assert-EzDarkFactoryTrue (-not (Test-Path -LiteralPath $missing))
    }
    finally { Remove-EzDarkFactoryTestDirectory $root }
}

Add-EzDarkFactoryTest -Name 'Private ACL: denied DACL persistence terminates without changing the target' -SkipReason $privateAclWindowsSkip -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'denied ACL'
    try {
        $file = Join-Path $root 'readable without WRITE_DAC.txt'; [IO.File]::WriteAllText($file, 'sentinel')
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $acl = [Security.AccessControl.FileSecurity]::new()
        $acl.SetAccessRuleProtection($true, $false)
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid, 'Read', 'Allow'))
        # OWNER RIGHTS suppresses the owner's otherwise implicit WRITE_DAC.
        $ownerRights = [Security.Principal.SecurityIdentifier]::new('S-1-3-4')
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($ownerRights, 'ReadPermissions', 'Allow'))
        Set-EzDarkFactoryTestAclDescriptor -Path $file -Descriptor $acl
        $before = (Get-Acl -LiteralPath $file).Sddl
        Assert-EzDarkFactoryThrows { & (Get-Module EzDarkFactory) { param($p) Set-EzDarkFactoryPrivateAcl -Path $p } $file } | Out-Null
        Assert-EzDarkFactoryEqual (Get-Acl -LiteralPath $file).Sddl $before
        Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText($file)) 'sentinel'
        # The containing fixture still owns DELETE_CHILD; no permission repair.
        [IO.File]::Delete($file)
    }
    finally { Remove-EzDarkFactoryTestDirectory $root }
}

Add-EzDarkFactoryTest -Name 'Private ACL: pre-existing identity refuses native ACL failure before key derivation' -SkipReason $privateAclWindowsSkip -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'preserved ACL failure'
    try {
        $paths = Get-EzDarkFactorySshPaths -Root $root
        [void][IO.Directory]::CreateDirectory($paths.KeysDirectory)
        [IO.File]::WriteAllText($paths.ControllerPrivateKey, 'synthetic private bytes')
        [IO.File]::WriteAllText($paths.ControllerPublicKey, 'ssh-ed25519 AAAA fixture')
        $calls = [pscustomobject]@{ Keygen = 0; NativeAcl = 0 }
        $tools = [pscustomobject]@{ Valid = $true; Ssh = 'fixture'; Scp = 'fixture'; Keygen = 'fixture-keygen'; Missing = @(); Reason = 'fixture' }
        $runner = {
            param($exe, $arguments, $seconds)
            if ($exe -ceq 'fixture-keygen') { $calls.Keygen++; throw 'Key derivation must not run after ACL refusal.' }
            $calls.NativeAcl++
            return [pscustomobject]@{ ExitCode = 5; StdOut = ''; StdErr = 'synthetic ACL refusal' }
        }.GetNewClosure()
        Assert-EzDarkFactoryThrows { Get-EzDarkFactoryControllerSshIdentity -Root $root -Tooling $tools -ProcessRunner $runner } -MessagePattern 'Failed to restrict.*private-key ACL' | Out-Null
        Assert-EzDarkFactoryEqual $calls.NativeAcl 1
        Assert-EzDarkFactoryEqual $calls.Keygen 0
        Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText($paths.ControllerPrivateKey)) 'synthetic private bytes'
        Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText($paths.ControllerPublicKey)) 'ssh-ed25519 AAAA fixture'
    }
    finally { Remove-EzDarkFactoryTestDirectory $root }
}
