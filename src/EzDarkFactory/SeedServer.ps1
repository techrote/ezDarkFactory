function Start-EzDarkFactorySeedServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$UserData,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$MetaData,
        [ValidateRange(1, 86400)][int]$TimeoutSeconds = 1800
    )

    if ([Text.Encoding]::UTF8.GetByteCount($UserData) -gt 1048576 -or [Text.Encoding]::UTF8.GetByteCount($MetaData) -gt 65536) {
        throw 'Cloud-init seed exceeds the bounded user-data or metadata size.'
    }
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Server.ExclusiveAddressUse = $true
    $listener.Start()
    $endpoint = [System.Net.IPEndPoint]$listener.LocalEndpoint
    $startedAt = [DateTime]::UtcNow
    return [pscustomobject]@{
        Listener = $listener
        Address = '127.0.0.1'
        Port = [int]$endpoint.Port
        UserData = $UserData
        MetaData = $MetaData
        StartedAt = $startedAt
        DeadlineUtc = $startedAt.AddSeconds($TimeoutSeconds)
        RequestCount = 0
        RequestPaths = New-Object 'System.Collections.Generic.List[string]'
        Clients = New-Object 'System.Collections.Generic.List[object]'
        Closed = $false
    }
}

function Stop-EzDarkFactorySeedServer {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Server)

    if ($Server.Closed) { return }
    try {
        foreach ($state in @($Server.Clients.ToArray())) {
            try {
                if ($null -ne $state.Stream) { $state.Stream.Dispose() }
                $state.Client.Dispose()
                [Array]::Clear($state.Buffer.GetBuffer(), 0, $state.Buffer.Capacity)
                $state.Buffer.Dispose()
            }
            catch { }
        }
        $Server.Clients.Clear()
        $Server.Listener.Stop()
    }
    finally {
        $Server.UserData = ''
        $Server.MetaData = ''
        $Server.Closed = $true
    }
}

function Write-EzDarkFactorySeedHttpResponse {
    param(
        [Parameter(Mandatory = $true)][System.IO.Stream]$Stream,
        [Parameter(Mandatory = $true)][int]$StatusCode,
        [Parameter(Mandatory = $true)][string]$Reason,
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'HEAD')][string]$Method,
        [AllowEmptyString()][string]$Body = ''
    )

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $bodyBytes = $utf8.GetBytes($Body)
    $crlf = [char]13 + [char]10
    $header = "HTTP/1.1 $StatusCode $Reason" + $crlf +
        'Content-Type: text/plain; charset=utf-8' + $crlf +
        "Content-Length: $($bodyBytes.Length)" + $crlf +
        'Connection: keep-alive' + $crlf +
        'Cache-Control: no-store' + $crlf + $crlf
    $headerBytes = [Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    if ($Method -ceq 'GET' -and $bodyBytes.Length -gt 0) {
        $Stream.Write($bodyBytes, 0, $bodyBytes.Length)
    }
    $Stream.Flush()
}

function Add-EzDarkFactorySeedPendingClients {
    param([Parameter(Mandatory = $true)][object]$Server, [int]$Maximum)

    $accepted = 0
    while ($accepted -lt $Maximum -and $Server.Listener.Pending()) {
        $client = $Server.Listener.AcceptTcpClient()
        if ($Server.Clients.Count -ge 16) { $client.Dispose(); $accepted++; continue }
        $client.NoDelay = $true
        $client.ReceiveTimeout = 1000
        $client.SendTimeout = 1000
        $Server.Clients.Add([pscustomobject]@{
            Client = $client
            Stream = $client.GetStream()
            Buffer = New-Object System.IO.MemoryStream
            CloseAfterResponse = $false
            Closed = $false
        })
        $accepted++
    }
    return $accepted
}

function Close-EzDarkFactorySeedPendingClient {
    param([Parameter(Mandatory = $true)][object]$State)
    if ($State.Closed) { return }
    try {
        if ($null -ne $State.Stream) { $State.Stream.Dispose() }
        $State.Client.Dispose()
        [Array]::Clear($State.Buffer.GetBuffer(), 0, $State.Buffer.Capacity)
        $State.Buffer.Dispose()
    }
    finally { $State.Closed = $true }
}

function Complete-EzDarkFactorySeedPendingRequest {
    param(
        [Parameter(Mandatory = $true)][object]$Server,
        [Parameter(Mandatory = $true)][object]$State
    )

    if ($State.Buffer.Length -gt 16384) {
        Write-EzDarkFactorySeedHttpResponse -Stream $State.Stream -StatusCode 431 -Reason 'Request Header Fields Too Large' -Method GET
        $State.CloseAfterResponse = $true
        return $true
    }

    $text = [Text.Encoding]::ASCII.GetString($State.Buffer.ToArray())
    $boundary = [regex]::Match($text, '(?s)^(?<headers>.*?)\r?\n\r?\n')
    if (-not $boundary.Success) { return $false }

    $allBytes = $State.Buffer.ToArray()
    $remainingCount = $allBytes.Length - $boundary.Length
    $State.Buffer.Position = 0
    $State.Buffer.SetLength(0)
    if ($remainingCount -gt 0) {
        $State.Buffer.Write($allBytes, $boundary.Length, $remainingCount)
    }

    $lines = @($boundary.Groups['headers'].Value -split '\r?\n')
    if ($lines.Count -eq 0 -or [string]::IsNullOrWhiteSpace($lines[0])) {
        Write-EzDarkFactorySeedHttpResponse -Stream $State.Stream -StatusCode 400 -Reason 'Bad Request' -Method GET
        return $true
    }
    if ($lines.Count -gt 65) {
        Write-EzDarkFactorySeedHttpResponse -Stream $State.Stream -StatusCode 431 -Reason 'Request Header Fields Too Large' -Method GET
        return $true
    }

    $match = [regex]::Match($lines[0], '^(?<method>[A-Z]+) (?<target>[^ ]+) HTTP/1\.[01]$')
    if (-not $match.Success) {
        Write-EzDarkFactorySeedHttpResponse -Stream $State.Stream -StatusCode 400 -Reason 'Bad Request' -Method GET
        return $true
    }

    $method = $match.Groups['method'].Value
    $target = $match.Groups['target'].Value
    if ($method -cnotin @('GET', 'HEAD')) {
        Write-EzDarkFactorySeedHttpResponse -Stream $State.Stream -StatusCode 405 -Reason 'Method Not Allowed' -Method GET
        return $true
    }

    if ($Server.RequestPaths.Count -lt 64) {
        $recorded = if ($target -cin @('/user-data', '/meta-data', '/vendor-data', '/network-config')) { $target } else { '<rejected>' }
        $Server.RequestPaths.Add($recorded)
    }
    if ($target -ceq '/user-data') {
        Write-EzDarkFactorySeedHttpResponse -Stream $State.Stream -StatusCode 200 -Reason 'OK' -Method $method -Body $Server.UserData
    }
    elseif ($target -ceq '/meta-data') {
        Write-EzDarkFactorySeedHttpResponse -Stream $State.Stream -StatusCode 200 -Reason 'OK' -Method $method -Body $Server.MetaData
    }
    elseif ($target -ceq '/vendor-data' -or $target -ceq '/network-config') {
        # Current NoCloud probes both standard optional files. Empty 200 responses
        # avoid long datasource retry delays while preserving DHCP networking.
        Write-EzDarkFactorySeedHttpResponse -Stream $State.Stream -StatusCode 200 -Reason 'OK' -Method $method -Body ''
    }
    else {
        Write-EzDarkFactorySeedHttpResponse -Stream $State.Stream -StatusCode 404 -Reason 'Not Found' -Method $method
    }
    return $true
}

function Invoke-EzDarkFactorySeedServerPending {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Server,
        [ValidateRange(1, 64)][int]$MaxRequests = 8
    )

    if ($Server.Closed) { throw 'The cloud-init seed server is already closed.' }
    if ([DateTime]::UtcNow -gt $Server.DeadlineUtc) {
        Stop-EzDarkFactorySeedServer -Server $Server
        throw 'The cloud-init seed server exceeded its bounded lifetime.'
    }

    $null = Add-EzDarkFactorySeedPendingClients -Server $Server -Maximum $MaxRequests
    $handled = 0
    $buffer = New-Object byte[] 4096

    foreach ($state in @($Server.Clients.ToArray())) {
        if ($handled -ge $MaxRequests) { break }
        if ($state.Closed) { continue }

        try {
            while ($handled -lt $MaxRequests -and -not $state.Closed) {
                while ($state.Stream.DataAvailable) {
                    $read = $state.Stream.Read($buffer, 0, $buffer.Length)
                    if ($read -le 0) { break }
                    $state.Buffer.Position = $state.Buffer.Length
                    $state.Buffer.Write($buffer, 0, $read)
                    if ($state.Buffer.Length -gt 16384) { break }
                }

                if (Complete-EzDarkFactorySeedPendingRequest -Server $Server -State $state) {
                    $handled++
                    $Server.RequestCount++
                    if ($state.CloseAfterResponse) {
                        Close-EzDarkFactorySeedPendingClient -State $state
                        break
                    }
                    # Direct QEMU guestfwd uses one host-side chardev for the VM
                    # lifetime. Keep it open and parse subsequent HTTP requests
                    # from the same stream instead of killing forwarding after
                    # cloud-init's first seed fetch.
                    continue
                }
                break
            }

            if (-not $state.Closed) {
                $socket = $state.Client.Client
                if ($socket.Poll(0, [System.Net.Sockets.SelectMode]::SelectRead) -and $socket.Available -eq 0) {
                    Close-EzDarkFactorySeedPendingClient -State $state
                }
            }
        }
        catch [System.IO.IOException] {
            Close-EzDarkFactorySeedPendingClient -State $state
        }
        catch [System.Net.Sockets.SocketException] {
            Close-EzDarkFactorySeedPendingClient -State $state
        }
    }

    for ($index = $Server.Clients.Count - 1; $index -ge 0; $index--) {
        if ($Server.Clients[$index].Closed) { $Server.Clients.RemoveAt($index) }
    }
    return $handled
}
