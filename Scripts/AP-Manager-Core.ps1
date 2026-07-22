# Core AP update functions extracted from AP-Manager.ps1 (Telnet session compatible).

function Backup-CiscoConfiguration {
    param(
        $Session,
        [string]$IPAddress,
        [string]$BackupsDirectory
    )

    Write-CiscoLog -LogPath $script:UpdateLogPath -Message "Creating running-config backup before changes..." -Level "INFO"
    $configuration = Invoke-CiscoCommand -Session $Session -Command "show running-config" -TimeoutSeconds 60
    $safeIP = $IPAddress.Replace(".", "_")
    $backupPath = Join-Path $BackupsDirectory ("AP_{0}_{1}_running-config.txt" -f $safeIP, (Get-Date -Format "yyyyMMdd_HHmmss"))
    Set-Content -LiteralPath $backupPath -Value $configuration -Encoding UTF8
    return $backupPath
}

function Get-CurrentSSID {
    param($Session)

    $output = Invoke-CiscoCommand -Session $Session -Command "show running-config | section ^interface Dot11Radio0$" -TimeoutSeconds 20
    $match = [regex]::Match($output, "(?m)^\s*ssid\s+(.+?)\s*$")

    if (-not $match.Success) {
        throw "Could not find an SSID under Dot11Radio0."
    }

    return $match.Groups[1].Value.Trim()
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
        if (-not $inside) { continue }
        if ($line -match "^[^\s!].*[>#]\s*$") { break }
        if ($line -match "^\S" -and $line.Trim() -ne "!") { break }
        $trimmed = $line.Trim()
        if (-not [string]::IsNullOrWhiteSpace($trimmed) -and $trimmed -ne "!") {
            $commands.Add($trimmed)
        }
    }

    if ($commands.Count -eq 0) {
        throw "Could not read the current SSID profile."
    }

    return $commands.ToArray()
}

function Test-CiscoResponse {
    param([string]$Command, [string]$Response)
    if ($Response -match "(?im)^%\s*(Invalid input|Incomplete command|Ambiguous command|Error|Failed)") {
        throw "Cisco rejected command '$Command'."
    }
}

function Set-WirelessConfiguration {
    param(
        $Session,
        [string]$CurrentSSID,
        [string]$NewSSID,
        [string]$NewWiFiPassword,
        [string]$LogPath
    )

    $script:UpdateLogPath = $LogPath
    $renameSSID = -not [string]::IsNullOrWhiteSpace($NewSSID) -and $NewSSID -ne $CurrentSSID
    $currentSSIDCLI = ConvertTo-CiscoCLIValue -Value $CurrentSSID
    $newSSIDCLI = if ([string]::IsNullOrWhiteSpace($NewSSID)) { "" } else { ConvertTo-CiscoCLIValue -Value $NewSSID }
    $newPasswordCLI = if ([string]::IsNullOrEmpty($NewWiFiPassword)) { "" } else { ConvertTo-CiscoCLIValue -Value $NewWiFiPassword }
    $changePassword = -not [string]::IsNullOrEmpty($NewWiFiPassword)

    if (-not $renameSSID -and -not $changePassword) {
        Write-CiscoLog -LogPath $LogPath -Message "New SSID and New WiFi Password are empty. WiFi settings skipped." -Level "WARN"
        return $CurrentSSID
    }

    if ($renameSSID) {
        Write-CiscoLog -LogPath $LogPath -Message "Renaming Dot11Radio0 SSID from '$CurrentSSID' to '$NewSSID'." -Level "INFO"
        $profileCommands = Get-SSIDProfileCommands -Session $Session

        [void](Invoke-CiscoCommand -Session $Session -Command "configure terminal")
        [void](Invoke-CiscoCommand -Session $Session -Command ("dot11 ssid " + $newSSIDCLI))

        $passwordWasCopied = $false
        foreach ($profileCommand in $profileCommands) {
            if ($profileCommand -match "^wpa-psk\s+") {
                if ($changePassword) { continue }
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

        Write-CiscoLog -LogPath $LogPath -Message "SSID changed to '$NewSSID' on Dot11Radio0." -Level "OK"
        if ($changePassword) {
            Write-CiscoLog -LogPath $LogPath -Message "WPA2 password updated." -Level "OK"
        }
        return $NewSSID
    }

    Write-CiscoLog -LogPath $LogPath -Message "Keeping SSID '$CurrentSSID' and updating WPA2 password." -Level "INFO"
    [void](Invoke-CiscoCommand -Session $Session -Command "configure terminal")
    [void](Invoke-CiscoCommand -Session $Session -Command ("dot11 ssid " + $currentSSIDCLI))
    $passwordCommand = "wpa-psk ascii " + $newPasswordCLI
    $response = Invoke-CiscoCommand -Session $Session -Command $passwordCommand
    Test-CiscoResponse -Command "wpa-psk ascii ********" -Response $response
    [void](Invoke-CiscoCommand -Session $Session -Command "end")
    Write-CiscoLog -LogPath $LogPath -Message "WPA2 password updated." -Level "OK"
    return $CurrentSSID
}

function Save-CiscoConfiguration {
    param($Session, [string]$LogPath)

    Write-CiscoLog -LogPath $LogPath -Message "Saving running configuration (write memory)..." -Level "INFO"
    $saveOutput = Invoke-CiscoCommand -Session $Session -Command "write memory" -TimeoutSeconds 30

    if ($saveOutput -notmatch "\[OK\]") {
        Write-CiscoLog -LogPath $LogPath -Message "write memory did not return [OK]. Review log." -Level "WARN"
        return $false
    }

    Write-CiscoLog -LogPath $LogPath -Message "Startup configuration saved." -Level "OK"
    return $true
}

function Enable-SSHVersion2 {
    param(
        [ref]$SessionReference,
        [string]$IPAddress,
        [string]$Username,
        [string]$Password,
        [string]$LogPath
    )

    $session = $SessionReference.Value

    if ($session.Type -eq "SSH") {
        $sshStatus = Invoke-CiscoCommand -Session $session -Command "show ip ssh" -TimeoutSeconds 20
        if ($sshStatus -match "SSH Enabled\s*-\s*version 2") {
            Write-CiscoLog -LogPath $LogPath -Message "SSH Version 2 is already enabled." -Level "OK"
            return
        }
    }

    $sshStatus = Invoke-CiscoCommand -Session $session -Command "show ip ssh" -TimeoutSeconds 20
    if ($sshStatus -match "SSH Enabled\s*-\s*version 2") {
        Write-CiscoLog -LogPath $LogPath -Message "SSH Version 2 is already enabled." -Level "OK"
        return
    }

    $identity = Invoke-CiscoCommand -Session $session -Command "show running-config | include ^hostname|^ip domain-name" -TimeoutSeconds 15
    $hasHostname = $identity -match "(?m)^hostname\s+\S+"
    $hasDomain = $identity -match "(?m)^ip domain-name\s+\S+"

    [void](Invoke-CiscoCommand -Session $session -Command "configure terminal")

    if (-not $hasHostname) {
        Write-CiscoLog -LogPath $LogPath -Message "Setting hostname to ap." -Level "WARN"
        [void](Invoke-CiscoCommand -Session $session -Command "hostname ap")
    }
    if (-not $hasDomain) {
        Write-CiscoLog -LogPath $LogPath -Message "Setting ip domain-name samacollege.com." -Level "WARN"
        [void](Invoke-CiscoCommand -Session $session -Command "ip domain-name samacollege.com")
    }

    Write-CiscoLog -LogPath $LogPath -Message "Generating 4096-bit RSA key..." -Level "INFO"

    if ($session.Type -eq "SSH") {
        [void](Invoke-CiscoCommand -Session $session -Command "crypto key generate rsa modulus 4096" -TimeoutSeconds 90)
    }
    else {
        Send-TelnetLine -Session $session -Text "crypto key generate rsa"
        $rsaStep = Read-Until -Session $session -Patterns @(
            "(?i)Do you really want to replace them\?\s*\[yes/no\]:",
            "(?i)How many bits in the modulus.*:",
            "(?m)^[^`r`n]*\(config\)#\s*$"
        ) -TimeoutSeconds 30

        if ($rsaStep.Text -match "(?i)Do you really want to replace them\?") {
            Send-TelnetLine -Session $session -Text "yes"
            $rsaStep = Read-Until -Session $session -Patterns @("(?i)How many bits in the modulus.*:", "(?m)^[^`r`n]*\(config\)#\s*$") -TimeoutSeconds 30
        }

        if ($rsaStep.Text -match "(?i)How many bits in the modulus") {
            Send-TelnetLine -Session $session -Text "4096"
            $rsaFinished = Read-Until -Session $session -Patterns @("(?i)\[OK\]", "(?m)^[^`r`n]*\(config\)#\s*$") -TimeoutSeconds 90
            if ($rsaFinished.Text -notmatch "(?i)\[OK\]") {
                throw "RSA key generation did not return [OK]."
            }
        }
    }

    [void](Invoke-CiscoCommand -Session $session -Command "end" -TimeoutSeconds 10)
    $preCheck = Invoke-CiscoCommand -Session $session -Command "show ip ssh" -TimeoutSeconds 20
    if ($preCheck -match "IOS Keys.*NONE" -or $preCheck -match "Please create RSA keys" -or $preCheck -match "SSH Disabled") {
        throw "IOS still reports no RSA key or SSH disabled after generation."
    }

    [void](Invoke-CiscoCommand -Session $session -Command "configure terminal")
    [void](Invoke-CiscoCommand -Session $session -Command "ip ssh version 2")
    [void](Invoke-CiscoCommand -Session $session -Command "end")
    Save-CiscoConfiguration -Session $session -LogPath $LogPath | Out-Null

    $verification = Invoke-CiscoCommand -Session $session -Command "show ip ssh" -TimeoutSeconds 20
    if ($verification -notmatch "SSH Enabled\s*-\s*version 2") {
        throw "SSH Version 2 verification failed."
    }

    Write-CiscoLog -LogPath $LogPath -Message "SSH Version 2 verified." -Level "OK"
}
