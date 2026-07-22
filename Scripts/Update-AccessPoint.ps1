[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [int]$RowNumber,

    [ValidateSet("all", "ssid", "password")]
    [string]$ApplyMode = "all",

    [string]$OutputJsonPath,

    [switch]$ShowWindow
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "Json-Helper.ps1")
. (Join-Path $PSScriptRoot "Cisco-Common.ps1")
. (Join-Path $PSScriptRoot "Excel-Helper.ps1")

# Reuse update logic from original AP-Manager.ps1 (Telnet-based, proven on Aironet 3600)
. (Join-Path $PSScriptRoot "AP-Manager-Core.ps1")

$projectRoot = Get-ProjectRoot
$logsDir = Join-Path $projectRoot "Logs"
$backupsDir = Join-Path $projectRoot "Backups"
New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
New-Item -ItemType Directory -Path $backupsDir -Force | Out-Null

$context = $null
$session = $null
$currentStage = "initialization"
$startTime = Get-Date
$logPath = $null
$backupPath = $null

function Write-OperationLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "OK", "WARN", "ERROR")][string]$Level = "INFO"
    )
    if ($logPath) {
        Write-CiscoLog -LogPath $logPath -Message $Message -Level $Level
    }
}

try {
    $currentStage = "opening Excel workbook"
    $context = Open-WorkbookContext
    $row = Get-AccessPointRow -Context $context -RowNumber $RowNumber

    if ($null -eq $row) {
        throw "Row $RowNumber is empty or has no Access Point IP."
    }

    $safeIp = $row.AccessPointIP.Replace(".", "_")
    $logPath = Join-Path $logsDir ("Update_{0}_{1}.log" -f $safeIp, (Get-Date -Format "yyyyMMdd_HHmmss"))
    Write-OperationLog "Started Apply Changes for $($row.AccessPointName) ($($row.AccessPointIP))"
    Write-OperationLog "Excel source: $($context.Source)"
    Write-OperationLog "Apply mode: $ApplyMode"

    if ([string]::IsNullOrWhiteSpace($row.AccessUser)) {
        throw "Access User is empty in row $RowNumber."
    }
    if ([string]::IsNullOrEmpty($row.AccessPassword)) {
        throw "Access Password is empty in row $RowNumber."
    }

    $newSSID = $row.NewWiFiSSID
    $newPassword = $row.NewWiFiPassword

    if ($ApplyMode -eq "ssid") {
        $newPassword = ""
    }
    elseif ($ApplyMode -eq "password") {
        $newSSID = ""
    }

    if ([string]::IsNullOrWhiteSpace($newSSID) -and [string]::IsNullOrEmpty($newPassword)) {
        throw "Nothing to apply. New WiFi SSID and New WiFi Password are both empty."
    }

    if (-not [string]::IsNullOrWhiteSpace($newSSID)) {
        if ($newSSID.Length -gt 32) { throw "New SSID must be 32 characters or fewer." }
    }
    if (-not [string]::IsNullOrEmpty($newPassword)) {
        if ($newPassword.Length -lt 8 -or $newPassword.Length -gt 63) {
            throw "WPA2 password must be between 8 and 63 characters."
        }
    }

    Write-OperationLog ("New SSID: {0}" -f $(if ([string]::IsNullOrWhiteSpace($newSSID)) { "<empty: skip>" } else { "'$newSSID'" }))
    Write-OperationLog ("New WiFi Password: {0}" -f $(if ([string]::IsNullOrEmpty($newPassword)) { "<empty: skip>" } else { "<provided: update>" }))

    $currentStage = "connecting to Cisco AP"
    $session = Connect-CiscoSession -IPAddress $row.AccessPointIP -Username $row.AccessUser -Password $row.AccessPassword
    Write-OperationLog "Connected via $($session.ConnectionType)" "OK"

    $currentStage = "creating backup"
    $backupPath = Backup-CiscoConfiguration -Session $session -IPAddress $row.AccessPointIP -BackupsDirectory $backupsDir
    Write-OperationLog "Backup saved: $backupPath" "OK"

    $currentStage = "reading current SSID"
    $oldSSID = Get-CurrentSSID -Session $session
    Write-OperationLog "Current Dot11Radio0 SSID: '$oldSSID'" "OK"

    $currentStage = "updating wireless configuration"
    $finalSSID = Set-WirelessConfiguration -Session $session -CurrentSSID $oldSSID -NewSSID $newSSID -NewWiFiPassword $newPassword -LogPath $logPath

    $passwordUpdated = -not [string]::IsNullOrEmpty($newPassword)
    $ssidChanged = (-not [string]::IsNullOrWhiteSpace($newSSID)) -and ($newSSID -ne $oldSSID)

    $currentStage = "saving configuration"
    $configSaved = Save-CiscoConfiguration -Session $session -LogPath $logPath

    $currentStage = "enabling SSH v2"
    $sshResult = "Failed"
    try {
        Enable-SSHVersion2 -SessionReference ([ref]$session) -IPAddress $row.AccessPointIP -Username $row.AccessUser -Password $row.AccessPassword -LogPath $logPath
        $sshResult = "Enabled"
    }
    catch {
        Write-OperationLog "SSH v2 setup failed: $($_.Exception.Message)" "WARN"
        $sshResult = "Failed"
    }

    $currentStage = "verifying configuration"
    $runningConfig = Invoke-CiscoCommand -Session $session -Command "show running-config" -TimeoutSeconds 60
    $startupConfig = Invoke-CiscoCommand -Session $session -Command "show startup-config" -TimeoutSeconds 60
    $verifiedSSID = Get-CurrentSSID -Session $session

    if ($verifiedSSID -ne $finalSSID) {
        throw "SSID verification failed. Expected '$finalSSID' but found '$verifiedSSID'."
    }

    Write-OperationLog "Configuration verified. Final SSID: '$verifiedSSID'" "OK"

    $currentStage = "updating Excel"
    Set-AccessPointFields -Context $context -RowNumber $RowNumber `
        -CurrentSSID $verifiedSSID `
        -ClearNewSSID:($ssidChanged) `
        -ClearNewPassword:($passwordUpdated) `
        -ConnectionStatus "Online"

    $duration = ((Get-Date) - $startTime).TotalSeconds
    Write-OperationLog "Completed in $([math]::Round($duration, 1)) seconds" "OK"

    $result = [pscustomobject]@{
        success = $true
        rowNumber = $RowNumber
        accessPointName = $row.AccessPointName
        accessPointIP = $row.AccessPointIP
        oldSSID = $oldSSID
        newSSID = $verifiedSSID
        passwordUpdated = $passwordUpdated
        sshV2 = $sshResult
        configurationSaved = $configSaved
        backupPath = $backupPath
        connectionType = $session.ConnectionType
        logPath = $logPath
        durationSeconds = [math]::Round($duration, 1)
        lastUpdated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        clients = $null
    }

    Write-JsonResult -OutputJsonPath $OutputJsonPath -Object $result -ToStdout:(-not $OutputJsonPath)
}
catch {
    $duration = ((Get-Date) - $startTime).TotalSeconds
    if ($logPath) {
        Write-OperationLog "ERROR during ${currentStage}: $($_.Exception.Message)" "ERROR"
    }

    if ($null -ne $context) {
        try {
            Set-AccessPointFields -Context $context -RowNumber $RowNumber -ConnectionStatus "Error"
        }
        catch {}
    }

    $errorResult = [pscustomobject]@{
        success = $false
        rowNumber = $RowNumber
        stage = $currentStage
        error = $_.Exception.Message
        backupPath = $backupPath
        logPath = $logPath
        durationSeconds = [math]::Round($duration, 1)
    }

    Write-JsonResult -OutputJsonPath $OutputJsonPath -Object $errorResult -ToStdout:(-not $OutputJsonPath)
    exit 1
}
finally {
    Close-CiscoSession -Session $session
    Close-WorkbookContext -Context $context
}
