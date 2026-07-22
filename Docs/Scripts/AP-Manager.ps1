[CmdletBinding()]
param(
    [string]$WorkbookPath,

    [string]$SheetName = "Sheet1",

    [Parameter(Mandatory = $true)]
    [int]$RowNumber,

    [string]$InputDataPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$PackageRoot = Split-Path -Parent $PSScriptRoot
$LogsDirectory = Join-Path $PackageRoot "Logs"
$BackupsDirectory = Join-Path $PackageRoot "Backups"
New-Item -ItemType Directory -Path $LogsDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $BackupsDirectory -Force | Out-Null

$script:LogPath = Join-Path $LogsDirectory ("AP_Row_{0}_{1}.log" -f $RowNumber, (Get-Date -Format "yyyyMMdd_HHmmss"))

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("INFO", "OK", "WARN", "ERROR")][string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message
    Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8

    $color = switch ($Level) {
        "OK"    { "Green" }
        "WARN"  { "Yellow" }
        "ERROR" { "Red" }
        default { "Cyan" }
    }

    Write-Host $line -ForegroundColor $color
}

function Get-CapturedRowData {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Captured Excel row data was not found: $Path"
    }

    try {
        $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($json)) {
            throw "Captured Excel row data is empty."
        }

        return ($json | ConvertFrom-Json)
    }
    finally {
        # The temporary file contains credentials, so remove it immediately.
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }
}

function Get-WorkbookRowData {
    param(
        [string]$Path,
        [string]$WorksheetName,
        [int]$Row
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Workbook not found: $Path"
    }

    $excel = $null
    $book = $null
    $sheet = $null

    try {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible = $false
        $excel.DisplayAlerts = $false

        # Open read-only. Save the workbook before clicking Run.
        $book = $excel.Workbooks.Open($Path, 0, $true)
        $sheet = $book.Worksheets.Item($WorksheetName)

        [pscustomobject]@{
            Department      = [string]$sheet.Cells.Item($Row, 1).Value2
            AccessPointName = [string]$sheet.Cells.Item($Row, 2).Value2
            IPAddress       = ([string]$sheet.Cells.Item($Row, 3).Value2).Trim()
            MacAddress      = ([string]$sheet.Cells.Item($Row, 4).Value2).Trim()
            Username        = ([string]$sheet.Cells.Item($Row, 5).Value2).Trim()
            Password        = [string]$sheet.Cells.Item($Row, 6).Value2
            NewSSID         = ([string]$sheet.Cells.Item($Row, 7).Value2).Trim()
            NewWiFiPassword = [string]$sheet.Cells.Item($Row, 8).Value2
        }
    }
    finally {
        if ($book -ne $null) {
            $book.Close($false)
        }
        if ($excel -ne $null) {
            $excel.Quit()
        }

        foreach ($item in @($sheet, $book, $excel)) {
            if ($item -ne $null) {
                [void][Runtime.InteropServices.Marshal]::ReleaseComObject($item)
            }
        }

        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
}

function Assert-InputData {
    param($Data)

    if ([string]::IsNullOrWhiteSpace($Data.IPAddress)) {
        throw "Access Point IP is empty in row $RowNumber."
    }

    $parsedIP = $null
    if (-not [System.Net.IPAddress]::TryParse($Data.IPAddress, [ref]$parsedIP)) {
        throw "Invalid IP address: $($Data.IPAddress)"
    }

    if ([string]::IsNullOrWhiteSpace($Data.Username)) {
        throw "Access User is empty in row $RowNumber."
    }

    if ([string]::IsNullOrEmpty($Data.Password)) {
        throw "Access Password is empty in row $RowNumber."
    }

    if (-not [string]::IsNullOrWhiteSpace($Data.NewSSID)) {
        if ($Data.NewSSID.Length -gt 32) {
            throw "New SSID must be 32 characters or fewer."
        }
        if ($Data.NewSSID -match "[`r`n]") {
            throw "New SSID contains an invalid line break."
        }
    }

    if (-not [string]::IsNullOrEmpty($Data.NewWiFiPassword)) {
        if ($Data.NewWiFiPassword.Length -lt 8 -or $Data.NewWiFiPassword.Length -gt 63) {
            throw "WPA2 password must be between 8 and 63 characters."
        }
        if ($Data.NewWiFiPassword -match "[`r`n]") {
            throw "New WiFi password contains an invalid line break."
        }
    }
}

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

            if ($count -le 0) {
                break
            }

            $lastReceived = $watch.ElapsedMilliseconds
            $clean = [System.Collections.Generic.List[byte]]::new()
            $index = 0

            while ($index -lt $count) {
                $value = $buffer[$index]

                # Telnet IAC negotiation.
                if ($value -eq 255) {
                    if (($index + 1) -ge $count) {
                        break
                    }

                    $command = $buffer[$index + 1]

                    # Escaped literal 255.
                    if ($command -eq 255) {
                        $clean.Add(255)
                        $index += 2
                        continue
                    }

                    # WILL/WONT/DO/DONT option negotiation.
                    if ($command -in @(251, 252, 253, 254)) {
                        if (($index + 2) -ge $count) {
                            break
                        }

                        $option = $buffer[$index + 2]

                        if ($command -eq 251) {
                            # Remote WILL -> reply DONT.
                            Send-TelnetBytes -Session $Session -Bytes ([byte[]](255, 254, $option))
                        }
                        elseif ($command -eq 253) {
                            # Remote DO -> reply WONT.
                            Send-TelnetBytes -Session $Session -Bytes ([byte[]](255, 252, $option))
                        }

                        $index += 3
                        continue
                    }

                    # Sub-negotiation: skip until IAC SE.
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

    $builder.ToString()
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

function Connect-CiscoTelnet {
    param(
        [string]$IPAddress,
        [string]$Username,
        [string]$Password
    )

    Write-Log "Connecting to $IPAddress by Telnet on port 23..."

    $client = New-Object Net.Sockets.TcpClient
    $async = $client.BeginConnect($IPAddress, 23, $null, $null)

    if (-not $async.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds(10))) {
        $client.Close()
        throw "Telnet port 23 did not respond on $IPAddress."
    }

    $client.EndConnect($async)
    $client.ReceiveTimeout = 3000
    $client.SendTimeout = 5000

    $session = [pscustomobject]@{
        Client = $client
        Stream = $client.GetStream()
    }

    $first = Read-Until -Session $session -Patterns @(
        "(?i)Username:",
        "(?i)login:",
        "(?i)Password:",
        "(?m)^[^\r\n]*[>#]\s*$"
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
        "(?m)^[^\r\n]*>\s*$",
        "(?m)^[^\r\n]*#\s*$",
        "(?i)Authentication failed",
        "(?i)Login invalid"
    ) -TimeoutSeconds 15

    if ($login.Text -match "(?i)Authentication failed|(?i)Login invalid") {
        $session.Client.Close()
        throw "Login failed for $IPAddress."
    }

    if ($login.Text -match "(?m)^[^\r\n]*>\s*$") {
        Send-TelnetLine -Session $session -Text "enable"
        $enablePrompt = Read-Until -Session $session -Patterns @(
            "(?i)Password:",
            "(?m)^[^\r\n]*#\s*$"
        ) -TimeoutSeconds 10

        if ($enablePrompt.Text -match "(?i)Password:") {
            Send-TelnetLine -Session $session -Text $Password
            $enabled = Read-Until -Session $session -Patterns @(
                "(?m)^[^\r\n]*#\s*$",
                "(?i)Access denied",
                "(?i)Bad passwords"
            ) -TimeoutSeconds 10

            if ($enabled.Text -match "(?i)Access denied|(?i)Bad passwords") {
                $session.Client.Close()
                throw "Enable password failed for $IPAddress."
            }
        }
    }

    Write-Log "Privileged mode entered successfully." "OK"

    [void](Invoke-CiscoCommand -Session $session -Command "terminal length 0" -TimeoutSeconds 10)

    $session
}

function Close-CiscoTelnet {
    param($Session)

    if ($Session -ne $null) {
        try { $Session.Stream.Close() } catch {}
        try { $Session.Client.Close() } catch {}
    }
}

function Invoke-CiscoCommand {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string]$Command,
        [int]$TimeoutSeconds = 20,
        [switch]$AllowDisconnect
    )

    Send-TelnetLine -Session $Session -Text $Command

    $result = Read-Until -Session $Session -Patterns @(
        "(?m)^[^\r\n]*[>#]\s*$"
    ) -TimeoutSeconds $TimeoutSeconds -AllowDisconnect:$AllowDisconnect

    if ($result.Text -match "(?im)^%\s*(Invalid input|Incomplete command|Ambiguous command|Error|Failed)") {
        throw "Cisco rejected command '$Command'. Response: $($result.Text)"
    }

    $result.Text
}


function ConvertTo-CiscoCLIValue {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -match "[`r`n]") {
        throw "Cisco CLI values cannot contain line breaks."
    }

    # Cisco IOS treats ? as interactive help. Ctrl+V escapes it as a literal.
    $Value.Replace("?", ([char]22).ToString() + "?")
}

function Backup-CiscoConfiguration {
    param(
        $Session,
        [string]$IPAddress
    )

    Write-Log "Creating a running-config backup before changes..."
    $configuration = Invoke-CiscoCommand -Session $Session -Command "show running-config" -TimeoutSeconds 60
    $safeIP = $IPAddress.Replace(".", "_")
    $backupPath = Join-Path $BackupsDirectory ("AP_{0}_{1}_running-config.txt" -f $safeIP, (Get-Date -Format "yyyyMMdd_HHmmss"))
    Set-Content -LiteralPath $backupPath -Value $configuration -Encoding UTF8
    Write-Log "Backup saved: $backupPath" "OK"
}

function Get-CurrentSSID {
    param($Session)

    $output = Invoke-CiscoCommand -Session $Session -Command "show running-config | section ^interface Dot11Radio0$" -TimeoutSeconds 20
    $match = [regex]::Match($output, "(?m)^\s*ssid\s+(.+?)\s*$")

    if (-not $match.Success) {
        throw "Could not find an SSID under Dot11Radio0."
    }

    $match.Groups[1].Value.Trim()
}

function Get-SSIDProfileCommands {
    param($Session)

    $output = Invoke-CiscoCommand -Session $Session -Command "show running-config | section ^dot11 ssid" -TimeoutSeconds 20
    $commands = New-Object System.Collections.Generic.List[string]
    $inside = $false

    foreach ($line in ($output -split "`r?`n")) {
        if ($line -match "^\s*dot11 ssid\s+.+$") {
            $inside = $true
            continue
        }

        if (-not $inside) {
            continue
        }

        if ($line -match "^[^\s!].*[>#]\s*$") {
            break
        }

        if ($line -match "^\S" -and $line.Trim() -ne "!") {
            break
        }

        $trimmed = $line.Trim()
        if (-not [string]::IsNullOrWhiteSpace($trimmed) -and $trimmed -ne "!") {
            $commands.Add($trimmed)
        }
    }

    if ($commands.Count -eq 0) {
        throw "Could not read the current SSID profile."
    }

    $commands.ToArray()
}

function Test-CiscoResponse {
    param(
        [string]$Command,
        [string]$Response
    )

    if ($Response -match "(?im)^%\s*(Invalid input|Incomplete command|Ambiguous command|Error|Failed)") {
        throw "Cisco rejected command '$Command'. Response: $Response"
    }
}

function Set-WirelessConfiguration {
    param(
        $Session,
        [string]$CurrentSSID,
        [string]$NewSSID,
        [string]$NewWiFiPassword
    )

    $renameSSID = -not [string]::IsNullOrWhiteSpace($NewSSID) -and $NewSSID -ne $CurrentSSID
    $currentSSIDCLI = ConvertTo-CiscoCLIValue -Value $CurrentSSID
    $newSSIDCLI = if ([string]::IsNullOrWhiteSpace($NewSSID)) { "" } else { ConvertTo-CiscoCLIValue -Value $NewSSID }
    $newPasswordCLI = if ([string]::IsNullOrEmpty($NewWiFiPassword)) { "" } else { ConvertTo-CiscoCLIValue -Value $NewWiFiPassword }
    $changePassword = -not [string]::IsNullOrEmpty($NewWiFiPassword)

    if (-not $renameSSID -and -not $changePassword) {
        Write-Log "New SSID and New WiFi Password are empty. WiFi settings were skipped." "WARN"
        return $CurrentSSID
    }

    if ($renameSSID) {
        Write-Log "Preparing to rename 2.4GHz SSID from '$CurrentSSID' to '$NewSSID'."
        $profileCommands = Get-SSIDProfileCommands -Session $Session

        [void](Invoke-CiscoCommand -Session $Session -Command "configure terminal")
        [void](Invoke-CiscoCommand -Session $Session -Command ("dot11 ssid " + $newSSIDCLI))

        $passwordWasCopied = $false

        foreach ($profileCommand in $profileCommands) {
            if ($profileCommand -match "^wpa-psk\s+") {
                if ($changePassword) {
                    continue
                }
                $passwordWasCopied = $true
            }

            $response = Invoke-CiscoCommand -Session $Session -Command $profileCommand
            Test-CiscoResponse -Command $profileCommand -Response $response
        }

        if ($changePassword) {
            $passwordCommand = "wpa-psk ascii " + $newPasswordCLI
            $response = Invoke-CiscoCommand -Session $Session -Command $passwordCommand
            Test-CiscoResponse -Command "wpa-psk ascii ********" -Response $response
        }
        elseif (-not $passwordWasCopied) {
            throw "The old WPA2 key could not be copied to the new SSID."
        }

        [void](Invoke-CiscoCommand -Session $Session -Command "exit")
        [void](Invoke-CiscoCommand -Session $Session -Command "interface Dot11Radio0")
        [void](Invoke-CiscoCommand -Session $Session -Command ("no ssid " + $currentSSIDCLI))
        [void](Invoke-CiscoCommand -Session $Session -Command ("ssid " + $newSSIDCLI))
        [void](Invoke-CiscoCommand -Session $Session -Command "exit")
        [void](Invoke-CiscoCommand -Session $Session -Command ("no dot11 ssid " + $currentSSIDCLI))
        [void](Invoke-CiscoCommand -Session $Session -Command "end")

        Write-Log "SSID changed to '$NewSSID' on Dot11Radio0." "OK"

        if ($changePassword) {
            Write-Log "WPA2 password updated." "OK"
        }

        return $NewSSID
    }

    # Password-only update.
    Write-Log "Keeping SSID '$CurrentSSID' and updating its WPA2 password."
    [void](Invoke-CiscoCommand -Session $Session -Command "configure terminal")
    [void](Invoke-CiscoCommand -Session $Session -Command ("dot11 ssid " + $currentSSIDCLI))
    $passwordCommand = "wpa-psk ascii " + $newPasswordCLI
    $response = Invoke-CiscoCommand -Session $Session -Command $passwordCommand
    Test-CiscoResponse -Command "wpa-psk ascii ********" -Response $response
    [void](Invoke-CiscoCommand -Session $Session -Command "end")

    Write-Log "WPA2 password updated." "OK"
    $CurrentSSID
}

function Save-CiscoConfiguration {
    param($Session)

    Write-Log "Saving running configuration to startup configuration..."
    $saveOutput = Invoke-CiscoCommand -Session $Session -Command "write memory" -TimeoutSeconds 30

    if ($saveOutput -notmatch "\[OK\]") {
        Write-Log "The AP did not return [OK], but the write memory command completed. Review the log." "WARN"
    }
    else {
        Write-Log "Startup configuration saved." "OK"
    }
}

function Enable-SSHVersion2 {
    param(
        [ref]$SessionReference,
        [string]$IPAddress,
        [string]$Username,
        [string]$Password
    )

    $session = $SessionReference.Value
    $sshStatus = Invoke-CiscoCommand -Session $session -Command "show ip ssh" -TimeoutSeconds 20

    if ($sshStatus -match "SSH Enabled\s*-\s*version 2") {
        Write-Log "SSH Version 2 is already enabled." "OK"
        return
    }

    # RSA generation requires both a hostname and an IP domain name.
    $identity = Invoke-CiscoCommand -Session $session -Command "show running-config | include ^hostname|^ip domain-name" -TimeoutSeconds 15
    $hasHostname = $identity -match "(?m)^hostname\s+\S+"
    $hasDomain = $identity -match "(?m)^ip domain-name\s+\S+"

    [void](Invoke-CiscoCommand -Session $session -Command "configure terminal")

    if (-not $hasHostname) {
        Write-Log "No hostname was found. Setting hostname to ap." "WARN"
        [void](Invoke-CiscoCommand -Session $session -Command "hostname ap")
    }

    if (-not $hasDomain) {
        Write-Log "No IP domain name was found. Setting ip domain-name samacollege.com." "WARN"
        [void](Invoke-CiscoCommand -Session $session -Command "ip domain-name samacollege.com")
    }

    Write-Log "Generating a 4096-bit RSA key for SSH Version 2..."
    Send-TelnetLine -Session $session -Text "crypto key generate rsa"

    $rsaText = ""
    $rsaStep = Read-Until -Session $session -Patterns @(
        "(?i)Do you really want to replace them\?\s*\[yes/no\]:",
        "(?i)How many bits in the modulus.*:",
        "(?m)^[^\r\n]*\(config\)#\s*$"
    ) -TimeoutSeconds 30
    $rsaText += $rsaStep.Text

    if ($rsaStep.Text -match "(?i)Do you really want to replace them\?") {
        Send-TelnetLine -Session $session -Text "yes"
        $rsaStep = Read-Until -Session $session -Patterns @(
            "(?i)How many bits in the modulus.*:",
            "(?m)^[^\r\n]*\(config\)#\s*$"
        ) -TimeoutSeconds 30
        $rsaText += $rsaStep.Text
    }

    if ($rsaStep.Text -match "(?i)How many bits in the modulus") {
        Send-TelnetLine -Session $session -Text "4096"
        $rsaFinished = Read-Until -Session $session -Patterns @(
            "(?i)\[OK\]",
            "(?m)^[^\r\n]*\(config\)#\s*$"
        ) -TimeoutSeconds 240
        $rsaText += $rsaFinished.Text

        if ($rsaFinished.Text -notmatch "(?m)^[^\r\n]*\(config\)#\s*$") {
            $promptResult = Read-Until -Session $session -Patterns @(
                "(?m)^[^\r\n]*\(config\)#\s*$"
            ) -TimeoutSeconds 30
            $rsaText += $promptResult.Text
        }
    }

    if ($rsaText -match "(?im)^%.*(domain|hostname|invalid|failed|error)") {
        throw "RSA key generation failed. Cisco output: $rsaText"
    }

    if ($rsaText -notmatch "(?i)\[OK\]") {
        throw "RSA key generation did not return [OK]. Cisco output: $rsaText"
    }

    Write-Log "RSA key generation completed." "OK"

    # Confirm IOS can see the new key before switching versions.
    [void](Invoke-CiscoCommand -Session $session -Command "end" -TimeoutSeconds 10)
    $preCheck = Invoke-CiscoCommand -Session $session -Command "show ip ssh" -TimeoutSeconds 20
    if ($preCheck -match "IOS Keys.*NONE" -or $preCheck -match "Please create RSA keys") {
        throw "IOS still reports no RSA key after generation. Output: $preCheck"
    }

    [void](Invoke-CiscoCommand -Session $session -Command "configure terminal")
    Write-Log "Switching SSH to Version 2. The current Telnet session may close."
    Send-TelnetLine -Session $session -Text "ip ssh version 2"
    $versionResult = Read-Until -Session $session -Patterns @(
        "(?m)^[^\r\n]*\(config\)#\s*$"
    ) -TimeoutSeconds 15 -AllowDisconnect

    $mustReconnect = $versionResult.Pattern -in @("DISCONNECTED", "TIMEOUT_OR_DISCONNECT")

    if (-not $mustReconnect) {
        try {
            [void](Invoke-CiscoCommand -Session $session -Command "end" -TimeoutSeconds 10)
            Save-CiscoConfiguration -Session $session
        }
        catch {
            $mustReconnect = $true
        }
    }

    if ($mustReconnect) {
        Write-Log "The Telnet session closed after changing SSH. Reconnecting to save and verify..." "WARN"
        Close-CiscoTelnet -Session $session
        Start-Sleep -Seconds 4
        $session = Connect-CiscoTelnet -IPAddress $IPAddress -Username $Username -Password $Password
        $SessionReference.Value = $session
        Save-CiscoConfiguration -Session $session
    }

    $verification = Invoke-CiscoCommand -Session $session -Command "show ip ssh" -TimeoutSeconds 20

    if ($verification -notmatch "SSH Enabled\s*-\s*version 2") {
        throw "SSH Version 2 verification failed. Output: $verification"
    }

    Write-Log "SSH Version 2 verified successfully." "OK"
}

$session = $null

try {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor DarkCyan
    Write-Host " Cisco Aironet 3600 AP WiFi Manager" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor DarkCyan
    Write-Host ""

    if (-not [string]::IsNullOrWhiteSpace($InputDataPath)) {
        $data = Get-CapturedRowData -Path $InputDataPath
        $sourceDescription = if ($null -ne $data.ExcelSource) { [string]$data.ExcelSource } else { "Excel row snapshot" }
        Write-Log "Reading the current values of row $RowNumber captured from: $sourceDescription"
    }
    else {
        if ([string]::IsNullOrWhiteSpace($WorkbookPath)) {
            throw "WorkbookPath is required when InputDataPath is not supplied."
        }
        Write-Log "Reading saved row $RowNumber from $WorkbookPath"
        $data = Get-WorkbookRowData -Path $WorkbookPath -WorksheetName $SheetName -Row $RowNumber
    }

    Assert-InputData -Data $data

    Write-Log ("Target AP: {0} | Name: {1}" -f $data.IPAddress, $data.AccessPointName)
    Write-Log ("Excel values used -> New SSID: {0} | New WiFi Password: {1}" -f `
        $(if ([string]::IsNullOrWhiteSpace([string]$data.NewSSID)) { "<empty: skip>" } else { "'$($data.NewSSID)'" }), `
        $(if ([string]::IsNullOrEmpty([string]$data.NewWiFiPassword)) { "<empty: skip>" } else { "<provided: update>" }))

    $session = Connect-CiscoTelnet -IPAddress $data.IPAddress -Username $data.Username -Password $data.Password

    Backup-CiscoConfiguration -Session $session -IPAddress $data.IPAddress

    $currentSSID = Get-CurrentSSID -Session $session
    Write-Log "Current Dot11Radio0 SSID: '$currentSSID'" "OK"

    $finalSSID = Set-WirelessConfiguration `
        -Session $session `
        -CurrentSSID $currentSSID `
        -NewSSID $data.NewSSID `
        -NewWiFiPassword $data.NewWiFiPassword

    Save-CiscoConfiguration -Session $session

    Enable-SSHVersion2 `
        -SessionReference ([ref]$session) `
        -IPAddress $data.IPAddress `
        -Username $data.Username `
        -Password $data.Password

    $verifiedSSID = Get-CurrentSSID -Session $session

    if ($verifiedSSID -ne $finalSSID) {
        throw "SSID verification failed. Expected '$finalSSID' but found '$verifiedSSID'."
    }

    Write-Log "Final Dot11Radio0 SSID verified: '$verifiedSSID'" "OK"
    Write-Log "Operation completed successfully for $($data.IPAddress)." "OK"

    Write-Host ""
    Write-Host "SUCCESS" -ForegroundColor Green
    Write-Host "Log file: $script:LogPath" -ForegroundColor Gray
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    Write-Host ""
    Write-Host "FAILED — no further commands will be sent." -ForegroundColor Red
    Write-Host "Review the log file: $script:LogPath" -ForegroundColor Yellow
}
finally {
    Close-CiscoTelnet -Session $session
    Write-Host ""
    Read-Host "Press Enter to close"
}
