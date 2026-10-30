function New-EzDarkFactorySecurityDirectoryLink {
    param([string]$Path, [string]$Target)
    $kind = if ($script:EzDarkFactoryIsWindowsHost) { 'Junction' } else { 'SymbolicLink' }
    New-Item -ItemType $kind -Path $Path -Target $Target -ErrorAction Stop | Out-Null
}

Add-EzDarkFactoryTest -Name 'Security: redirected download cache refuses before deletion or downloader execution' -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'cache redirection'
    $link = Join-Path $root 'cache'
    try {
        $outside = Join-Path $root 'outside'
        [void][IO.Directory]::CreateDirectory($outside)
        $victim = Join-Path $outside 'artifact.txt'
        [IO.File]::WriteAllText($victim, 'outside bytes must survive')
        New-EzDarkFactorySecurityDirectoryLink -Path $link -Target $outside
        $observed = [pscustomobject]@{ Calls = 0 }
        $download = { param($url, $path) $observed.Calls++; throw 'unexpected downloader' }.GetNewClosure()
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Get-EzDarkFactoryVerifiedArtifact -Url 'https://example.invalid/artifact' -FileName 'artifact.txt' -Algorithm SHA256 -ExpectedDigest ('a' * 64) -DestinationDirectory $link -Downloader $download
        } -MessagePattern 'reparse|symlink|redirection' | Out-Null
        Assert-EzDarkFactoryEqual -Actual $observed.Calls -Expected 0
        Assert-EzDarkFactoryEqual -Actual ([IO.File]::ReadAllText($victim)) -Expected 'outside bytes must survive'
    }
    finally {
        if (Test-Path -LiteralPath $link) { [IO.Directory]::Delete($link) }
        Remove-EzDarkFactoryTestDirectory $root
    }
}

Add-EzDarkFactoryTest -Name 'Security: JSON replacement rejects redirected ancestors and preserves outside bytes' -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'JSON redirection'
    $link = Join-Path $root 'alias'
    try {
        $outside = Join-Path $root 'outside'
        [void][IO.Directory]::CreateDirectory($outside)
        $victim = Join-Path $outside 'state.json'
        [IO.File]::WriteAllText($victim, '{"schemaVersion":1,"value":"original"}')
        New-EzDarkFactorySecurityDirectoryLink -Path $link -Target $outside
        Assert-EzDarkFactoryThrows -ScriptBlock {
            Write-EzDarkFactoryJson -Path (Join-Path $link 'state.json') -Value @{ schemaVersion = 1; value = 'changed' }
        } -MessagePattern 'reparse|symlink|redirection' | Out-Null
        Assert-EzDarkFactoryEqual -Actual ([IO.File]::ReadAllText($victim)) -Expected '{"schemaVersion":1,"value":"original"}'
    }
    finally {
        if (Test-Path -LiteralPath $link) { [IO.Directory]::Delete($link) }
        Remove-EzDarkFactoryTestDirectory $root
    }
}

Add-EzDarkFactoryTest -Name 'Security: dangling directory links and ancestors above managed roots are refused' -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'ancestor redirection'
    $link = Join-Path $root 'alias'
    try {
        $target = Join-Path $root 'target'
        [void][IO.Directory]::CreateDirectory($target)
        New-EzDarkFactorySecurityDirectoryLink -Path $link -Target $target
        $module = Get-Module EzDarkFactory
        Assert-EzDarkFactoryThrows { & $module { param($p) Assert-EzDarkFactorySafePath -Path (Join-Path $p 'nested/new.json') } $link } -MessagePattern 'reparse' | Out-Null
        [IO.Directory]::Delete($target)
        Assert-EzDarkFactoryThrows { & $module { param($p) Assert-EzDarkFactorySafePath -Path $p } $link } -MessagePattern 'reparse' | Out-Null
    }
    finally {
        try { [IO.Directory]::Delete($link) } catch { }
        Remove-EzDarkFactoryTestDirectory $root
    }
}

Add-EzDarkFactoryTest -Name 'Security: recursive cleanup preflights all descendants without following a junction' -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'safe cleanup'
    $link = Join-Path $root 'stage/redirect'
    try {
        $stage = Join-Path $root 'stage'; $outside = Join-Path $root 'outside'
        [void][IO.Directory]::CreateDirectory($stage); [void][IO.Directory]::CreateDirectory($outside)
        [IO.File]::WriteAllText((Join-Path $stage 'keep.txt'), 'stage evidence')
        [IO.File]::WriteAllText((Join-Path $outside 'keep.txt'), 'outside evidence')
        New-EzDarkFactorySecurityDirectoryLink -Path $link -Target $outside
        Assert-EzDarkFactoryThrows { & (Get-Module EzDarkFactory) { param($p) Remove-EzDarkFactorySafeTree -Path $p } $stage } -MessagePattern 'reparse' | Out-Null
        Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText((Join-Path $stage 'keep.txt'))) 'stage evidence'
        Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText((Join-Path $outside 'keep.txt'))) 'outside evidence'
    }
    finally { if (Test-Path -LiteralPath $link) { [IO.Directory]::Delete($link) }; Remove-EzDarkFactoryTestDirectory $root }
}

Add-EzDarkFactoryTest -Name 'Security: invalid acquisition URL cannot delete an existing cache entry' -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'invalid url'
    try {
        $file = Join-Path $root 'artifact.bin'; [IO.File]::WriteAllText($file, 'preserve before validation')
        foreach ($url in @('http://example.invalid/a', 'https://user:password@example.invalid/a')) {
            Assert-EzDarkFactoryThrows { Get-EzDarkFactoryVerifiedArtifact -Url $url -FileName 'artifact.bin' -Algorithm SHA256 -ExpectedDigest ('a' * 64) -DestinationDirectory $root -Downloader { throw 'not reached' } } -MessagePattern 'HTTPS' | Out-Null
            Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText($file)) 'preserve before validation'
        }
        foreach ($name in @('..', '.', 'a:b', 'a\b', 'a/b')) {
            Assert-EzDarkFactoryThrows { Get-EzDarkFactoryVerifiedArtifact -Url 'https://example.invalid/a' -FileName $name -Algorithm SHA256 -ExpectedDigest ('a' * 64) -DestinationDirectory $root -Downloader { throw 'not reached' } } -MessagePattern 'plain filename' | Out-Null
        }
    }
    finally { Remove-EzDarkFactoryTestDirectory $root }
}

Add-EzDarkFactoryTest -Name 'Security: failed acquisition preserves a competing destination and removes only its temporary file' -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'competing cache'
    try {
        $destination = Join-Path $root 'artifact.bin'
        $downloader = { param($u, $p) [IO.File]::WriteAllText($destination, 'competing publisher evidence'); [IO.File]::WriteAllText($p, 'partial'); throw 'interrupted' }.GetNewClosure()
        Assert-EzDarkFactoryThrows { Get-EzDarkFactoryVerifiedArtifact -Url 'https://example.invalid/a' -FileName 'artifact.bin' -Algorithm SHA256 -ExpectedDigest ('a' * 64) -DestinationDirectory $root -Downloader $downloader } -MessagePattern 'interrupted' | Out-Null
        Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText($destination)) 'competing publisher evidence'
        Assert-EzDarkFactoryEqual @(Get-ChildItem -LiteralPath $root -Filter '*.tmp' -Force).Count 0
    }
    finally { Remove-EzDarkFactoryTestDirectory $root }
}

Add-EzDarkFactoryTest -Name 'Security: redirect resolution forbids downgrade and userinfo while accepting relative HTTPS locations' -ScriptBlock {
    & (Get-Module EzDarkFactory) {
        $base = [Uri]'https://example.invalid/path/file'
        if ((Resolve-EzDarkFactoryDownloadUrl -Url '../other' -Base $base).AbsoluteUri -cne 'https://example.invalid/other') { throw 'Relative redirect was not resolved.' }
        foreach ($url in @('http://example.invalid/a', 'file:///tmp/a', 'https://user:secret@example.invalid/a')) {
            $rejected = $false; try { $null = Resolve-EzDarkFactoryDownloadUrl -Url $url -Base $base } catch { $rejected = $true }
            if (-not $rejected) { throw 'Unsafe redirect was accepted.' }
        }
    }
}

Add-EzDarkFactoryTest -Name 'Security: state text is bounded and refuses reparse reads' -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'bounded state'
    try {
        $path = Join-Path $root 'large.json'
        [IO.File]::WriteAllText($path, ('x' * 2097153))
        Assert-EzDarkFactoryThrows { Read-EzDarkFactoryJson -Path $path } -MessagePattern 'bounded read limit' | Out-Null
        $module = Get-Module EzDarkFactory
        $small = Join-Path $root 'small.txt'; [IO.File]::WriteAllText($small, '12345')
        Assert-EzDarkFactoryEqual (& $module { param($p) Read-EzDarkFactoryBoundedText -Path $p -MaximumBytes 5 } $small) '12345'
        Assert-EzDarkFactoryThrows { & $module { param($p) Read-EzDarkFactoryBoundedText -Path $p -MaximumBytes 4 } $small } -MessagePattern 'bounded' | Out-Null
    }
    finally { Remove-EzDarkFactoryTestDirectory $root }
}

function New-EzDarkFactorySecurityQemuRuntime {
    param([string]$Root)
    $paths = Get-EzDarkFactoryPaths -Root $Root
    [void][IO.Directory]::CreateDirectory($paths.Qemu)
    foreach ($file in @('qemu-img.exe', 'qemu-system-x86_64.exe', 'dependency.dll', 'firmware.fd')) { [IO.File]::WriteAllText((Join-Path $paths.Qemu $file), ('fixture ' + $file)) }
    $manifestDigest = Get-EzDarkFactoryFileDigest -Path $paths.QemuManifest -Algorithm SHA256
    $digest = & (Get-Module EzDarkFactory) { param($p, $d) Write-EzDarkFactoryQemuPayloadInventory -RuntimeDirectory $p -ManifestDigest $d } $paths.Qemu $manifestDigest
    Write-EzDarkFactoryJson -Path (Join-Path $paths.Qemu 'ezdarkfactory-provenance.json') -Value @{ schemaVersion = 1; manifestSha256 = $manifestDigest; payloadManifestSha256 = $digest }
    return $paths
}

Add-EzDarkFactoryTest -Name 'Security: installed executable DLL firmware and inventory tampering refuse before any version probe' -ScriptBlock {
    foreach ($mode in @('qemu-img.exe', 'dependency.dll', 'firmware.fd', 'extra.dll', 'missing', 'receipt')) {
        $root = New-EzDarkFactoryCheckoutFixture -Prefix ('QEMU tamper ' + $mode)
        try {
            $paths = New-EzDarkFactorySecurityQemuRuntime $root
            $calls = [pscustomobject]@{ Count = 0 }
            $probe = { param($r, $v) $calls.Count++; [pscustomobject]@{ QemuSystemVersion = "QEMU emulator version $v"; QemuImgVersion = "qemu-img version $v" } }.GetNewClosure()
            Assert-EzDarkFactoryTrue (Get-EzDarkFactoryManagedQemuStatus -Root $root -PayloadProbe $probe).Valid
            Assert-EzDarkFactoryEqual $calls.Count 1
            if ($mode -ceq 'missing') { [IO.File]::Delete((Join-Path $paths.Qemu 'dependency.dll')) }
            elseif ($mode -ceq 'receipt') { [IO.File]::AppendAllText((Join-Path $paths.Qemu 'ezdarkfactory-payload.json'), ' ') }
            else { [IO.File]::WriteAllText((Join-Path $paths.Qemu $mode), 'tampered bytes') }
            $status = Get-EzDarkFactoryManagedQemuStatus -Root $root -PayloadProbe $probe
            Assert-EzDarkFactoryEqual $status.Valid $false
            Assert-EzDarkFactoryEqual $calls.Count 1 -Message 'Tampered installed content must not execute even a version probe.'
            Assert-EzDarkFactoryThrows { Get-EzDarkFactoryQemuToolPath -Root $root -Name 'qemu-img.exe' } -MessagePattern 'payload|inventory' | Out-Null
        }
        finally { Remove-EzDarkFactoryTestDirectory $root }
    }
}

Add-EzDarkFactoryTest -Name 'Security: legacy QEMU receipts are not upgraded from unverified installed bytes' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'legacy QEMU receipt'
    try {
        $paths = New-EzDarkFactorySecurityQemuRuntime $root
        $receiptPath = Join-Path $paths.Qemu 'ezdarkfactory-provenance.json'
        $receipt = Read-EzDarkFactoryJson $receiptPath; $receipt.PSObject.Properties.Remove('payloadManifestSha256')
        Write-EzDarkFactoryJson $receiptPath $receipt
        $before = [IO.File]::ReadAllText($receiptPath)
        $status = Get-EzDarkFactoryManagedQemuStatus -Root $root -PayloadProbe { throw 'must not execute installed bytes' }
        Assert-EzDarkFactoryEqual $status.Valid $false
        Assert-EzDarkFactoryTrue ($status.Reason -match 'lacks a verified payload inventory')
        Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText($receiptPath)) $before
    }
    finally { Remove-EzDarkFactoryTestDirectory $root }
}

Add-EzDarkFactoryTest -Name 'Security: seed shutdown expires transport and releases payloads without retaining rejected request targets' -ScriptBlock {
    $server = Start-EzDarkFactorySeedServer -UserData 'private seed fixture' -MetaData 'meta fixture' -TimeoutSeconds 30
    try {
        $null = Invoke-EzDarkFactorySeedHttpFixture -Server $server -RequestLine 'GET /bad?token=synthetic-sensitive-query HTTP/1.1'
        Assert-EzDarkFactoryEqual @($server.RequestPaths.ToArray()) @('<rejected>')
        $server.DeadlineUtc = [DateTime]::UtcNow.AddSeconds(-1)
        Assert-EzDarkFactoryThrows { Invoke-EzDarkFactorySeedServerPending $server } -MessagePattern 'bounded lifetime' | Out-Null
        Assert-EzDarkFactoryEqual $server.Closed $true
        Assert-EzDarkFactoryEqual $server.UserData ''
        Assert-EzDarkFactoryEqual $server.MetaData ''
        Assert-EzDarkFactoryEqual $server.Clients.Count 0
    }
    finally { Stop-EzDarkFactorySeedServer $server }
    Assert-EzDarkFactoryThrows { Start-EzDarkFactorySeedServer -UserData ('u' * 1048577) -MetaData 'm' } -MessagePattern 'bounded' | Out-Null
}

Add-EzDarkFactoryTest -Name 'Security: seed client count and request history remain bounded' -ScriptBlock {
    $server = Start-EzDarkFactorySeedServer -UserData 'u' -MetaData 'm' -TimeoutSeconds 30
    $clients = New-Object 'System.Collections.Generic.List[object]'
    try {
        for ($i = 0; $i -lt 24; $i++) {
            $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', $server.Port); $clients.Add($c)
        }
        $null = Invoke-EzDarkFactorySeedServerPending -Server $server -MaxRequests 64
        Assert-EzDarkFactoryTrue ($server.Clients.Count -le 16)
        foreach ($c in $clients) { $c.Dispose() }
        $null = Invoke-EzDarkFactorySeedServerPending -Server $server -MaxRequests 64
        for ($i = 0; $i -lt 70; $i++) { $null = Invoke-EzDarkFactorySeedHttpFixture -Server $server -RequestLine 'GET /meta-data HTTP/1.1' }
        Assert-EzDarkFactoryEqual $server.RequestPaths.Count 64
    }
    finally { foreach ($c in $clients) { $c.Dispose() }; Stop-EzDarkFactorySeedServer $server }
}

Add-EzDarkFactoryTest -Name 'Security: controller identity mismatch preserves both pre-existing key files' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'controller mismatch'
    try {
        $paths = Get-EzDarkFactorySshPaths -Root $root
        [void][IO.Directory]::CreateDirectory($paths.KeysDirectory)
        [IO.File]::WriteAllText($paths.ControllerPrivateKey, 'synthetic private bytes')
        [IO.File]::WriteAllText($paths.ControllerPublicKey, 'ssh-ed25519 AAAA fixture')
        $tools = [pscustomobject]@{ Valid = $true; Ssh = 'fixture'; Scp = 'fixture'; Keygen = 'fixture-keygen'; Missing = @(); Reason = 'fixture' }
        $runner = { param($exe, $arguments, $seconds) [pscustomobject]@{ ExitCode = 0; StdOut = $(if ($exe -ceq 'fixture-keygen') { 'ssh-ed25519 BBBB' } else { '' }); StdErr = '' } }
        Assert-EzDarkFactoryThrows { Get-EzDarkFactoryControllerSshIdentity -Root $root -Tooling $tools -ProcessRunner $runner } -MessagePattern 'public/private key mismatch' | Out-Null
        Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText($paths.ControllerPrivateKey)) 'synthetic private bytes'
        Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText($paths.ControllerPublicKey)) 'ssh-ed25519 AAAA fixture'
    }
    finally { Remove-EzDarkFactoryTestDirectory $root }
}

Add-EzDarkFactoryTest -Name 'Security: token guards and bounded diagnostics redact before truncating' -ScriptBlock {
    $tokens = @('ghp_' + ('A' * 36), 'github_pat_' + ('B' * 70), 'sk-proj-' + ('C' * 60), 'AKIA' + ('D' * 16))
    foreach ($token in $tokens) {
        Assert-EzDarkFactoryThrows { & (Get-Module EzDarkFactory) { param($t) Assert-EzDarkFactoryCredentialFreeText -Text $t } $token } -MessagePattern 'credential-like' | Out-Null
        $safe = & (Get-Module EzDarkFactory) { param($t) Protect-EzDarkFactoryDiagnosticText -Text ('prefix ' + $t + ' suffix') -MaximumCharacters 64 } $token
        Assert-EzDarkFactoryTrue ($safe.Contains('[REDACTED]') -and -not $safe.Contains($token.Substring(0, 10)))
    }
    $safe = & (Get-Module EzDarkFactory) { Protect-EzDarkFactoryDiagnosticText -Text 'Authorization: Bearer synthetic-value' }
    Assert-EzDarkFactoryEqual $safe 'Authorization: Bearer [REDACTED]'
}

Add-EzDarkFactoryTest -Name 'Security: unsafe transfer destinations and controller-key sources refuse before guest access' -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'copy boundaries'
    $link = Join-Path $root 'redirect'
    try {
        $paths = Get-EzDarkFactoryPaths -Root $root
        [void][IO.Directory]::CreateDirectory($paths.Keys)
        [IO.File]::WriteAllText((Join-Path $paths.Keys 'controller_ed25519'), 'fixture')
        Assert-EzDarkFactoryThrows { Invoke-EzDarkFactoryCopyToGuest -Root $root -InstanceName absent -HostPath (Join-Path $paths.Keys 'controller_ed25519') -GuestPath '/tmp/key' } -MessagePattern 'must not be transferred' | Out-Null
        Assert-EzDarkFactoryThrows { Invoke-EzDarkFactoryCopyFromGuest -Root $root -InstanceName absent -GuestPath '/tmp/file' -HostPath (Join-Path $paths.Keys 'controller_ed25519') } -MessagePattern 'cannot replace managed runtime' | Out-Null
        New-EzDarkFactorySecurityDirectoryLink -Path $link -Target $root
        Assert-EzDarkFactoryThrows { Invoke-EzDarkFactoryCopyFromGuest -Root $root -InstanceName absent -GuestPath '/tmp/file' -HostPath (Join-Path $link 'target') } -MessagePattern 'reparse' | Out-Null
    }
    finally { if (Test-Path -LiteralPath $link) { [IO.Directory]::Delete($link) }; Remove-EzDarkFactoryTestDirectory $root }
}

$securityWindowsSkip = if ($script:EzDarkFactoryIsWindowsHost) { '' } else { 'Windows-specific ACL, hard-link and device-path checks execute in both required Windows lanes.' }
Add-EzDarkFactoryTest -Name 'Security: Windows path validation reaches the drive root under both PowerShell runtimes' -SkipReason $securityWindowsSkip -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'drive root ancestor'
    try {
        $candidate = Join-Path $root 'nested/path.txt'
        $validated = & (Get-Module EzDarkFactory) { param($p) Assert-EzDarkFactorySafePath -Path $p } $candidate
        Assert-EzDarkFactoryEqual $validated ([IO.Path]::GetFullPath($candidate))
    }
    finally { Remove-EzDarkFactoryTestDirectory $root }
}

Add-EzDarkFactoryTest -Name 'Security: Windows private ACL removes pre-existing broad explicit ACEs' -SkipReason $securityWindowsSkip -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'explicit ACL'
    try {
        $file = Join-Path $root 'private.txt'; [IO.File]::WriteAllText($file, 'fixture')
        $acl = Get-Acl -LiteralPath $file
        $everyone = [Security.Principal.SecurityIdentifier]::new('S-1-1-0')
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($everyone, 'FullControl', 'Allow'))
        Set-Acl -LiteralPath $file -AclObject $acl
        & (Get-Module EzDarkFactory) { param($p) Protect-EzDarkFactoryControllerPrivateKey -Path $p } $file
        $after = Get-Acl -LiteralPath $file
        $rules = @($after.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
        Assert-EzDarkFactoryEqual $rules.Count 1
        Assert-EzDarkFactoryEqual $rules[0].IdentityReference.Value ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
    }
    finally { Remove-EzDarkFactoryTestDirectory $root }
}

Add-EzDarkFactoryTest -Name 'Security: Windows hard-linked keys refuse permission mutation of another file' -SkipReason $securityWindowsSkip -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'hardlink ACL'
    try {
        $file = Join-Path $root 'outside.txt'; $link = Join-Path $root 'private.txt'
        [IO.File]::WriteAllText($file, 'outside')
        New-Item -ItemType HardLink -Path $link -Target $file | Out-Null
        $before = (Get-Acl -LiteralPath $file).Sddl
        Assert-EzDarkFactoryThrows { & (Get-Module EzDarkFactory) { param($p) Protect-EzDarkFactoryControllerPrivateKey -Path $p } $link } -MessagePattern 'hard-linked' | Out-Null
        Assert-EzDarkFactoryEqual (Get-Acl -LiteralPath $file).Sddl $before
    }
    finally { Remove-EzDarkFactoryTestDirectory $root }
}

Add-EzDarkFactoryTest -Name 'Security: Windows ADS device and ambiguous trailing-component paths refuse' -SkipReason $securityWindowsSkip -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'Windows path syntax'
    try {
        foreach ($tail in @('state.json:stream', 'NUL', 'CON.txt', 'COM1', 'bad.', 'bad ')) {
            Assert-EzDarkFactoryThrows { & (Get-Module EzDarkFactory) { param($p) Assert-EzDarkFactorySafePath -Path $p } (Join-Path $root $tail) } -MessagePattern 'unsafe|alternate|local drive' | Out-Null
        }
        Assert-EzDarkFactoryThrows { & (Get-Module EzDarkFactory) { Assert-EzDarkFactorySafePath -Path '\\?\C:\Windows' } } -MessagePattern 'local drive|namespace' | Out-Null
    }
    finally { Remove-EzDarkFactoryTestDirectory $root }
}

Add-EzDarkFactoryTest -Name 'Security: base seed rejects token-shaped content in either template before guest execution' -ScriptBlock {
    foreach ($template in @('user-data.yaml', 'meta-data.yaml')) {
        $root = New-EzDarkFactoryCheckoutFixture -Prefix 'base input tokens'
        try {
            $path = Join-Path (Get-EzDarkFactoryPaths $root).BaseCloudInit $template
            [IO.File]::AppendAllText($path, ("`n# synthetic " + 'ghp_' + ('Z' * 36) + "`n"))
            Assert-EzDarkFactoryThrows { New-EzDarkFactoryBaseSeedData -Root $root -BuildId ('a' * 32) } -MessagePattern 'credential-like' | Out-Null
            Assert-EzDarkFactoryTrue (-not (Test-Path -LiteralPath (Get-EzDarkFactoryPaths $root).Instances))
        }
        finally { Remove-EzDarkFactoryTestDirectory $root }
    }
}

Add-EzDarkFactoryTest -Name 'Security: production overlay validation rejects external dependencies before resolving a QEMU executable' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    try {
        Write-EzDarkFactorySnapshotFixtureImage -Path $fixture.Disk -Backing '../../../outside.qcow2'
        # No metadata runner and no QEMU installation: a dependency error must
        # precede tool resolution, so this tests the real production preflight.
        Assert-EzDarkFactoryThrows { Test-EzDarkFactoryInstanceOverlay -Root $fixture.Root -OverlayPath $fixture.Disk -BaseId $fixture.Intent.baseId } -MessagePattern 'backing' | Out-Null
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Security: tracked token formats are rejected without displaying their bytes' -ScriptBlock {
    $root = New-EzDarkFactoryRepositoryFixture
    try {
        $credential = 'github_pat_' + ('Z' * 70)
        $null = Add-EzDarkFactoryTrackedFixtureFile -Root $root -RelativePath 'notes/token.txt' -Content $credential
        $errorText = ''
        try { $null = Test-EzDarkFactoryRepositoryContract -Root $root } catch { $errorText = $_.Exception.Message }
        Assert-EzDarkFactoryTrue ($errorText.Contains('credential-like'))
        Assert-EzDarkFactoryTrue (-not $errorText.Contains($credential))
    }
    finally { Remove-EzDarkFactoryTestDirectory $root }
}

Add-EzDarkFactoryTest -Name 'Security: bootstrap revalidates all acquired inputs before executing the extractor' -SkipReason $qemuWindowsSkip -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'late acquisition mutation'
    try {
        $fixture = New-EzDarkFactoryQemuFixture -Root $root
        $hooks = New-EzDarkFactoryQemuFixtureHooks -Fixture $fixture
        $cache = (Get-EzDarkFactoryPaths $root).Downloads
        $download = $hooks.Downloader
        $changedDownload = {
            param($url, $destination)
            & $download $url $destination
            if ($url -match '7zip-package-fixture') {
                [IO.File]::WriteAllText((Join-Path $cache 'qemu-fixture.exe'), 'changed after earlier successful verification')
            }
        }.GetNewClosure()
        $calls = [pscustomobject]@{ Count = 0 }
        $extractor = { param($b, $p, $d, $v) $calls.Count++; throw 'unverified input reached execution' }.GetNewClosure()
        Assert-EzDarkFactoryThrows { Install-EzDarkFactoryQemuRuntime -Root $root -ManifestPath $fixture.ManifestPath -Downloader $changedDownload -ExtractorBootstrapper $extractor } -MessagePattern 'changed before extraction' | Out-Null
        Assert-EzDarkFactoryEqual $calls.Count 0
        Assert-EzDarkFactoryTrue (-not (Test-Path -LiteralPath (Get-EzDarkFactoryPaths $root).Qemu))
    }
    finally { Remove-EzDarkFactoryTestDirectory $root }
}

Add-EzDarkFactoryTest -Name 'Security: invalid installed runtime is preserved instead of replaced during bootstrap' -SkipReason $qemuWindowsSkip -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'preserve invalid runtime'
    try {
        $paths = Get-EzDarkFactoryPaths $root
        [void][IO.Directory]::CreateDirectory($paths.Qemu)
        $evidence = Join-Path $paths.Qemu 'evidence.txt'
        [IO.File]::WriteAllText($evidence, 'preserve exactly')
        Assert-EzDarkFactoryThrows { Install-EzDarkFactoryQemuRuntime -Root $root -Downloader { throw 'must not download' } } -MessagePattern 'will not be replaced automatically' | Out-Null
        Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText($evidence)) 'preserve exactly'
    }
    finally { Remove-EzDarkFactoryTestDirectory $root }
}

Add-EzDarkFactoryTest -Name 'Security: actual Windows key generation and staged copy-from preserve destination on failure' -SkipReason $qemuWindowsSkip -ScriptBlock {
    $root = New-EzDarkFactoryCheckoutFixture -Prefix 'native key and atomic transfer'
    try {
        $intent = New-EzDarkFactoryPortabilityIdentityTestIntent
        $access = New-EzDarkFactorySshTestAccess -Root $root -Intent $intent
        $launch = New-EzDarkFactorySshTestLaunch -Root $root -Intent $intent -Access $access
        $access.state = 'READY'; $access.readyAt = [DateTime]::UtcNow.ToString('o')
        Write-EzDarkFactoryJson -Path (Get-EzDarkFactorySshPaths -Root $root -InstanceName $intent.name).AccessState -Value $access -SchemaVersion 2
        $identity = Get-EzDarkFactoryControllerSshIdentity -Root $root
        $originalKey = Get-EzDarkFactoryFileDigest -Path $identity.PrivateKey -Algorithm SHA256
        $again = Get-EzDarkFactoryControllerSshIdentity -Root $root
        Assert-EzDarkFactoryEqual $again.PublicKeyText $identity.PublicKeyText
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $identity.PrivateKey -Algorithm SHA256) $originalKey
        $output = Join-Path $root 'result with spaces.txt'
        [IO.File]::WriteAllText($output, 'old result')
        $partial = {
            param($exe, $arguments, $timeout)
            [IO.File]::WriteAllText($arguments[-1], 'partial bytes')
            [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'synthetic transfer failure' }
        }
        Assert-EzDarkFactoryThrows { Invoke-EzDarkFactoryCopyFromGuest -Root $root -InstanceName $intent.name -GuestPath '/tmp/result' -HostPath $output -ProcessProvider $launch.ProcessProvider -ScpRunner $partial } -MessagePattern 'copy-from failed' | Out-Null
        Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText($output)) 'old result'
        Assert-EzDarkFactoryEqual @(Get-ChildItem -LiteralPath $root -Force -Filter '.ezdarkfactory-copy-*').Count 0
        $complete = {
            param($exe, $arguments, $timeout)
            if ($arguments -cnotcontains 'BatchMode=yes') { throw 'transfer must be noninteractive' }
            [IO.File]::WriteAllText($arguments[-1], 'complete new bytes')
            [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
        }
        $null = Invoke-EzDarkFactoryCopyFromGuest -Root $root -InstanceName $intent.name -GuestPath '/tmp/result' -HostPath $output -ProcessProvider $launch.ProcessProvider -ScpRunner $complete
        Assert-EzDarkFactoryEqual ([IO.File]::ReadAllText($output)) 'complete new bytes'
        Assert-EzDarkFactoryEqual @(Get-ChildItem -LiteralPath $root -Force -Filter '.ezdarkfactory-copy-*').Count 0
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $identity.PrivateKey -Algorithm SHA256) $originalKey
    }
    finally { Remove-EzDarkFactoryTestDirectory $root }
}
