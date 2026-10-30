function Set-EzDarkFactorySnapshotFixtureInteger {
    param([byte[]]$Bytes, [int]$Offset, [int]$Length, [long]$Value)
    for ($index = $Length - 1; $index -ge 0; $index--) {
        $Bytes[$Offset + $index] = [byte]($Value -band 255)
        $Value = $Value -shr 8
    }
}

function New-EzDarkFactorySnapshotHeaderBoundaryStream {
    param([byte[]]$Header, [long]$ReportedLength, [int]$ReadChunk = 17)
    if ($null -eq ('EzDarkFactorySnapshotHeaderBoundaryStream' -as [type])) {
        # A seekable stream models a multi-GiB image while keeping only its
        # first cluster in memory. Short reads exercise the real parser loops.
        Add-Type -TypeDefinition @'
using System;
using System.IO;
public sealed class EzDarkFactorySnapshotHeaderBoundaryStream : MemoryStream
{
    private readonly long reportedLength;
    private readonly int readChunk;
    public long BytesRead { get; private set; }
    public int ReadCalls { get; private set; }
    public int LargestReadRequest { get; private set; }
    public EzDarkFactorySnapshotHeaderBoundaryStream(byte[] header, long length, int chunk)
        : base(header, false)
    {
        reportedLength = length;
        readChunk = chunk;
    }
    public override long Length { get { return reportedLength; } }
    public override int Read(byte[] buffer, int offset, int count)
    {
        ReadCalls++;
        LargestReadRequest = Math.Max(LargestReadRequest, count);
        int read = base.Read(buffer, offset, Math.Min(count, readChunk));
        BytesRead += read;
        return read;
    }
}
'@ -ErrorAction Stop
    }
    return [EzDarkFactorySnapshotHeaderBoundaryStream]::new($Header, $ReportedLength, $ReadChunk)
}

function Write-EzDarkFactorySnapshotFixtureImage {
    param(
        [string]$Path, [string]$Backing = '', [string]$Data = '', [long]$VirtualSize = 67108864,
        [scriptblock]$IntegerWriter = ${function:Set-EzDarkFactorySnapshotFixtureInteger}
    )
    $header = New-Object byte[] 512
    $header[0] = 0x51; $header[1] = 0x46; $header[2] = 0x49; $header[3] = 0xfb
    & $IntegerWriter $header 4 4 3
    & $IntegerWriter $header 20 4 9
    & $IntegerWriter $header 24 8 $VirtualSize
    & $IntegerWriter $header 96 4 4
    & $IntegerWriter $header 100 4 104
    if ($Backing) {
        $backingBytes = [Text.Encoding]::UTF8.GetBytes($Backing)
        & $IntegerWriter $header 8 8 128
        & $IntegerWriter $header 16 4 $backingBytes.Length
        & $IntegerWriter $header 104 4 0xe2792acaL
        & $IntegerWriter $header 108 4 5
        [Array]::Copy([Text.Encoding]::ASCII.GetBytes('qcow2'), 0, $header, 112, 5)
        [Array]::Copy($backingBytes, 0, $header, 128, $backingBytes.Length)
    }
    $payload = [Text.Encoding]::UTF8.GetBytes(([pscustomobject]@{ data = $Data; backing = $Backing; size = $VirtualSize } | ConvertTo-Json -Compress))
    $image = New-Object byte[] (512 + $payload.Length)
    [Array]::Copy($header, 0, $image, 0, $header.Length)
    [Array]::Copy($payload, 0, $image, 512, $payload.Length)
    [IO.File]::WriteAllBytes($Path, $image)
}

function Get-EzDarkFactorySnapshotFixturePayload {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    return ([Text.Encoding]::UTF8.GetString($bytes, 512, $bytes.Length - 512) | ConvertFrom-Json -ErrorAction Stop)
}

function New-EzDarkFactorySnapshotFixture {
    param([switch]$WithoutInstance)
    $baseFixture = New-EzDarkFactoryBaseBuildFixture
    $root = $baseFixture.Root
    $state = [pscustomobject]@{ Calls = New-Object 'System.Collections.Generic.List[object]'; Mode = 'normal' }
    $runnerState = $state
    # GetNewClosure captures variables, not functions defined in Run-Tests.ps1's
    # script scope. Carry each helper explicitly across the module callback so
    # the fixture also works through Invoke-CiCheck.ps1's nested script entry.
    $runnerPayloadReader = ${function:Get-EzDarkFactorySnapshotFixturePayload}
    $runnerImageWriter = ${function:Write-EzDarkFactorySnapshotFixtureImage}
    $runnerIntegerWriter = ${function:Set-EzDarkFactorySnapshotFixtureInteger}
    $runner = {
        param($argumentList)
        $arguments = @($argumentList)
        $runnerState.Calls.Add([string[]]$arguments)
        $command = $arguments[0]
        $path = [IO.Path]::GetFullPath($arguments[-1])
        if ($command -ceq 'create') {
            $backing = $arguments[[Array]::IndexOf($arguments, '-b') + 1]
            & $runnerImageWriter -Path $path -Backing $backing -IntegerWriter $runnerIntegerWriter
            return [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
        }
        if ($command -ceq 'convert') {
            if ($runnerState.Mode -ceq 'fail-convert') {
                [IO.File]::WriteAllText($path, 'partial conversion')
                return [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'fixture interrupted conversion' }
            }
            $source = [IO.Path]::GetFullPath($arguments[-2])
            $payload = & $runnerPayloadReader -Path $source
            $visibleData = $payload.data
            if (-not $visibleData -and $payload.backing) {
                $back = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($source)) $payload.backing))
                $visibleData = (& $runnerPayloadReader -Path $back).data
            }
            $size = if ($runnerState.Mode -ceq 'wrong-convert-size') { 33554432 } else { [long]$payload.size }
            $backing = if ($runnerState.Mode -ceq 'converted-backing') { '../outside.qcow2' } else { '' }
            & $runnerImageWriter -Path $path -Data $visibleData -VirtualSize $size -Backing $backing -IntegerWriter $runnerIntegerWriter
            if ($runnerState.Mode -ceq 'source-changes') {
                [IO.File]::AppendAllText($source, 'changed-during-convert')
            }
            return [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
        }
        if ($command -ceq 'check') {
            $report = if ($runnerState.Mode -ceq 'bad-check') { '{"format":"qcow2","check-errors":0,"corruptions":1}' }
                elseif ($runnerState.Mode -ceq 'bad-check-type') { '{"format":"qcow2","check-errors":"0"}' }
                else { '{"format":"qcow2","check-errors":0,"corruptions":0,"leaks":0}' }
            return [pscustomobject]@{ ExitCode = 0; StdOut = $report; StdErr = '' }
        }
        if ($command -ceq 'info') {
            if ($runnerState.Mode -ceq 'malformed-info') { return [pscustomobject]@{ ExitCode = 0; StdOut = 'not-json'; StdErr = '' } }
            $payload = & $runnerPayloadReader -Path $path
            $info = [ordered]@{ filename = $path; format = 'qcow2'; 'virtual-size' = [long]$payload.size }
            if ($payload.backing) {
                $info['backing-filename'] = $payload.backing
                $info['backing-filename-format'] = 'qcow2'
            }
            elseif ($runnerState.Mode -ceq 'info-data-file') { $info['data-file'] = '/external/payload.raw' }
            if ($arguments -ccontains '--backing-chain') {
                $back = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($path)) $payload.backing))
                $chain = @([pscustomobject]$info, [pscustomobject]@{ filename = $back; format = 'qcow2'; 'virtual-size' = [long]$payload.size })
                return [pscustomobject]@{ ExitCode = 0; StdOut = ($chain | ConvertTo-Json -Compress); StdErr = '' }
            }
            return [pscustomobject]@{ ExitCode = 0; StdOut = ([pscustomobject]$info | ConvertTo-Json -Compress); StdErr = '' }
        }
        return [pscustomobject]@{ ExitCode = 90; StdOut = ''; StdErr = "Unexpected snapshot fixture operation $command" }
    }.GetNewClosure()
    $inputPath = Join-Path $root 'incoming standalone.qcow2'
    Write-EzDarkFactorySnapshotFixtureImage -Path $inputPath -Data 'baseline guest bytes'
    $safe = New-EzDarkFactoryStorageLifecycleGuard -State proven-safe -Source 'snapshot fixture has no QEMU owner'
    $fixture = [pscustomobject]@{
        Root = $root; Paths = $baseFixture.Paths; BaseFixture = $baseFixture; InputPath = $inputPath
        Runner = $runner; QemuStatusProvider = $baseFixture.QemuStatusProvider; State = $state
        SafeGuard = $safe; Base = $null; Intent = $null; Disk = $null
    }
    if (-not $WithoutInstance) {
        $fixture.Base = Import-EzDarkFactoryStandaloneBase -Root $root -ImagePath $inputPath -QemuImgRunner $runner -QemuStatusProvider $fixture.QemuStatusProvider
        $fixture.Intent = New-EzDarkFactoryInstanceIntent -Root $root -InstanceName 'snapshot-source' -BaseId $fixture.Base.BaseId -QemuImgRunner $runner
        $overlay = New-EzDarkFactoryInstanceOverlay -Root $root -InstanceName $fixture.Intent.name -BaseId $fixture.Base.BaseId -LifecycleGuard $safe -QemuImgRunner $runner
        $fixture.Disk = $overlay.Disk
        Write-EzDarkFactorySnapshotFixtureImage -Path $fixture.Disk -Backing $overlay.BackingReference -Data 'source workspace sentinel and synthetic auth state'
    }
    $state.Calls.Clear()
    return $fixture
}

function Remove-EzDarkFactorySnapshotFixture {
    param([object]$Fixture)
    if ($null -ne $Fixture) { Remove-EzDarkFactoryBaseBuildFixture $Fixture.BaseFixture }
}

Add-EzDarkFactoryTest -Name 'Snapshots: QCOW2 header accepts only bounded supported standalone or exact managed backing' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture -WithoutInstance
    try {
        $header = Test-EzDarkFactoryQcow2Header -Path $fixture.InputPath
        Assert-EzDarkFactoryEqual $header.VirtualSizeBytes 67108864
        Assert-EzDarkFactoryEqual $header.BackingReference ''
        Assert-EzDarkFactoryEqual $header.Version 3
        $v2 = [IO.File]::ReadAllBytes($fixture.InputPath)
        Set-EzDarkFactorySnapshotFixtureInteger $v2 4 4 2
        for ($index = 72; $index -lt 112; $index++) { $v2[$index] = 0 }
        [IO.File]::WriteAllBytes($fixture.InputPath, $v2)
        Assert-EzDarkFactoryEqual (Test-EzDarkFactoryQcow2Header -Path $fixture.InputPath).Version 2
        Write-EzDarkFactorySnapshotFixtureImage -Path $fixture.InputPath -Backing '../../bases/base-known/base.qcow2'
        Assert-EzDarkFactoryThrows { Test-EzDarkFactoryQcow2Header -Path $fixture.InputPath } -MessagePattern 'no backing file' | Out-Null
        Assert-EzDarkFactoryThrows { Test-EzDarkFactoryQcow2Header -Path $fixture.InputPath -ExpectedBacking '../../bases/wrong/base.qcow2' } -MessagePattern 'does not exactly match' | Out-Null
        Assert-EzDarkFactoryEqual (Test-EzDarkFactoryQcow2Header -Path $fixture.InputPath -ExpectedBacking '../../bases/base-known/base.qcow2').BackingReference '../../bases/base-known/base.qcow2'
        Assert-EzDarkFactoryEqual $fixture.State.Calls.Count 0
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Snapshots: image lengths above 2 GiB retain bounded first-cluster reads' -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'large QCOW2 header stream'
    $module = Get-Module EzDarkFactory
    try {
        $path = Join-Path $root 'small header fixture.qcow2'
        foreach ($backing in @('', '../../bases/base-known/base.qcow2')) {
            Write-EzDarkFactorySnapshotFixtureImage -Path $path -Backing $backing -VirtualSize 17179869184L
            $fixtureBytes = [IO.File]::ReadAllBytes($path)
            foreach ($case in @(
                @{ Length = 2147483647L; ClusterBits = 9; ReadChunk = 17 },
                @{ Length = 2147483648L; ClusterBits = 9; ReadChunk = 17 },
                @{ Length = 2736259072L; ClusterBits = 16; ReadChunk = 4093 },
                @{ Length = [long]::MaxValue; ClusterBits = 9; ReadChunk = 17 },
                @{ Length = [long]::MaxValue; ClusterBits = 21; ReadChunk = 65521 }
            )) {
                $clusterSize = 1 -shl $case.ClusterBits
                $headerBytes = New-Object byte[] $clusterSize
                [Array]::Copy($fixtureBytes, 0, $headerBytes, 0, 512)
                Set-EzDarkFactorySnapshotFixtureInteger $headerBytes 20 4 $case.ClusterBits
                $stream = New-EzDarkFactorySnapshotHeaderBoundaryStream -Header $headerBytes -ReportedLength $case.Length -ReadChunk $case.ReadChunk
                try {
                    $header = & $module { param($inputStream, $expected) Read-EzDarkFactoryQcow2Header -Stream $inputStream -ExpectedBacking $expected } $stream $backing
                    Assert-EzDarkFactoryEqual $header.Version 3
                    Assert-EzDarkFactoryEqual $header.VirtualSizeBytes 17179869184L
                    Assert-EzDarkFactoryEqual $header.BackingReference $backing
                    Assert-EzDarkFactoryEqual $header.ClusterSizeBytes $clusterSize
                    Assert-EzDarkFactoryEqual $stream.BytesRead (104L + $clusterSize) -Message 'Large logical images must read only the prefix and one bounded cluster.'
                    Assert-EzDarkFactoryTrue ($stream.LargestReadRequest -le $clusterSize)
                    Assert-EzDarkFactoryTrue ($stream.ReadCalls -gt 2) -Message 'The fixture must exercise partial stream reads.'
                }
                finally { $stream.Dispose() }
            }
        }
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Snapshots: large stream lengths preserve dependency bounds and truncated-read refusal' -ScriptBlock {
    $root = New-EzDarkFactoryTestDirectory -Prefix 'unsafe large QCOW2 header stream'
    $module = Get-Module EzDarkFactory
    try {
        $path = Join-Path $root 'small unsafe header fixture.qcow2'
        foreach ($case in @('external-backing', 'backing-offset', 'extension-length', 'truncated-cluster')) {
            $backing = if ($case -eq 'external-backing' -or $case -eq 'backing-offset') { '../outside.qcow2' } else { '' }
            Write-EzDarkFactorySnapshotFixtureImage -Path $path -Backing $backing
            $fixtureBytes = [IO.File]::ReadAllBytes($path)
            $headerBytes = New-Object byte[] $(if ($case -eq 'truncated-cluster') { 256 } else { 512 })
            [Array]::Copy($fixtureBytes, 0, $headerBytes, 0, $headerBytes.Length)
            $expectedBacking = ''
            $pattern = 'no backing file'
            if ($case -eq 'backing-offset') {
                Set-EzDarkFactorySnapshotFixtureInteger $headerBytes 8 8 2736259072L
                $expectedBacking = $backing
                $pattern = 'out-of-cluster bounds'
            }
            elseif ($case -eq 'extension-length') {
                Set-EzDarkFactorySnapshotFixtureInteger $headerBytes 104 4 0x6803f857L
                Set-EzDarkFactorySnapshotFixtureInteger $headerBytes 108 4 0xffffffffL
                $pattern = 'exceeds its bounded first-cluster'
            }
            elseif ($case -eq 'truncated-cluster') { $pattern = 'first-cluster read ended unexpectedly' }
            $stream = New-EzDarkFactorySnapshotHeaderBoundaryStream -Header $headerBytes -ReportedLength 2736259072L
            try {
                Assert-EzDarkFactoryThrows {
                    & $module { param($inputStream, $expected) Read-EzDarkFactoryQcow2Header -Stream $inputStream -ExpectedBacking $expected } $stream $expectedBacking
                } -MessagePattern $pattern | Out-Null
                Assert-EzDarkFactoryTrue ($stream.BytesRead -le 616)
                Assert-EzDarkFactoryTrue ($stream.LargestReadRequest -le 512)
            }
            finally { $stream.Dispose() }
        }
    }
    finally { Remove-EzDarkFactoryTestDirectory -Path $root }
}

Add-EzDarkFactoryTest -Name 'Snapshots: malformed or dependency-bearing imports refuse before any qemu-img call' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture -WithoutInstance
    try {
        $original = [IO.File]::ReadAllBytes($fixture.InputPath)
        $mutations = @(
            @{ offset = 0; length = 4; value = 0; pattern = 'magic' },
            @{ offset = 4; length = 4; value = 4; pattern = 'version' },
            @{ offset = 8; length = 8; value = 128; pattern = 'backing' },
            @{ offset = 16; length = 4; value = 5; pattern = 'backing' },
            @{ offset = 20; length = 4; value = 22; pattern = 'cluster' },
            @{ offset = 24; length = 8; value = 0; pattern = 'positive' },
            @{ offset = 32; length = 4; value = 2; pattern = 'Encrypted' },
            @{ offset = 60; length = 4; value = 1; pattern = 'snapshots' },
            @{ offset = 64; length = 8; value = 512; pattern = 'snapshots' },
            @{ offset = 72; length = 8; value = 1; pattern = 'incompatible' },
            @{ offset = 72; length = 8; value = 2; pattern = 'incompatible' },
            @{ offset = 72; length = 8; value = 4; pattern = 'external-data' },
            @{ offset = 72; length = 8; value = 32; pattern = 'incompatible' },
            @{ offset = 80; length = 8; value = 2; pattern = 'compatible' },
            @{ offset = 88; length = 8; value = 2; pattern = 'external-data' },
            @{ offset = 96; length = 4; value = 7; pattern = 'refcount' },
            @{ offset = 100; length = 4; value = 0xffffffffL; pattern = 'length|convert' },
            @{ offset = 104; length = 4; value = 0x44415441L; pattern = 'extension' },
            @{ offset = 104; length = 4; value = 0x0537be77L; pattern = 'extension' },
            @{ offset = 108; length = 4; value = 1; pattern = 'terminator' }
        )
        foreach ($mutation in $mutations) {
            $bytes = [byte[]]$original.Clone()
            Set-EzDarkFactorySnapshotFixtureInteger $bytes $mutation.offset $mutation.length $mutation.value
            [IO.File]::WriteAllBytes($fixture.InputPath, $bytes)
            $before = Get-EzDarkFactoryFileDigest -Path $fixture.InputPath -Algorithm SHA256
            Assert-EzDarkFactoryThrows {
                Import-EzDarkFactoryStandaloneBase -Root $fixture.Root -ImagePath $fixture.InputPath -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
            } -MessagePattern $mutation.pattern | Out-Null
            Assert-EzDarkFactoryEqual $fixture.State.Calls.Count 0 -Message 'Untrusted header must fail before QEMU receives the source or any staging path.'
            Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $fixture.InputPath -Algorithm SHA256) $before
        }
        [IO.File]::WriteAllBytes($fixture.InputPath, [byte[]]@(0x51, 0x46, 0x49, 0xfb))
        Assert-EzDarkFactoryThrows { Import-EzDarkFactoryStandaloneBase -Root $fixture.Root -ImagePath $fixture.InputPath -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider } -MessagePattern 'truncated' | Out-Null
        Assert-EzDarkFactoryEqual $fixture.State.Calls.Count 0
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Snapshots: extension bounds duplicates missing terminators and oversized uint64 fail closed' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture -WithoutInstance
    try {
        $original = [IO.File]::ReadAllBytes($fixture.InputPath)
        $bytes = [byte[]]$original.Clone()
        Set-EzDarkFactorySnapshotFixtureInteger $bytes 104 4 0x6803f857L
        Set-EzDarkFactorySnapshotFixtureInteger $bytes 108 4 0xffffffffL
        [IO.File]::WriteAllBytes($fixture.InputPath, $bytes)
        Assert-EzDarkFactoryThrows { Test-EzDarkFactoryQcow2Header -Path $fixture.InputPath } -MessagePattern 'exceeds' | Out-Null
        $bytes = [byte[]]$original.Clone()
        foreach ($offset in @(104, 160)) {
            Set-EzDarkFactorySnapshotFixtureInteger $bytes $offset 4 0x6803f857L
            Set-EzDarkFactorySnapshotFixtureInteger $bytes ($offset + 4) 4 48
        }
        [IO.File]::WriteAllBytes($fixture.InputPath, $bytes)
        Assert-EzDarkFactoryThrows { Test-EzDarkFactoryQcow2Header -Path $fixture.InputPath } -MessagePattern 'duplicate' | Out-Null
        $bytes = [byte[]]$original.Clone()
        $bytes[24] = 128
        [IO.File]::WriteAllBytes($fixture.InputPath, $bytes)
        Assert-EzDarkFactoryThrows { Test-EzDarkFactoryQcow2Header -Path $fixture.InputPath } -MessagePattern 'integer range' | Out-Null
        $bytes = [byte[]]$original.Clone()
        Set-EzDarkFactorySnapshotFixtureInteger $bytes 100 4 112
        $bytes[104] = 1
        [IO.File]::WriteAllBytes($fixture.InputPath, $bytes)
        Assert-EzDarkFactoryThrows { Test-EzDarkFactoryQcow2Header -Path $fixture.InputPath } -MessagePattern 'optional header' | Out-Null
        Write-EzDarkFactorySnapshotFixtureImage -Path $fixture.InputPath -Backing '../known.qcow2'
        $bytes = [IO.File]::ReadAllBytes($fixture.InputPath)
        Set-EzDarkFactorySnapshotFixtureInteger $bytes 8 8 120
        [Array]::Copy([Text.Encoding]::UTF8.GetBytes('../known.qcow2'), 0, $bytes, 120, 14)
        [IO.File]::WriteAllBytes($fixture.InputPath, $bytes)
        Assert-EzDarkFactoryThrows { Test-EzDarkFactoryQcow2Header -Path $fixture.InputPath -ExpectedBacking '../known.qcow2' } -MessagePattern 'terminator' | Out-Null
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Snapshots: imported symlink ancestors and oversized sidecars refuse before tool invocation' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture -WithoutInstance
    $link = $null
    $target = $null
    try {
        # PS5.1 resolves New-Item -Target through wildcard semantics. Keep the
        # bracketed source/link path, but use a literal-safe target with spaces.
        $target = New-EzDarkFactoryTestDirectory -Prefix 'snapshot junction target with spaces'
        Copy-Item -LiteralPath $fixture.InputPath -Destination (Join-Path $target 'disk.qcow2')
        $link = Join-Path $fixture.Root 'redirected imports'
        $itemType = if ($script:EzDarkFactoryIsWindowsHost) { 'Junction' } else { 'SymbolicLink' }
        $null = New-Item -ItemType $itemType -Path $link -Target $target -ErrorAction Stop
        Assert-EzDarkFactoryThrows {
            Import-EzDarkFactoryStandaloneBase -Root $fixture.Root -ImagePath (Join-Path $link 'disk.qcow2') -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
        } -MessagePattern 'reparse point' | Out-Null
        $sidecar = Join-Path $fixture.Root 'oversized-manifest.json'
        [IO.File]::WriteAllText($sidecar, ('x' * 65537))
        Assert-EzDarkFactoryThrows {
            Import-EzDarkFactoryStandaloneBase -Root $fixture.Root -ImagePath $fixture.InputPath -ManifestPath $sidecar -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
        } -MessagePattern '64 KiB' | Out-Null
        Assert-EzDarkFactoryEqual $fixture.State.Calls.Count 0
    }
    finally {
        if ($null -ne $link -and (Test-Path -LiteralPath $link)) { [IO.Directory]::Delete($link) }
        if ($null -ne $target) { Remove-EzDarkFactoryTestDirectory -Path $target }
        Remove-EzDarkFactorySnapshotFixture $fixture
    }
}

Add-EzDarkFactoryTest -Name 'Snapshots: import normalizes only a staged copy and publishes immutable sensitive provenance' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture -WithoutInstance
    try {
        $before = Get-EzDarkFactoryFileDigest -Path $fixture.InputPath -Algorithm SHA256
        $result = Import-EzDarkFactoryStandaloneBase -Root $fixture.Root -ImagePath $fixture.InputPath -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $fixture.InputPath -Algorithm SHA256) $before
        Assert-EzDarkFactoryEqual $result.Manifest.schemaVersion 2
        Assert-EzDarkFactoryEqual $result.Manifest.kind 'imported'
        Assert-EzDarkFactoryEqual $result.Manifest.source.filename 'incoming standalone.qcow2'
        Assert-EzDarkFactoryEqual $result.Manifest.source.imageSha256 $before
        Assert-EzDarkFactoryEqual $result.BaseId ('base-' + $result.Manifest.baseSha256)
        Assert-EzDarkFactoryEqual $result.OperationProvenance $result.Manifest
        Assert-EzDarkFactoryTrue $result.Manifest.sensitiveState
        Assert-EzDarkFactoryTrue $result.Manifest.guestIdentityResetRequired
        Assert-EzDarkFactoryTrue $result.ReadOnly
        Assert-EzDarkFactoryTrue (((Get-Item -LiteralPath $result.ManifestPath -Force).Attributes -band [IO.FileAttributes]::ReadOnly) -ne 0)
        Assert-EzDarkFactoryEqual (Test-EzDarkFactoryPreparedBase -Root $fixture.Root -BaseId $result.BaseId -QemuImgRunner $fixture.Runner).Manifest.baseSha256 (Get-EzDarkFactoryFileDigest -Path $result.Image -Algorithm SHA256)
        foreach ($call in $fixture.State.Calls) {
            Assert-EzDarkFactoryTrue ($call -cnotcontains $fixture.InputPath) -Message 'qemu-img must never open the untrusted caller-owned source path.'
            Assert-EzDarkFactoryTrue ($call -cnotcontains 'rebase' -and $call -cnotcontains 'commit' -and $call -cnotcontains '-r')
        }
        Assert-EzDarkFactoryEqual @(Get-ChildItem -LiteralPath $fixture.Paths.Bases -Directory -Filter '.snapshot-*' -Force).Count 0
        $manifestText = [IO.File]::ReadAllText($result.ManifestPath)
        Assert-EzDarkFactoryTrue (-not $manifestText.Contains($fixture.Root)) -Message 'Durable provenance must not retain the source root.'
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Snapshots: import refuses managed source paths and an already-open source file' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    $stream = $null
    try {
        Assert-EzDarkFactoryThrows { Import-EzDarkFactoryStandaloneBase -Root $fixture.Root -ImagePath $fixture.Base.Image -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider } -MessagePattern 'inside managed runtime' | Out-Null
        $stream = New-Object IO.FileStream($fixture.InputPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        Assert-EzDarkFactoryThrows { Import-EzDarkFactoryStandaloneBase -Root $fixture.Root -ImagePath $fixture.InputPath -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider } -MessagePattern 'another process|being used|IOException|permission|access' | Out-Null
        Assert-EzDarkFactoryEqual $fixture.State.Calls.Count 0
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        Remove-EzDarkFactorySnapshotFixture $fixture
    }
}

Add-EzDarkFactoryTest -Name 'Snapshots: omitted empty and whitespace optional manifest paths have identical import semantics' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture -WithoutInstance
    try {
        $first = Import-EzDarkFactoryStandaloneBase -Root $fixture.Root -ImagePath $fixture.InputPath -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
        foreach ($manifestPath in @('', '   ')) {
            $next = Import-EzDarkFactoryStandaloneBase -Root $fixture.Root -ImagePath $fixture.InputPath -ManifestPath $manifestPath -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
            Assert-EzDarkFactoryEqual $next.BaseId $first.BaseId
            Assert-EzDarkFactoryTrue $next.Reused
            Assert-EzDarkFactoryEqual $next.OperationProvenance.source.exportManifest $null
            Assert-EzDarkFactoryEqual $next.OperationProvenance.source.exportManifestSha256 ''
        }
        Assert-EzDarkFactoryThrows {
            Import-EzDarkFactoryStandaloneBase -Root $fixture.Root -ImagePath $fixture.InputPath -ManifestPath (Join-Path $fixture.Root 'missing-manifest.json') -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
        } -MessagePattern 'missing' | Out-Null
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Snapshots: derived state is standalone independent and carries source identity provenance' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    try {
        $before = Get-EzDarkFactoryFileDigest -Path $fixture.Disk -Algorithm SHA256
        $result = New-EzDarkFactoryDerivedBase -Root $fixture.Root -SourceIntent $fixture.Intent -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
        Assert-EzDarkFactoryEqual $result.Manifest.kind 'derived'
        Assert-EzDarkFactoryEqual $result.Manifest.source.instance.name $fixture.Intent.name
        Assert-EzDarkFactoryEqual $result.Manifest.source.instance.baseId $fixture.Intent.baseId
        Assert-EzDarkFactoryEqual $result.Manifest.source.overlaySha256 $before
        Assert-EzDarkFactoryEqual (Test-EzDarkFactoryQcow2Header -Path $result.Image).BackingReference ''
        Assert-EzDarkFactoryEqual (Get-EzDarkFactorySnapshotFixturePayload -Path $result.Image).data 'source workspace sentinel and synthetic auth state'
        $sourcePayload = Get-EzDarkFactorySnapshotFixturePayload -Path $fixture.Disk
        Write-EzDarkFactorySnapshotFixtureImage -Path $fixture.Disk -Backing $sourcePayload.backing -Data 'later source mutation'
        Assert-EzDarkFactoryEqual (Get-EzDarkFactorySnapshotFixturePayload -Path $result.Image).data 'source workspace sentinel and synthetic auth state'
        $clone = New-EzDarkFactoryInstanceOverlay -Root $fixture.Root -InstanceName 'independent-clone' -BaseId $result.BaseId -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner
        $chain = Test-EzDarkFactoryInstanceStorage -Root $fixture.Root -InstanceName 'independent-clone' -BaseId $result.BaseId -QemuImgRunner $fixture.Runner
        Assert-EzDarkFactoryEqual $chain.ChainDepth 1
        Assert-EzDarkFactoryEqual $chain.BasePath $result.Image
        Assert-EzDarkFactoryTrue ($chain.BasePath -cne $fixture.Disk)
        Assert-EzDarkFactoryEqual (Test-EzDarkFactoryQcow2Header -Path $clone.Disk -ExpectedBacking $clone.BackingReference).BackingReference $clone.BackingReference
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Snapshots: stopped export is atomic backing-independent and exactly digested' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    try {
        $destination = Join-Path $fixture.Root 'export with spaces'
        $before = Get-EzDarkFactoryFileDigest -Path $fixture.Disk -Algorithm SHA256
        $result = Export-EzDarkFactoryInstanceStorage -Root $fixture.Root -SourceIntent $fixture.Intent -LifecycleGuard $fixture.SafeGuard -DestinationDirectory $destination -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
        Assert-EzDarkFactoryEqual $result.Directory $destination
        Assert-EzDarkFactoryEqual $result.Manifest.imageSha256 (Get-EzDarkFactoryFileDigest -Path $result.Image -Algorithm SHA256)
        Assert-EzDarkFactoryEqual $result.Manifest.virtualSizeBytes 67108864
        Assert-EzDarkFactoryEqual $result.Manifest.source.instance.name $fixture.Intent.name
        Assert-EzDarkFactoryEqual (Test-EzDarkFactoryQcow2Header -Path $result.Image).BackingReference ''
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $fixture.Disk -Algorithm SHA256) $before
        Assert-EzDarkFactoryTrue $result.SensitiveState
        Assert-EzDarkFactoryTrue ($result.Warning -match 'credentials')
        Assert-EzDarkFactoryEqual @(Get-ChildItem -LiteralPath $destination -Force).Count 2
        Assert-EzDarkFactoryThrows {
            Export-EzDarkFactoryInstanceStorage -Root $fixture.Root -SourceIntent $fixture.Intent -LifecycleGuard $fixture.SafeGuard -DestinationDirectory $destination -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
        } -MessagePattern 'already exists' | Out-Null
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $result.Image -Algorithm SHA256) $result.Manifest.imageSha256
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Snapshots: explicit lifecycle guards reject running transitional absent and malformed evidence before tools' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    try {
        $guards = @($null)
        foreach ($state in @('running', 'starting', 'stopping', 'unknown')) { $guards += New-EzDarkFactoryStorageLifecycleGuard -State $state -Source 'negative guard' }
        $guards += [pscustomobject]@{ schemaVersion = 9; state = 'proven-safe'; source = 'invalid schema' }
        foreach ($guard in $guards) {
            Assert-EzDarkFactoryThrows {
                New-EzDarkFactoryDerivedBase -Root $fixture.Root -SourceIntent $fixture.Intent -LifecycleGuard $guard -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
            } -MessagePattern 'lifecycle|proven' | Out-Null
            Assert-EzDarkFactoryThrows {
                Export-EzDarkFactoryInstanceStorage -Root $fixture.Root -SourceIntent $fixture.Intent -LifecycleGuard $guard -DestinationDirectory (Join-Path $fixture.Root 'refused export') -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
            } -MessagePattern 'lifecycle|proven' | Out-Null
        }
        Assert-EzDarkFactoryEqual $fixture.State.Calls.Count 0
        Assert-EzDarkFactoryEqual @(Get-ChildItem -LiteralPath $fixture.Paths.Bases -Directory -Filter '.snapshot-*' -Force).Count 0
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Snapshots: managed source header mismatch refuses traversal before qemu-img info' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    try {
        Write-EzDarkFactorySnapshotFixtureImage -Path $fixture.Disk -Backing '../../../../outside.qcow2' -Data 'unsafe source header'
        Assert-EzDarkFactoryThrows {
            New-EzDarkFactoryDerivedBase -Root $fixture.Root -SourceIntent $fixture.Intent -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
        } -MessagePattern 'does not exactly match' | Out-Null
        Assert-EzDarkFactoryEqual $fixture.State.Calls.Count 0
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Snapshots: failed conversion and failed publication preserve source and recoverable candidate' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    try {
        $before = Get-EzDarkFactoryFileDigest -Path $fixture.Disk -Algorithm SHA256
        $existingBases = @(Get-ChildItem -LiteralPath $fixture.Paths.Bases -Directory -Filter 'base-*').Count
        $fixture.State.Mode = 'fail-convert'
        Assert-EzDarkFactoryThrows {
            New-EzDarkFactoryDerivedBase -Root $fixture.Root -SourceIntent $fixture.Intent -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
        } -MessagePattern 'recoverable staging' | Out-Null
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $fixture.Disk -Algorithm SHA256) $before
        Assert-EzDarkFactoryEqual @(Get-ChildItem -LiteralPath $fixture.Paths.Bases -Directory -Filter 'base-*').Count $existingBases
        $stage = @(Get-ChildItem -LiteralPath $fixture.Paths.Bases -Directory -Filter '.snapshot-*' -Force)[0].FullName
        Assert-EzDarkFactoryTrue (Test-Path -LiteralPath (Join-Path $stage 'failure.json'))
        Assert-EzDarkFactoryTrue (Test-Path -LiteralPath (Join-Path $stage 'standalone.qcow2'))
        $fixture.State.Mode = 'normal'
        $refuseMove = { param($source, $destination) throw [InvalidOperationException]::new('fixture publication refusal') }
        Assert-EzDarkFactoryThrows {
            Export-EzDarkFactoryInstanceStorage -Root $fixture.Root -SourceIntent $fixture.Intent -LifecycleGuard $fixture.SafeGuard -DestinationDirectory (Join-Path $fixture.Root 'failed export') -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider -DirectoryMover $refuseMove
        } -MessagePattern 'recoverable staging' | Out-Null
        Assert-EzDarkFactoryTrue (-not (Test-Path -LiteralPath (Join-Path $fixture.Root 'failed export')))
        $exportStage = @(Get-ChildItem -LiteralPath $fixture.Root -Directory -Filter '.ezdarkfactory-export-*' -Force)[0].FullName
        Assert-EzDarkFactoryTrue (Test-Path -LiteralPath (Join-Path $exportStage 'disk.qcow2'))
        Assert-EzDarkFactoryTrue (Test-Path -LiteralPath (Join-Path $exportStage 'manifest.json'))
        Assert-EzDarkFactoryTrue (Test-Path -LiteralPath (Join-Path $exportStage 'failure.json'))
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $fixture.Disk -Algorithm SHA256) $before
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Snapshots: conversion output size backing and integrity claims are independently checked' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture -WithoutInstance
    try {
        $before = Get-EzDarkFactoryFileDigest -Path $fixture.InputPath -Algorithm SHA256
        foreach ($mode in @('wrong-convert-size', 'converted-backing', 'bad-check', 'bad-check-type', 'malformed-info', 'info-data-file')) {
            $fixture.State.Mode = $mode
            Assert-EzDarkFactoryThrows {
                Import-EzDarkFactoryStandaloneBase -Root $fixture.Root -ImagePath $fixture.InputPath -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
            } -MessagePattern 'Import failed' | Out-Null
            Assert-EzDarkFactoryEqual @(Get-ChildItem -LiteralPath $fixture.Paths.Bases -Directory -Filter 'base-*').Count 0
            Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $fixture.InputPath -Algorithm SHA256) $before
        }
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Snapshots: export sidecar must match exact bytes size and strict sensitive provenance' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    try {
        $export = Export-EzDarkFactoryInstanceStorage -Root $fixture.Root -SourceIntent $fixture.Intent -LifecycleGuard $fixture.SafeGuard -DestinationDirectory (Join-Path $fixture.Root 'round trip export') -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
        $import = Import-EzDarkFactoryStandaloneBase -Root $fixture.Root -ImagePath $export.Image -ManifestPath $export.ManifestPath -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
        Assert-EzDarkFactoryEqual $import.Manifest.kind 'imported'
        Assert-EzDarkFactoryEqual $import.OperationProvenance.source.exportManifest.source.instance.name $fixture.Intent.name
        Assert-EzDarkFactoryEqual $import.OperationProvenance.source.exportManifestSha256 (Get-EzDarkFactoryFileDigest -Path $export.ManifestPath -Algorithm SHA256)
        $export.Manifest.imageSha256 = 'a' * 64
        Write-EzDarkFactoryJson -Path $export.ManifestPath -Value $export.Manifest
        $fixture.State.Calls.Clear()
        Assert-EzDarkFactoryThrows {
            Import-EzDarkFactoryStandaloneBase -Root $fixture.Root -ImagePath $export.Image -ManifestPath $export.ManifestPath -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
        } -MessagePattern 'do not match' | Out-Null
        Assert-EzDarkFactoryEqual $fixture.State.Calls.Count 0
        $export.Manifest.sensitiveState = $false
        Write-EzDarkFactoryJson -Path $export.ManifestPath -Value $export.Manifest
        Assert-EzDarkFactoryThrows {
            Import-EzDarkFactoryStandaloneBase -Root $fixture.Root -ImagePath $export.Image -ManifestPath $export.ManifestPath -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
        } -MessagePattern 'sensitiveState must be true' | Out-Null
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Snapshots: manifest schemas reject coercion unsafe kinds false cleanup claims and unknown fields' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    try {
        $json = $fixture.Base.OperationProvenance | ConvertTo-Json -Depth 32 -Compress
        $mutations = @(
            { param($m) $m.schemaVersion = '2' },
            { param($m) $m.virtualSizeBytes = '67108864' },
            { param($m) $m.virtualSizeBytes = $true },
            { param($m) $m.baseSha256 = @($m.baseSha256) },
            { param($m) $m.kind = 'prepared' },
            { param($m) $m.kind = @('imported') },
            { param($m) $m.sensitiveState = 'true' },
            { param($m) $m.guestIdentityResetRequired = $false },
            { param($m) $m.source.filename = 'C:\sensitive\disk.qcow2' },
            { param($m) $m.source.imageSha256 = @($m.source.imageSha256) },
            { param($m) $m.source.exportManifestSha256 = 'a' * 64 },
            { param($m) $m.qemu.qemuImgVersion = '' },
            { param($m) $m | Add-Member -NotePropertyName identityCleaned -NotePropertyValue $true }
        )
        foreach ($mutate in $mutations) {
            $manifest = & (Get-Module EzDarkFactory) { param($text) ConvertFrom-EzDarkFactoryJsonText -Text $text -SchemaVersion 2 -Description 'snapshot fixture' } $json
            & $mutate $manifest
            Assert-EzDarkFactoryThrows { Assert-EzDarkFactorySnapshotBaseManifest -Manifest $manifest } | Out-Null
        }
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Snapshots: byte-identical operations retain immutable base and return current provenance' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    try {
        $first = New-EzDarkFactoryDerivedBase -Root $fixture.Root -SourceIntent $fixture.Intent -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
        $manifestBefore = Get-EzDarkFactoryFileDigest -Path $first.ManifestPath -Algorithm SHA256
        $second = New-EzDarkFactoryDerivedBase -Root $fixture.Root -SourceIntent $fixture.Intent -LifecycleGuard $fixture.SafeGuard -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
        Assert-EzDarkFactoryTrue $second.Reused
        Assert-EzDarkFactoryEqual $second.BaseId $first.BaseId
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $first.ManifestPath -Algorithm SHA256) $manifestBefore
        Assert-EzDarkFactoryEqual $second.OperationProvenance.source.instance.name $fixture.Intent.name
        $export = Export-EzDarkFactoryInstanceStorage -Root $fixture.Root -SourceIntent $fixture.Intent -LifecycleGuard $fixture.SafeGuard -DestinationDirectory (Join-Path $fixture.Root 'deduplicated export') -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
        $import = Import-EzDarkFactoryStandaloneBase -Root $fixture.Root -ImagePath $export.Image -ManifestPath $export.ManifestPath -QemuImgRunner $fixture.Runner -QemuStatusProvider $fixture.QemuStatusProvider
        Assert-EzDarkFactoryTrue $import.Reused
        Assert-EzDarkFactoryEqual $import.Manifest.kind 'derived'
        Assert-EzDarkFactoryEqual $import.OperationProvenance.kind 'imported'
        Assert-EzDarkFactoryEqual $import.OperationProvenance.source.exportManifest.source.instance.name $fixture.Intent.name
        Assert-EzDarkFactoryEqual (Get-EzDarkFactoryFileDigest -Path $first.ManifestPath -Algorithm SHA256) $manifestBefore
    }
    finally { Remove-EzDarkFactorySnapshotFixture $fixture }
}

Add-EzDarkFactoryTest -Name 'Snapshots: sensitive-base validation remains relocation-safe and detects manifest mutation' -ScriptBlock {
    $fixture = New-EzDarkFactorySnapshotFixture
    $destination = $null
    try {
        $destination = New-EzDarkFactoryCheckoutFixture -Prefix 'snapshot relocated root B with spaces'
        Copy-Item -LiteralPath $fixture.Paths.Runtime -Destination $destination -Recurse -Force
        $accepted = Test-EzDarkFactoryPreparedBase -Root $destination -BaseId $fixture.Base.BaseId -QemuImgRunner $fixture.Runner
        Assert-EzDarkFactoryTrue ($accepted.Image.StartsWith($destination, [StringComparison]::Ordinal))
        Assert-EzDarkFactoryEqual $accepted.Manifest.baseSha256 $fixture.Base.Manifest.baseSha256
        $chain = Test-EzDarkFactoryInstanceStorage -Root $destination -InstanceName $fixture.Intent.name -BaseId $fixture.Intent.baseId -QemuImgRunner $fixture.Runner
        Assert-EzDarkFactoryEqual $chain.ChainDepth 1
        [IO.File]::SetAttributes($accepted.ManifestPath, ((Get-Item -LiteralPath $accepted.ManifestPath -Force).Attributes -band (-bnot [IO.FileAttributes]::ReadOnly)))
        Assert-EzDarkFactoryThrows { Test-EzDarkFactoryPreparedBase -Root $destination -BaseId $fixture.Base.BaseId -QemuImgRunner $fixture.Runner } -MessagePattern 'not marked read-only' | Out-Null
    }
    finally {
        if ($null -ne $destination) { Remove-EzDarkFactoryTestDirectory -Path $destination }
        Remove-EzDarkFactorySnapshotFixture $fixture
    }
}
