[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [int]$RowNumber,

    [string]$OutputJsonPath,

    [switch]$ShowWindow
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "Json-Helper.ps1")
. (Join-Path $PSScriptRoot "Cisco-Common.ps1")
. (Join-Path $PSScriptRoot "Excel-Helper.ps1")

$projectRoot = Get-ProjectRoot
$logsDir = Join-Path $projectRoot "Logs"
New-Item -ItemType Directory -Path $logsDir -Force | Out-Null

$context = $null
$session = $null
$currentStage = "initialization"
$startTime = Get-Date
$logPath = $null

function Write-OperationLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "OK", "WARN", "ERROR")][string]$Level = "INFO"
    )
    if ($logPath) {
        Write-CiscoLog -LogPath $logPath -Message $Message -Level $Level
    }
}

function Write-JsonResponse {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [int]$ExitCode = 0
    )

    Write-JsonResult -OutputJsonPath $OutputJsonPath -Object $Object -ToStdout:(-not $OutputJsonPath)
    exit $ExitCode
}

try {
    $currentStage = "opening Excel workbook"
    $context = Open-WorkbookContext
    $row = Get-AccessPointRow -Context $context -RowNumber $RowNumber

    if ($null -eq $row) {
        throw "Row $RowNumber is empty or has no Access Point IP."
    }

    $safeIp = $row.AccessPointIP.Replace(".", "_")
    $logPath = Join-Path $logsDir ("Clients_{0}_{1}.log" -f $safeIp, (Get-Date -Format "yyyyMMdd_HHmmss"))
    Write-OperationLog "Started Get Clients for $($row.AccessPointName) ($($row.AccessPointIP))"
    Write-OperationLog "Excel source: $($context.Source)"

    if ([string]::IsNullOrWhiteSpace($row.AccessUser)) {
        throw "Access User is empty in row $RowNumber."
    }
    if ([string]::IsNullOrEmpty($row.AccessPassword)) {
        throw "Access Password is empty in row $RowNumber."
    }

    $parsedIP = $null
    if (-not [Net.IPAddress]::TryParse($row.AccessPointIP, [ref]$parsedIP)) {
        throw "Invalid Access Point IP: $($row.AccessPointIP)"
    }

    $currentStage = "writing pending status"
    Set-ClientsCell -Context $context -RowNumber $RowNumber -Value "..." -FontColor "C55A11"

    $currentStage = "connecting to Cisco AP"
    $session = Connect-CiscoSession -IPAddress $row.AccessPointIP -Username $row.AccessUser -Password $row.AccessPassword
    Write-OperationLog "Connected via $($session.ConnectionType)" "OK"
    Write-OperationLog "Commands: terminal length 0, show dot11 associations client (Dot11Radio0 only)"

    $currentStage = "reading wireless client associations"
    try {
        $associationOutput = Invoke-CiscoCommand -Session $session -Command "show dot11 associations client" -TimeoutSeconds 30
    }
    catch {
        $associationOutput = Invoke-CiscoCommand -Session $session -Command "show dot11 associations" -TimeoutSeconds 30
    }

    $currentStage = "counting Dot11Radio0 clients"
    $clientCount = [int](Get-Radio0ClientCount -Output $associationOutput)
    Write-OperationLog "Dot11Radio0 client count: $clientCount" "OK"

    $currentStage = "writing client count to column K"
    Set-ClientsCell -Context $context -RowNumber $RowNumber -Value $clientCount -FontColor "008000" -Numeric

    $duration = ((Get-Date) - $startTime).TotalSeconds
    Write-OperationLog "Completed in $([math]::Round($duration, 1)) seconds" "OK"

    Write-JsonResponse -Object ([pscustomobject]@{
        success = $true
        rowNumber = $RowNumber
        accessPointName = $row.AccessPointName
        accessPointIP = $row.AccessPointIP
        clients = $clientCount
        connectionType = $session.ConnectionType
        logPath = $logPath
        durationSeconds = [math]::Round($duration, 1)
        lastUpdated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    })
}
catch {
    if ($null -ne $context) {
        try { Set-ClientsCell -Context $context -RowNumber $RowNumber -Value "ERROR" -FontColor "C00000" } catch {}
    }

    $duration = ((Get-Date) - $startTime).TotalSeconds
    if ($logPath) {
        Write-OperationLog "ERROR during ${currentStage}: $($_.Exception.Message)" "ERROR"
        Write-OperationLog "Duration: $([math]::Round($duration, 1)) seconds" "ERROR"
    }

    Write-JsonResponse -ExitCode 1 -Object ([pscustomobject]@{
        success = $false
        rowNumber = $RowNumber
        stage = $currentStage
        error = $_.Exception.Message
        logPath = $logPath
        durationSeconds = [math]::Round($duration, 1)
        clients = "ERROR"
    })
}
finally {
    Close-CiscoSession -Session $session
    Close-WorkbookContext -Context $context
}
