# Excel COM helper — header-based read/write with open workbook support.
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$script:HeaderMap = @{}
$script:ClientsColumnLetter = "K"
$script:ClientsColumnNumber = 11
$script:ClientsColumnWarned = $false

function Release-ComObject {
    param($Object)
    if ($null -ne $Object) {
        try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Object) } catch {}
    }
}

function Get-ProjectRoot {
    return (Split-Path -Parent $PSScriptRoot)
}

function Get-ExpectedWorkbookPath {
    return (Join-Path (Get-ProjectRoot) "AP-Info-Manager.xlsx")
}

function Test-ManagerWorksheet {
    param($Worksheet)
    try {
        $found = 0
        for ($col = 1; $col -le 20; $col++) {
            $header = [Convert]::ToString($Worksheet.Cells.Item(1, $col).Value2, [Globalization.CultureInfo]::InvariantCulture)
            if ($header -match "Access Point IP") { $found++ }
            if ($header -match "Access User") { $found++ }
            if ($header -match "Access Password") { $found++ }
        }
        return ($found -ge 2)
    }
    catch {
        return $false
    }
}

function Find-OpenManagerWorkbook {
    param(
        [Parameter(Mandatory = $true)]$Excel,
        [Parameter(Mandatory = $true)][string]$PackageDirectory
    )

    $packageFullPath = [IO.Path]::GetFullPath($PackageDirectory).TrimEnd('\')
    $fallback = $null

    for ($index = 1; $index -le $Excel.Workbooks.Count; $index++) {
        $candidate = $Excel.Workbooks.Item($index)
        $candidateSheet = $null
        try {
            $candidateSheet = $candidate.Worksheets.Item("Sheet1")
            if (-not (Test-ManagerWorksheet -Worksheet $candidateSheet)) {
                Release-ComObject $candidateSheet
                Release-ComObject $candidate
                continue
            }

            $candidateDirectory = [IO.Path]::GetDirectoryName(
                [Convert]::ToString($candidate.FullName, [Globalization.CultureInfo]::InvariantCulture)
            )
            if (-not [string]::IsNullOrWhiteSpace($candidateDirectory)) {
                $candidateDirectory = [IO.Path]::GetFullPath($candidateDirectory).TrimEnd('\')
            }

            Release-ComObject $candidateSheet

            if ([string]::Equals($candidateDirectory, $packageFullPath, [StringComparison]::OrdinalIgnoreCase)) {
                return $candidate
            }

            if ($null -eq $fallback) { $fallback = $candidate }
            else { Release-ComObject $candidate }
        }
        catch {
            Release-ComObject $candidateSheet
            Release-ComObject $candidate
        }
    }

    return $fallback
}

function Open-WorkbookContext {
    param([switch]$ReadOnly)

    $PackageRoot = Get-ProjectRoot
    $ExpectedWorkbookPath = Get-ExpectedWorkbookPath
    $excel = $null
    $book = $null
    $sheet = $null
    $ownsExcel = $false
    $ownsBook = $false
    $source = "Saved workbook file"

    try {
        try {
            $excel = [Runtime.InteropServices.Marshal]::GetActiveObject("Excel.Application")
            $book = Find-OpenManagerWorkbook -Excel $excel -PackageDirectory $PackageRoot
            if ($null -ne $book) {
                $source = "Live open Excel workbook"
            }
        }
        catch {
            $excel = $null
            $book = $null
        }

        if ($null -eq $book) {
            if ($null -ne $excel) {
                Release-ComObject $excel
                $excel = $null
            }

            $workbookPath = $ExpectedWorkbookPath
            if (-not (Test-Path -LiteralPath $workbookPath)) {
                throw "Excel workbook was not found: $workbookPath"
            }

            $excel = New-Object -ComObject Excel.Application
            $ownsExcel = $true
            $excel.Visible = $false
            $excel.DisplayAlerts = $false
            $book = $excel.Workbooks.Open($workbookPath, 0, [bool]$ReadOnly)
            $ownsBook = $true
        }

        $sheet = $book.Worksheets.Item("Sheet1")
        if (-not (Test-ManagerWorksheet -Worksheet $sheet)) {
            throw "The expected AP Manager headers were not found in Sheet1."
        }

        return [pscustomobject]@{
            Excel = $excel
            Book = $book
            Sheet = $sheet
            OwnsExcel = $ownsExcel
            OwnsBook = $ownsBook
            Source = $source
        }
    }
    catch {
        Release-ComObject $sheet
        if ($ownsBook -and $null -ne $book) {
            try { $book.Close($false) } catch {}
        }
        if ($ownsExcel -and $null -ne $excel) {
            try { $excel.Quit() } catch {}
        }
        Release-ComObject $book
        Release-ComObject $excel

        if ($_.Exception.Message -match "locked|being used|cannot access") {
            throw "Excel file is locked or in use by another process. Close other applications or save and retry."
        }
        throw
    }
}

function Close-WorkbookContext {
    param($Context, [switch]$Save)

    if ($null -eq $Context) { return }

    try {
        if ($Save -and $null -ne $Context.Book) {
            try { $Context.Book.Save() } catch {
                throw "Could not save Excel workbook. The file may be locked: $($_.Exception.Message)"
            }
        }
        if ($Context.OwnsBook -and $null -ne $Context.Book) {
            $Context.Book.Close([bool]$Save)
        }
    }
    finally {
        if ($Context.OwnsExcel -and $null -ne $Context.Excel) {
            try { $Context.Excel.Quit() } catch {}
        }
        Release-ComObject $Context.Sheet
        Release-ComObject $Context.Book
        Release-ComObject $Context.Excel
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
}

function Initialize-HeaderMap {
    param([Parameter(Mandatory = $true)]$Worksheet)

    $script:HeaderMap = @{}
    $aliases = @{
        "Department" = @("Department", "American Department")
        "AccessPointName" = @("Access Point Name", "Access Point")
        "AccessPointIP" = @("Access Point IP", "IP Address", "IP")
        "MacAddress" = @("Access Point Mac Address", "Access Point  Mac Address", "MAC Address", "Mac Address")
        "AccessUser" = @("Access User", "Username")
        "AccessPassword" = @("Access Password", "Password")
        "NewWiFiSSID" = @("New WiFi SSID", "New SSID")
        "NewWiFiPassword" = @("New WiFi Password", "New Password")
        "ClientsStatus" = @("Clients Status", "Get Status", "Get Clients")
        "Clients" = @("Clients", "Client Count")
        "CurrentSSID" = @("Current SSID", "SSID")
        "ConnectionStatus" = @("Connection Status", "Status")
        "LastUpdated" = @("Last Updated", "Last Updated Date")
    }

    for ($col = 1; $col -le 30; $col++) {
        $raw = $Worksheet.Cells.Item(1, $col).Value2
        if ($null -eq $raw) { continue }
        $header = ([Convert]::ToString($raw, [Globalization.CultureInfo]::InvariantCulture)).Trim()
        if ([string]::IsNullOrWhiteSpace($header)) { continue }

        foreach ($key in $aliases.Keys) {
            foreach ($alias in $aliases[$key]) {
                if ($header -eq $alias) {
                    $script:HeaderMap[$key] = $col
                }
            }
        }
    }

    $clientsCol = $script:ClientsColumnNumber
    if ($script:HeaderMap.ContainsKey("Clients") -and $script:HeaderMap["Clients"] -ne $script:ClientsColumnNumber) {
        if (-not $script:ClientsColumnWarned) {
            Write-Warning "Clients header is in column $($script:HeaderMap['Clients']) but reads/writes use column K ($($script:ClientsColumnNumber))."
            $script:ClientsColumnWarned = $true
        }
    }

    if (-not $script:HeaderMap.ContainsKey("AccessPointIP")) {
        throw "Required header 'Access Point IP' was not found."
    }
}

function Get-HeaderColumn {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$Required
    )

    if ($script:HeaderMap.ContainsKey($Name)) {
        return $script:HeaderMap[$Name]
    }

    if ($Required) {
        throw "Required column header '$Name' was not found in the workbook."
    }

    return $null
}

function Get-CellText {
    param(
        [Parameter(Mandatory = $true)]$Worksheet,
        [Parameter(Mandatory = $true)][int]$Row,
        [Parameter(Mandatory = $true)][int]$Column
    )

    $value = $Worksheet.Cells.Item($Row, $Column).Value2
    if ($null -eq $value) { return "" }
    return ([Convert]::ToString($value, [Globalization.CultureInfo]::InvariantCulture)).Trim()
}

function Get-AccessPointRow {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][int]$RowNumber
    )

    Initialize-HeaderMap -Worksheet $Context.Sheet

    $nameCol = Get-HeaderColumn -Name "AccessPointName"
    $ipCol = Get-HeaderColumn -Name "AccessPointIP" -Required
    $macCol = Get-HeaderColumn -Name "MacAddress"
    $userCol = Get-HeaderColumn -Name "AccessUser" -Required
    $passCol = Get-HeaderColumn -Name "AccessPassword" -Required
    $newSsidCol = Get-HeaderColumn -Name "NewWiFiSSID"
    $newPassCol = Get-HeaderColumn -Name "NewWiFiPassword"
    $clientsCol = Get-HeaderColumn -Name "Clients"
    $currentSsidCol = Get-HeaderColumn -Name "CurrentSSID"
    $connCol = Get-HeaderColumn -Name "ConnectionStatus"
    $lastCol = Get-HeaderColumn -Name "LastUpdated"

    $ip = Get-CellText -Worksheet $Context.Sheet -Row $RowNumber -Column $ipCol
    if ([string]::IsNullOrWhiteSpace($ip)) {
        return $null
    }

    $clientsRaw = Get-CellText -Worksheet $Context.Sheet -Row $RowNumber -Column $script:ClientsColumnNumber

    $deptCol = Get-HeaderColumn -Name "Department"

    [pscustomobject]@{
        RowNumber = $RowNumber
        Department = if ($deptCol) { Get-CellText -Worksheet $Context.Sheet -Row $RowNumber -Column $deptCol } else { "" }
        AccessPointName = if ($nameCol) { Get-CellText -Worksheet $Context.Sheet -Row $RowNumber -Column $nameCol } else { "" }
        AccessPointIP = $ip
        MacAddress = if ($macCol) { Get-CellText -Worksheet $Context.Sheet -Row $RowNumber -Column $macCol } else { "" }
        AccessUser = Get-CellText -Worksheet $Context.Sheet -Row $RowNumber -Column $userCol
        AccessPassword = [string]$Context.Sheet.Cells.Item($RowNumber, $passCol).Value2
        NewWiFiSSID = if ($newSsidCol) { Get-CellText -Worksheet $Context.Sheet -Row $RowNumber -Column $newSsidCol } else { "" }
        NewWiFiPassword = if ($newPassCol) { [string]$Context.Sheet.Cells.Item($RowNumber, $newPassCol).Value2 } else { "" }
        Clients = $clientsRaw
        CurrentSSID = if ($currentSsidCol) { Get-CellText -Worksheet $Context.Sheet -Row $RowNumber -Column $currentSsidCol } else { "" }
        ConnectionStatus = if ($connCol) { Get-CellText -Worksheet $Context.Sheet -Row $RowNumber -Column $connCol } else { "" }
        LastUpdated = if ($lastCol) { Get-CellText -Worksheet $Context.Sheet -Row $RowNumber -Column $lastCol } else { "" }
        ExcelSource = $Context.Source
    }
}

function Get-AllAccessPoints {
    param([Parameter(Mandatory = $true)]$Context)

    Initialize-HeaderMap -Worksheet $Context.Sheet
    $ipCol = Get-HeaderColumn -Name "AccessPointIP" -Required
    $usedRange = $Context.Sheet.UsedRange
    $lastRow = $usedRange.Rows.Count
    $results = New-Object System.Collections.Generic.List[object]

    for ($row = 2; $row -le $lastRow; $row++) {
        $ip = Get-CellText -Worksheet $Context.Sheet -Row $row -Column $ipCol
        if ([string]::IsNullOrWhiteSpace($ip)) { continue }
        $ap = Get-AccessPointRow -Context $Context -RowNumber $row
        if ($null -ne $ap) {
            $results.Add($ap)
        }
    }

    return $results
}

function Set-ClientsCell {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][int]$RowNumber,
        [Parameter(Mandatory = $true)]$Value,
        [string]$FontColor = "000000",
        [switch]$Numeric
    )

    $col = $script:ClientsColumnNumber
    $cell = $Context.Sheet.Cells.Item($RowNumber, $col)
    try {
        if ($Numeric) {
            $numberText = [Convert]::ToString([int]$Value, [Globalization.CultureInfo]::InvariantCulture)
            $cell.NumberFormat = "0"
            $cell.FormulaR1C1 = "=" + $numberText
        }
        else {
            $cell.NumberFormat = "General"
            $cell.Value2 = [Convert]::ToString($Value, [Globalization.CultureInfo]::InvariantCulture)
        }

        $cell.HorizontalAlignment = -4108
        $cell.Font.Bold = $true
        $cell.Font.Color = [Convert]::ToInt32(
            $FontColor.Substring(4, 2) + $FontColor.Substring(2, 2) + $FontColor.Substring(0, 2),
            16
        )

        $lastCol = Get-HeaderColumn -Name "LastUpdated"
        if ($lastCol) {
            $lastCell = $Context.Sheet.Cells.Item($RowNumber, $lastCol)
            $lastCell.Value2 = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Release-ComObject $lastCell
        }

        if ($Context.OwnsBook) {
            $Context.Book.Save()
        }
    }
    finally {
        Release-ComObject $cell
    }
}

function Set-AccessPointFields {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][int]$RowNumber,
        [string]$CurrentSSID,
        [switch]$ClearNewSSID,
        [switch]$ClearNewPassword,
        [string]$ConnectionStatus
    )

    Initialize-HeaderMap -Worksheet $Context.Sheet

    if (-not [string]::IsNullOrWhiteSpace($CurrentSSID)) {
        $col = Get-HeaderColumn -Name "CurrentSSID"
        if ($col) {
            $cell = $Context.Sheet.Cells.Item($RowNumber, $col)
            $cell.Value2 = $CurrentSSID
            Release-ComObject $cell
        }
    }

    if ($ClearNewSSID) {
        $col = Get-HeaderColumn -Name "NewWiFiSSID"
        if ($col) {
            $cell = $Context.Sheet.Cells.Item($RowNumber, $col)
            $cell.Value2 = ""
            Release-ComObject $cell
        }
    }

    if ($ClearNewPassword) {
        $col = Get-HeaderColumn -Name "NewWiFiPassword"
        if ($col) {
            $cell = $Context.Sheet.Cells.Item($RowNumber, $col)
            $cell.Value2 = ""
            Release-ComObject $cell
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ConnectionStatus)) {
        $col = Get-HeaderColumn -Name "ConnectionStatus"
        if ($col) {
            $cell = $Context.Sheet.Cells.Item($RowNumber, $col)
            $cell.Value2 = $ConnectionStatus
            Release-ComObject $cell
        }
    }

    $lastCol = Get-HeaderColumn -Name "LastUpdated"
    if ($lastCol) {
        $lastCell = $Context.Sheet.Cells.Item($RowNumber, $lastCol)
        $lastCell.Value2 = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Release-ComObject $lastCell
    }

    if ($Context.OwnsBook) {
        $Context.Book.Save()
    }
}

function Export-AccessPointsJson {
    param([Parameter(Mandatory = $true)]$Context)

    $rows = Get-AllAccessPoints -Context $Context
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

    return ($public | ConvertTo-Json -Depth 5 -Compress)
}
