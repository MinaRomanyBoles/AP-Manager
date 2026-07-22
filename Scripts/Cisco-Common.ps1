# Shared Cisco connection helpers — Telnet + SSH (Posh-SSH) with Telnet fallback.
$ErrorActionPreference = "Stop"

function Send-TelnetBytes {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][byte[]]$Bytes
    )
    $Session.Stream.Write($Bytes, 0, $Bytes.Length)
    $Session.Stream.Flush()
}

function Send-TelnetLine {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string]$Text
    )
    $bytes = [Text.Encoding]::ASCII.GetBytes($Text + "`r`n")
    Send-TelnetBytes -Session $Session -Bytes $bytes
}

function Read-TelnetChunk {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [int]$IdleMilliseconds = 300,
        [int]$MaximumMilliseconds = 3000
    )

    $builder = New-Object Text.StringBuilder
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $lastReceived = -1

    while ($watch.ElapsedMilliseconds -lt $MaximumMilliseconds) {
        if ($Session.Stream.DataAvailable) {
            $buffer = New-Object byte[] 4096
            $count = $Session.Stream.Read($buffer, 0, $buffer.Length)
            if ($count -le 0) { break }

            $lastReceived = $watch.ElapsedMilliseconds
            $clean = [System.Collections.Generic.List[byte]]::new()
            $index = 0

            while ($index -lt $count) {
                $value = $buffer[$index]
                if ($value -eq 255) {
                    if (($index + 1) -ge $count) { break }
                    $command = $buffer[$index + 1]
                    if ($command -eq 255) {
                        $clean.Add(255)
                        $index += 2
                        continue
                    }
                    if ($command -in @(251, 252, 253, 254)) {
                        if (($index + 2) -ge $count) { break }
                        $option = $buffer[$index + 2]
                        if ($command -eq 251) {
                            Send-TelnetBytes -Session $Session -Bytes ([byte[]](255, 254, $option))
                        }
                        elseif ($command -eq 253) {
                            Send-TelnetBytes -Session $Session -Bytes ([byte[]](255, 252, $option))
                        }
                        $index += 3
                        continue
                    }
                    if ($command -eq 250) {
                        $index += 2
                        while (($index + 1) -lt $count) {
                            if ($buffer[$index] -eq 255 -and $buffer[$index + 1] -eq 240) {
                                $index += 2
                                break
                            }
                            $index++
                        }
                        continue
                    }
                    $index += 2
                    continue
                }
                $clean.Add($value)
                $index++
            }

            if ($clean.Count -gt 0) {
                [void]$builder.Append([Text.Encoding]::ASCII.GetString($clean.ToArray()))
            }
        }
        else {
            if ($lastReceived -ge 0 -and (($watch.ElapsedMilliseconds - $lastReceived) -ge $IdleMilliseconds)) {
                break
            }
            Start-Sleep -Milliseconds 50
        }
    }

    return $builder.ToString()
}

function Read-Until {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string[]]$Patterns,
        [int]$TimeoutSeconds = 20,
        [switch]$AllowDisconnect
    )

    $allText = ""
    $watch = [Diagnostics.Stopwatch]::StartNew()

    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        try {
            $chunk = Read-TelnetChunk -Session $Session -IdleMilliseconds 250 -MaximumMilliseconds 1200
        }
        catch {
            if ($AllowDisconnect) {
                return [pscustomobject]@{ Text = $allText; Pattern = "DISCONNECTED" }
            }
            throw
        }

        if (-not [string]::IsNullOrEmpty($chunk)) {
            $allText += $chunk
        }

        foreach ($pattern in $Patterns) {
            if ($allText -match $pattern) {
                return [pscustomobject]@{ Text = $allText; Pattern = $pattern }
            }
        }

        Start-Sleep -Milliseconds 100
    }

    if ($AllowDisconnect) {
        return [pscustomobject]@{ Text = $allText; Pattern = "TIMEOUT_OR_DISCONNECT" }
    }

    throw "Timed out waiting for the Cisco prompt. Received: $allText"
}

function Invoke-CiscoCommand {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string]$Command,
        [int]$TimeoutSeconds = 30,
        [switch]$AllowDisconnect
    )

    if ($Session.Type -eq "SSH") {
        return Invoke-SshCiscoCommand -Session $Session -Command $Command -TimeoutSeconds $TimeoutSeconds
    }

    Send-TelnetLine -Session $Session -Text $Command
    $result = Read-Until -Session $Session -Patterns @("(?m)^[^`r`n]*[>#]\s*$") -TimeoutSeconds $TimeoutSeconds -AllowDisconnect:$AllowDisconnect

    if ($result.Text -match "(?im)^%\s*(Invalid input|Incomplete command|Ambiguous command|Error|Failed)") {
        throw "Cisco rejected command '$Command'."
    }

    return $result.Text
}

function Test-PortOpen {
    param(
        [Parameter(Mandatory = $true)][string]$IPAddress,
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutSeconds = 10
    )

    $client = New-Object Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($IPAddress, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))) {
            return $false
        }
        $client.EndConnect($async)
        return $true
    }
    catch {
        return $false
    }
    finally {
        try { $client.Close() } catch {}
    }
}

function Test-ApPing {
    param([Parameter(Mandatory = $true)][string]$IPAddress)
    try {
        return (Test-Connection -ComputerName $IPAddress -Count 1 -Quiet -ErrorAction Stop)
    }
    catch {
        return $false
    }
}

function Connect-CiscoTelnet {
    param(
        [Parameter(Mandatory = $true)][string]$IPAddress,
        [Parameter(Mandatory = $true)][string]$Username,
        [Parameter(Mandatory = $true)][string]$Password
    )

    if (-not (Test-PortOpen -IPAddress $IPAddress -Port 23 -TimeoutSeconds 10)) {
        throw "Telnet port 23 is closed or unreachable on $IPAddress."
    }

    $client = New-Object Net.Sockets.TcpClient
    $async = $client.BeginConnect($IPAddress, 23, $null, $null)

    if (-not $async.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds(10))) {
        $client.Close()
        throw "Connection timeout on Telnet port 23 for $IPAddress."
    }

    $client.EndConnect($async)
    $client.ReceiveTimeout = 4000
    $client.SendTimeout = 5000

    $session = [pscustomobject]@{
        Type = "Telnet"
        Client = $client
        Stream = $client.GetStream()
        ConnectionType = "Telnet"
    }

    try {
        $first = Read-Until -Session $session -Patterns @(
            "(?i)Username:", "(?i)login:", "(?i)Password:", "(?m)^[^`r`n]*[>#]\s*$"
        ) -TimeoutSeconds 15

        if ($first.Text -match "(?i)Username:|(?i)login:") {
            Send-TelnetLine -Session $session -Text $Username
            [void](Read-Until -Session $session -Patterns @("(?i)Password:") -TimeoutSeconds 10)
            Send-TelnetLine -Session $session -Text $Password
        }
        elseif ($first.Text -match "(?i)Password:") {
            Send-TelnetLine -Session $session -Text $Password
        }

        $login = Read-Until -Session $session -Patterns @(
            "(?m)^[^`r`n]*>\s*$", "(?m)^[^`r`n]*#\s*$",
            "(?i)Authentication failed", "(?i)Login invalid"
        ) -TimeoutSeconds 15

        if ($login.Text -match "(?i)Authentication failed|(?i)Login invalid") {
            throw "Login failed for $IPAddress. Check Access User and Access Password."
        }

        if ($login.Text -match "(?m)^[^`r`n]*>\s*$") {
            Send-TelnetLine -Session $session -Text "enable"
            $enablePrompt = Read-Until -Session $session -Patterns @("(?i)Password:", "(?m)^[^`r`n]*#\s*$") -TimeoutSeconds 10
            if ($enablePrompt.Text -match "(?i)Password:") {
                Send-TelnetLine -Session $session -Text $Password
                $enabled = Read-Until -Session $session -Patterns @(
                    "(?m)^[^`r`n]*#\s*$", "(?i)Access denied", "(?i)Bad passwords"
                ) -TimeoutSeconds 10
                if ($enabled.Text -match "(?i)Access denied|(?i)Bad passwords") {
                    throw "Enable password failed for $IPAddress."
                }
            }
        }

        [void](Invoke-CiscoCommand -Session $session -Command "terminal length 0" -TimeoutSeconds 10)
        return $session
    }
    catch {
        Close-CiscoSession -Session $session
        throw
    }
}

function Connect-CiscoSsh {
    param(
        [Parameter(Mandatory = $true)][string]$IPAddress,
        [Parameter(Mandatory = $true)][string]$Username,
        [Parameter(Mandatory = $true)][string]$Password
    )

    if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
        throw "Posh-SSH module is not installed. Run Install-AP-Manager.bat."
    }

    Import-Module Posh-SSH -ErrorAction Stop

    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($Username, $securePassword)

    $sessionParams = @{
        ComputerName = $IPAddress
        Credential = $credential
        AcceptKey = $true
        ConnectionTimeout = 10
        Force = $true
        ErrorAction = "Stop"
    }

    try {
        $sshSession = New-SSHSession @sessionParams
    }
    catch {
        throw "SSH negotiation failed for $IPAddress. $($_.Exception.Message)"
    }

    if ($null -eq $sshSession) {
        throw "SSH session could not be established for $IPAddress."
    }

    $wrapper = [pscustomobject]@{
        Type = "SSH"
        SshSession = $sshSession
        ConnectionType = "SSH"
        Buffer = ""
        InEnableMode = $false
    }

    try {
        $banner = Invoke-SshCiscoCommand -Session $wrapper -Command "" -TimeoutSeconds 10
        if ($banner -match "(?m)^[^`r`n]*>\s*$") {
            Invoke-SshCiscoCommand -Session $wrapper -Command "enable" -TimeoutSeconds 10 | Out-Null
            Invoke-SshCiscoCommand -Session $wrapper -Command $Password -TimeoutSeconds 10 | Out-Null
        }
        Invoke-SshCiscoCommand -Session $wrapper -Command "terminal length 0" -TimeoutSeconds 10 | Out-Null
        $wrapper.InEnableMode = $true
        return $wrapper
    }
    catch {
        Close-CiscoSession -Session $wrapper
        throw
    }
}

function Invoke-SshCiscoCommand {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string]$Command,
        [int]$TimeoutSeconds = 30
    )

    $result = Invoke-SSHCommand -SessionId $Session.SshSession.SessionId -Command $Command -TimeOut ($TimeoutSeconds * 1000)
    if ($result.ExitStatus -ne 0 -and $Command -ne "") {
        if ($result.Error -match "(?im)^%\s*(Invalid input|Incomplete command|Ambiguous command|Error|Failed)") {
            throw "Cisco rejected command '$Command'."
        }
    }
    return ($result.Output -join "`n")
}

function Connect-CiscoSession {
    param(
        [Parameter(Mandatory = $true)][string]$IPAddress,
        [Parameter(Mandatory = $true)][string]$Username,
        [Parameter(Mandatory = $true)][string]$Password
    )

    if (-not (Test-ApPing -IPAddress $IPAddress)) {
        throw "Access Point $IPAddress does not respond to ping."
    }

    if (Test-PortOpen -IPAddress $IPAddress -Port 22 -TimeoutSeconds 10) {
        try {
            $session = Connect-CiscoSsh -IPAddress $IPAddress -Username $Username -Password $Password
            return $session
        }
        catch {
            if (Test-PortOpen -IPAddress $IPAddress -Port 23 -TimeoutSeconds 10) {
                $session = Connect-CiscoTelnet -IPAddress $IPAddress -Username $Username -Password $Password
                $session | Add-Member -NotePropertyName ConnectionType -NotePropertyValue "Telnet (SSH fallback)" -Force
                return $session
            }
            throw
        }
    }

    return Connect-CiscoTelnet -IPAddress $IPAddress -Username $Username -Password $Password
}

function Close-CiscoSession {
    param($Session)
    if ($null -eq $Session) { return }

    if ($Session.Type -eq "SSH") {
        try {
            if ($null -ne $Session.SshSession) {
                Remove-SSHSession -SessionId $Session.SshSession.SessionId -ErrorAction SilentlyContinue | Out-Null
            }
        }
        catch {}
        return
    }

    try { $Session.Stream.Close() } catch {}
    try { $Session.Client.Close() } catch {}
}

function Get-Radio0ClientCount {
    param([Parameter(Mandatory = $true)][string]$Output)

    $sectionMatch = [regex]::Match(
        $Output,
        "(?is)802\.11\s+Client\s+Stations\s+on\s+Dot11Radio0\s*:?(.*?)(?=802\.11\s+Client\s+Stations\s+on\s+Dot11Radio1|(?:`r?`n)[^`r`n]*#\s*$|\z)"
    )

    $section = if ($sectionMatch.Success) { $sectionMatch.Groups[1].Value } else { $Output }

    $macPattern = "(?im)^\s*([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4}|[0-9a-f]{2}(?::[0-9a-f]{2}){5})(?:\s+|$)"
    $macs = [regex]::Matches($section, $macPattern) |
        ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() } |
        Sort-Object -Unique

    return @($macs).Count
}

function ConvertTo-CiscoCLIValue {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value -match "[`r`n]") {
        throw "Cisco CLI values cannot contain line breaks."
    }
    $Value.Replace("?", ([char]22).ToString() + "?")
}

function Write-CiscoLog {
    param(
        [Parameter(Mandatory = $true)][string]$LogPath,
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("INFO", "OK", "WARN", "ERROR")][string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}
