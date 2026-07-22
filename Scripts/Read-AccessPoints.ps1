[CmdletBinding()]
param(
    [string]$OutputJsonPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "Json-Helper.ps1")
. (Join-Path $PSScriptRoot "Excel-Helper.ps1")

$context = $null
try {
    $context = Open-WorkbookContext -ReadOnly
    $rows = Get-AllAccessPoints -Context $context
    $public = foreach ($row in $rows) {
        [pscustomobject]@{
            rowNumber = $row.RowNumber
            accessPointName = $row.AccessPointName
            accessPointIP = $row.AccessPointIP
            macAddress = $row.MacAddress
            accessUser = $row.AccessUser
            hasAccessPassword = -not [string]::IsNullOrEmpty($row.AccessPassword)
            currentSSID = $row.CurrentSSID
            newWiFiSSID = $row.NewWiFiSSID
            hasNewWiFiPassword = -not [string]::IsNullOrEmpty($row.NewWiFiPassword)
            clients = $row.Clients
            connectionStatus = $row.ConnectionStatus
            lastUpdated = $row.LastUpdated
        }
    }

    $meta = [pscustomobject]@{
        success = $true
        source = $context.Source
        lastSync = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        accessPoints = @($public)
    }

    if ($OutputJsonPath) {
        Write-JsonFile -Path $OutputJsonPath -Object $meta
    }
    else {
        Write-Output ($meta | ConvertTo-Json -Depth 8 -Compress)
    }
}
catch {
    $errorObj = [pscustomobject]@{
        success = $false
        error = $_.Exception.Message
    }
    $output = $errorObj | ConvertTo-Json -Compress
    if ($OutputJsonPath) {
        Write-JsonFile -Path $OutputJsonPath -Object $errorObj
    }
    else {
        Write-Output $output
    }
    exit 1
}
finally {
    Close-WorkbookContext -Context $context
}
