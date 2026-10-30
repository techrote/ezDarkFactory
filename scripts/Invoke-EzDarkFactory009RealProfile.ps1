#requires -Version 5.1
[CmdletBinding()]
param([string]$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')))

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Import-Module (Join-Path $Root 'src/EzDarkFactory/EzDarkFactory.psd1') -Force -ErrorAction Stop
$module = Get-Module EzDarkFactory
$instanceName = 'ezdarkfactory009-real-profile'
$started = $false
$missingToolHidden = $false
$tooling = $null
$controller = $null
$profile = $null
$intent = $null
$sentinel = 'EDF009_WORKSPACE_' + [Guid]::NewGuid().ToString('N')

function Invoke-EzDarkFactory009Guest {
    param([Parameter(Mandatory = $true)][string]$Script, [int]$TimeoutSeconds = 120, [switch]$WhileNotReady)

    if ($WhileNotReady) {
        # Negative readiness evidence must disable the ordinary exec surface.
        # Recovery uses the already authenticated instance's scoped, strict
        # known-hosts entry and the same independently validated running owner.
        $access = Get-EzDarkFactorySshAccessState -Root $Root -InstanceName $instanceName
        $knownHosts = (Get-EzDarkFactorySshPaths -Root $Root -InstanceName $instanceName).InstanceKnownHosts
        $arguments = New-EzDarkFactorySshCommandArguments -PrivateKey $controller.PrivateKey -KnownHosts $knownHosts -Port ([int]$access.sshPort) -User 'coder' -Batch -RemoteCommand @('sh', '-lc', $Script)
        $result = Invoke-EzDarkFactoryProcess -FilePath $tooling.Ssh -ArgumentList $arguments -TimeoutSeconds $TimeoutSeconds
    }
    else {
        $result = Invoke-EzDarkFactoryExec -Root $Root -InstanceName $instanceName -Command @('sh', '-lc', $Script) -TimeoutSeconds $TimeoutSeconds
    }
    if ([int]$result.ExitCode -ne 0) {
        throw "Real coding-profile guest check failed with exit $($result.ExitCode). stdout=<$($result.StdOut)> stderr=<$($result.StdErr)>"
    }
    return [string]$result.StdOut
}

function Assert-EzDarkFactory009Marker {
    param([Parameter(Mandatory = $true)][string]$ExpectedCloudInstanceId)

    $text = Invoke-EzDarkFactory009Guest -Script 'cat /var/lib/ezdarkfactory/ready.json' -TimeoutSeconds 60
    $marker = $text | ConvertFrom-Json -ErrorAction Stop
    $expected = [ordered]@{
        schemaVersion = 2
        instanceName = $instanceName
        baseId = [string]$intent.baseId
        profile = [string]$intent.profile
        cloudInstanceId = $ExpectedCloudInstanceId
        provisioningProfile = [string]$profile.Name
        provisioningVersion = [int]$profile.Version
        provisioningDigest = [string]$profile.Digest
        provisioningState = 'complete'
    }
    foreach ($field in $expected.Keys) {
        if (@($marker.PSObject.Properties.Name) -cnotcontains $field -or $marker.$field -cne $expected[$field]) {
            throw "Real coding-ready marker disagrees with requested '$field'."
        }
    }
    if (@($marker.PSObject.Properties.Name).Count -ne $expected.Count) {
        throw 'Real coding-ready marker has unexpected fields.'
    }
    return $text.Trim()
}

function Invoke-EzDarkFactory009Revalidation {
    $access = Get-EzDarkFactorySshAccessState -Root $Root -InstanceName $instanceName
    return & $module {
        param($rootValue, $nameValue, $intentValue, $accessValue, $identityValue, $toolingValue)
        Wait-EzDarkFactorySshReady -Root $rootValue -InstanceName $nameValue -Intent $intentValue -Access $accessValue -Identity $identityValue -Tooling $toolingValue -TimeoutSeconds 120
    } $Root $instanceName $intent $access $controller $tooling
}

try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'This qualification requires a Windows host and the reviewed Windows QEMU runtime.'
    }
    $tooling = Get-EzDarkFactoryOpenSshTools
    if (-not $tooling.Valid) { throw "Real coding-profile qualification requires Windows OpenSSH. $($tooling.Reason)" }
    $profile = Get-EzDarkFactoryCodingProfile -Root $Root
    if ($profile.Name -cne 'coding-default' -or [int]$profile.Version -ne 1) {
        throw 'EDF-009 qualification expects the reviewed coding-default version 1 profile.'
    }

    Write-Host ('EDF009_STARTED_AT=' + [DateTime]::UtcNow.ToString('o'))
    Write-Host 'EDF009_ACCELERATOR=tcg'
    Write-Host 'EDF009_WHPX_EXECUTION=SKIP: GitHub-hosted qualification uses explicit TCG; no WHPX runtime PASS is claimed.'
    $bootstrap = Install-EzDarkFactoryQemuRuntime -Root $Root
    $source = Invoke-EzDarkFactorySourceImageAcquire -Root $Root
    Write-Host ('EDF009_REAL_QEMU=' + $bootstrap.version)
    Write-Host ('EDF009_REAL_SOURCE_SHA256=' + $source.sha256)

    # Preserve the accepted base and first-boot deadlines. The workflow's larger
    # enclosing bound also covers a second boot and the new negative checks.
    $base = Invoke-EzDarkFactoryBaseBuild -Root $Root -Accelerator tcg -BuildTimeoutSeconds 2400
    $acceptedBase = Test-EzDarkFactoryPreparedBase -Root $Root -BaseId $base.baseId
    if ($acceptedBase.Manifest.build.accelerator -cne 'tcg') {
        throw 'Prepared-base qualification did not record explicit TCG execution.'
    }
    $created = New-EzDarkFactoryManagedInstance -Root $Root -InstanceName $instanceName -BaseId $base.baseId -Profile light
    if ($created.chainDepth -ne 1) { throw 'Real coding instance violated the one-level backing-chain contract.' }
    $intent = Get-EzDarkFactoryInstanceIntent -Root $Root -InstanceName $instanceName
    if ($intent.provisioningProfile -cne 'coding-default' -or [int]$intent.provisioningVersion -ne 1) {
        throw 'Normal instance creation did not persist coding-default version 1.'
    }
    $controller = Get-EzDarkFactoryControllerSshIdentity -Root $Root -Tooling $tooling

    Write-Host 'EDF009_STEP=first_boot'
    # Set before start so a readiness failure still attempts identity-checked
    # graceful shutdown rather than leaving its known QEMU process unattended.
    $started = $true
    $ready = Start-EzDarkFactoryReadyInstance -Root $Root -InstanceName $instanceName -Accelerator tcg -ReadyTimeoutSeconds 900
    if ($ready.state -cne 'READY' -or $ready.sshHost -cne '127.0.0.1' -or $ready.accelerator -cne 'tcg') {
        throw 'Fresh instance did not reach explicit TCG, localhost-only READY.'
    }
    $access = Get-EzDarkFactorySshAccessState -Root $Root -InstanceName $instanceName -RequireReady
    if ($access.schemaVersion -ne 2 -or $access.provisioningProfile -cne 'coding-default' -or [int]$access.provisioningVersion -ne 1 -or $access.provisioningDigest -cne $profile.Digest) {
        throw 'READY access state did not preserve the requested coding-profile schema, version and digest.'
    }
    $firstLaunchId = [string]$access.launchId
    $cloudInstanceId = [string]$access.cloudInstanceId
    $markerBefore = Assert-EzDarkFactory009Marker -ExpectedCloudInstanceId $cloudInstanceId
    Write-Host 'EDF009_REAL_VERSIONED_CODING_READY=PASS'

    Write-Host 'EDF009_STEP=tooling_account_workspace'
    $guestChecks = @'
set -eu
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
test "$(id -un)" = coder
test "$HOME" = /home/coder
test "$(getent passwd coder | cut -d: -f6)" = /home/coder
test "$(stat -c '%U:%G' /home/coder)" = coder:coder
test -d /home/coder/workspace
test "$(stat -c '%U:%G' /home/coder/workspace)" = coder:coder
test -w /home/coder/workspace
test -s /home/coder/.ssh/authorized_keys
test -s /etc/ssl/certs/ca-certificates.crt
sudo -n true
test "$(sudo -n passwd -S coder | awk '{print $2}')" = L
test "$(sudo -n passwd -S root | awk '{print $2}')" = L
ssh_config="$(sudo -n /usr/sbin/sshd -T -C user=coder,host=localhost,addr=127.0.0.1)"
printf '%s\n' "$ssh_config" | grep -Fx 'passwordauthentication no'
printf '%s\n' "$ssh_config" | grep -Fx 'kbdinteractiveauthentication no'
printf '%s\n' "$ssh_config" | grep -Fx 'permitrootlogin no'
printf '%s\n' "$ssh_config" | grep -Fx 'pubkeyauthentication yes'
for tool in git gcc g++ make cmake ninja python3 pip3 curl wget jq rg unzip zip rsync tmux ssh scp ssh-keygen sshd; do
    command -v "$tool" >/dev/null
done
work="$(mktemp -d /home/coder/workspace/.ezdarkfactory009-tools.XXXXXX)"
trap 'rm -rf "$work"' EXIT HUP INT TERM
python3 -m venv "$work/venv"
"$work/venv/bin/python" -c 'import sys; assert sys.prefix != sys.base_prefix'
"$work/venv/bin/python" -m pip --version
printf '#include <stdio.h>\nint main(void) { puts("EDF009_C_OK"); return 0; }\n' > "$work/main.c"
gcc -Wall -Wextra -Werror "$work/main.c" -o "$work/c-check"
test "$("$work/c-check")" = EDF009_C_OK
printf '#include <iostream>\nint main() { std::cout << "EDF009_CPP_OK"; }\n' > "$work/main.cpp"
g++ -Wall -Wextra -Werror "$work/main.cpp" -o "$work/cpp-check"
test "$("$work/cpp-check")" = EDF009_CPP_OK
printf '%s\n' '__EDF009_SENTINEL__' > /home/coder/workspace/ezdarkfactory009-persistence.txt
printf '%s\n' 'EDF009_GUEST_CHECKS=PASS'
'@
    $guestOutput = Invoke-EzDarkFactory009Guest -Script ($guestChecks.Replace('__EDF009_SENTINEL__', $sentinel))
    if ($guestOutput -notmatch '(?m)^EDF009_GUEST_CHECKS=PASS\r?$') { throw 'Guest tooling/account/workspace evidence was incomplete.' }
    Write-Host 'EDF009_REAL_REQUIRED_TOOLS_VENV_COMPILERS=PASS'
    Write-Host 'EDF009_REAL_CODER_PASSWORD_SSH_SUDO_POLICY=PASS'
    Write-Host 'EDF009_REAL_WORKSPACE_OWNERSHIP=PASS'

    Write-Host 'EDF009_STEP=idempotent_provisioning'
    foreach ($iteration in @(1, 2)) {
        $null = Invoke-EzDarkFactory009Guest -Script 'sudo -n /usr/local/sbin/ezdarkfactory-coding-profile provision'
        $markerAfter = Assert-EzDarkFactory009Marker -ExpectedCloudInstanceId $cloudInstanceId
        if ($markerAfter -cne $markerBefore) { throw "Provisioning iteration $iteration changed the stable coding-ready identity." }
        $persisted = Invoke-EzDarkFactory009Guest -Script 'cat /home/coder/workspace/ezdarkfactory009-persistence.txt' -TimeoutSeconds 60
        if ($persisted.Trim() -cne $sentinel) { throw "Provisioning iteration $iteration changed existing workspace content." }
    }
    Write-Host 'EDF009_REAL_IDEMPOTENT_PROVISIONING=PASS'

    $stopped = Stop-EzDarkFactoryInstance -Root $Root -InstanceName $instanceName -ShutdownTimeoutSeconds 120
    if ($stopped.state -cne 'STOPPED') { throw 'Initial guest shutdown was not clean.' }
    $started = $false
    Write-Host 'EDF009_STEP=restart_persistence'
    $started = $true
    $restarted = Start-EzDarkFactoryReadyInstance -Root $Root -InstanceName $instanceName -Accelerator tcg -ReadyTimeoutSeconds 900
    if ($restarted.state -cne 'READY') { throw 'Restarted coding guest did not reach READY.' }
    $restartedAccess = Get-EzDarkFactorySshAccessState -Root $Root -InstanceName $instanceName -RequireReady
    if ($restartedAccess.launchId -ceq $firstLaunchId -or $restartedAccess.cloudInstanceId -cne $cloudInstanceId -or [int]$restartedAccess.sshPort -ne [int]$intent.sshPort) {
        throw 'Restart did not preserve stable guest identity/SSH reservation while recording a fresh QEMU launch.'
    }
    $markerAfterRestart = Assert-EzDarkFactory009Marker -ExpectedCloudInstanceId $cloudInstanceId
    if ($markerAfterRestart -cne $markerBefore) { throw 'Restart changed the versioned guest identity.' }
    $persisted = Invoke-EzDarkFactory009Guest -Script 'cat /home/coder/workspace/ezdarkfactory009-persistence.txt' -TimeoutSeconds 60
    if ($persisted.Trim() -cne $sentinel) { throw 'Restart lost mutable workspace content.' }
    Write-Host 'EDF009_REAL_RESTART_PERSISTENCE=PASS'

    Write-Host 'EDF009_STEP=missing_tool_refusal'
    $knownHostsPath = (Get-EzDarkFactorySshPaths -Root $Root -InstanceName $instanceName).InstanceKnownHosts
    $knownHostsBefore = (Get-FileHash -LiteralPath $knownHostsPath -Algorithm SHA256).Hash
    $missingToolHidden = $true
    $null = Invoke-EzDarkFactory009Guest -Script "sudo -n sh -ec 'test -x /usr/bin/rg; test ! -e /usr/bin/rg.ezdarkfactory009-disabled; mv /usr/bin/rg /usr/bin/rg.ezdarkfactory009-disabled'" -TimeoutSeconds 60
    $rejection = $null
    try { $null = Invoke-EzDarkFactory009Revalidation }
    catch { $rejection = $_.Exception.Message }
    if ([string]::IsNullOrWhiteSpace($rejection) -or $rejection -notmatch 'profile|provision' -or $rejection -match 'did not reach.*within|timed out|timeout') {
        throw "Removing a required tool did not cause an explicit profile-readiness rejection: $rejection"
    }
    $failedAccess = Get-EzDarkFactorySshAccessState -Root $Root -InstanceName $instanceName
    if ($failedAccess.state -ceq 'READY' -or -not [string]::IsNullOrWhiteSpace([string]$failedAccess.readyAt)) {
        throw 'Failed live profile validation retained stale READY access state.'
    }
    if ((Get-FileHash -LiteralPath $knownHostsPath -Algorithm SHA256).Hash -cne $knownHostsBefore) {
        throw 'Failed profile readiness changed managed SSH trust.'
    }
    $null = Invoke-EzDarkFactory009Guest -WhileNotReady -Script 'test ! -e /var/lib/ezdarkfactory/ready.json' -TimeoutSeconds 60
    $execRefused = $false
    try { $null = Invoke-EzDarkFactoryExec -Root $Root -InstanceName $instanceName -Command @('true') -TimeoutSeconds 60 }
    catch {
        if ($_.Exception.Message -notmatch 'has not reached.*READY') { throw }
        $execRefused = $true
    }
    if (-not $execRefused) { throw 'Managed exec remained usable after coding readiness was invalidated.' }
    Write-Host ('EDF009_EXPECTED_MISSING_TOOL_REJECTION=' + $rejection)
    Write-Host 'EDF009_REAL_MISSING_TOOL_REFUSES_READY=PASS'
    Write-Host 'EDF009_REAL_STALE_READY_AND_TRUST_PROTECTION=PASS'

    $null = Invoke-EzDarkFactory009Guest -WhileNotReady -Script "sudo -n sh -ec 'test ! -e /usr/bin/rg; test -x /usr/bin/rg.ezdarkfactory009-disabled; mv /usr/bin/rg.ezdarkfactory009-disabled /usr/bin/rg'" -TimeoutSeconds 60
    $missingToolHidden = $false
    $null = Invoke-EzDarkFactory009Guest -WhileNotReady -Script 'sudo -n /usr/local/sbin/ezdarkfactory-coding-profile provision'
    $recovered = Invoke-EzDarkFactory009Revalidation
    if ($recovered.state -cne 'READY') { throw 'Restored coding profile failed successful revalidation.' }
    $recoveredMarker = Assert-EzDarkFactory009Marker -ExpectedCloudInstanceId $cloudInstanceId
    if ($recoveredMarker -cne $markerBefore) { throw 'Profile recovery changed the stable guest identity.' }
    Write-Host 'EDF009_REAL_PROFILE_RECOVERY=PASS'

    $stopped = Stop-EzDarkFactoryInstance -Root $Root -InstanceName $instanceName -ShutdownTimeoutSeconds 120
    if ($stopped.state -cne 'STOPPED') { throw 'Qualified coding guest did not shut down cleanly.' }
    $started = $false
    Write-Host ('EDF009_REAL_BASE=' + $base.baseId)
    Write-Host ('EDF009_REAL_PROFILE=' + $profile.Name + ':' + $profile.Version)
    Write-Host ('EDF009_REAL_PROFILE_SHA256=' + $profile.Digest)
    Write-Host 'EDF009_REAL_GRACEFUL_STOP=PASS'
    Write-Host ('EDF009_COMPLETED_AT=' + [DateTime]::UtcNow.ToString('o'))
}
catch {
    Write-Host 'EDF009_REAL_DIAGNOSTICS_BEGIN'
    try {
        $runtimePaths = Get-EzDarkFactoryInstanceRuntimePaths -Root $Root -InstanceName $instanceName
        foreach ($path in @($runtimePaths.Runtime, (Join-Path $runtimePaths.Directory 'access.json'))) {
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                Write-Host ('STATE_FILE=' + $path)
                Get-Content -LiteralPath $path -Raw | Write-Host
            }
        }
        if (Test-Path -LiteralPath $runtimePaths.Logs -PathType Container) {
            Get-ChildItem -LiteralPath $runtimePaths.Logs -File -ErrorAction SilentlyContinue | ForEach-Object {
                Write-Host ('LOG_TAIL=' + $_.FullName)
                Get-Content -LiteralPath $_.FullName -Tail 120 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
            }
        }
    }
    catch { Write-Host ('DIAGNOSTIC_ERROR=' + $_.Exception.Message) }
    Write-Host 'EDF009_REAL_DIAGNOSTICS_END'
    throw
}
finally {
    if ($missingToolHidden -and $started) {
        try {
            $null = Invoke-EzDarkFactory009Guest -WhileNotReady -Script "sudo -n sh -ec 'test ! -e /usr/bin/rg; test -x /usr/bin/rg.ezdarkfactory009-disabled; mv /usr/bin/rg.ezdarkfactory009-disabled /usr/bin/rg'" -TimeoutSeconds 30
        }
        catch { Write-Host ('EDF009_TOOL_RESTORE_ERROR=' + $_.Exception.Message) }
    }
    if ($started) {
        try { $null = Stop-EzDarkFactoryInstance -Root $Root -InstanceName $instanceName -ShutdownTimeoutSeconds 30 }
        catch { Write-Host ('EDF009_GRACEFUL_CLEANUP_ERROR=' + $_.Exception.Message) }
    }
}
