param(
    [Parameter(Mandatory = $true)]
    [int]$RowNumber
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$mainScript = Join-Path $PSScriptRoot "AP-Manager.ps1"
$packageRoot = Split-Path -Parent $PSScriptRoot
$workbookPath = Join-Path $packageRoot "AP-Info-Manager.xlsx"
$sheetName = "Sheet1"
$runtimeDirectory = Join-Path $packageRoot "Runtime"
New-Item -ItemType Directory -Path $runtimeDirectory -Force | Out-Null

function Get-CellText {
    param(
        [Parameter(Mandatory = $true)]$Worksheet,
        [Parameter(Mandatory = $true)][int]$Row,
        [Parameter(Mandatory = $true)][int]$Column,
        [switch]$Trim
    )

    $value = $Worksheet.Cells.Item($Row, $Column).Value2
    if ($null -eq $value) {
        return ""
    }

    $text = [string]$value
    if ($Trim) {
        return $text.Trim()
    }

    return $text
}

function Get-RowDataFromWorksheet {
    param(
        [Parameter(Mandatory = $true)]$Worksheet,
        [Parameter(Mandatory = $true)][int]$Row,
        [Parameter(Mandatory = $true)][string]$Source
    )

    [pscustomobject]@{
        Department      = Get-CellText -Worksheet $Worksheet -Row $Row -Column 1
        AccessPointName = Get-CellText -Worksheet $Worksheet -Row $Row -Column 2
        IPAddress       = Get-CellText -Worksheet $Worksheet -Row $Row -Column 3 -Trim
        MacAddress      = Get-CellText -Worksheet $Worksheet -Row $Row -Column 4 -Trim
        Username        = Get-CellText -Worksheet $Worksheet -Row $Row -Column 5 -Trim
        Password        = Get-CellText -Worksheet $Worksheet -Row $Row -Column 6
        NewSSID         = Get-CellText -Worksheet $Worksheet -Row $Row -Column 7 -Trim
        NewWiFiPassword = Get-CellText -Worksheet $Worksheet -Row $Row -Column 8
        ExcelSource     = $Source
        CapturedAt      = (Get-Date).ToString("o")
    }
}

function Find-OpenWorkbook {
    param(
        [Parameter(Mandatory = $true)]$Excel,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $targetFullPath = [IO.Path]::GetFullPath($TargetPath)
    $nameMatches = @()

    for ($index = 1; $index -le $Excel.Workbooks.Count; $index++) {
        $candidate = $Excel.Workbooks.Item($index)
        try {
            $candidateFullPath = [IO.Path]::GetFullPath([string]$candidate.FullName)
            if ([string]::Equals($candidateFullPath, $targetFullPath, [StringComparison]::OrdinalIgnoreCase)) {
                return $candidate
            }

            if ([string]::Equals([string]$candidate.Name, [IO.Path]::GetFileName($TargetPath), [StringComparison]::OrdinalIgnoreCase)) {
                $nameMatches += $candidate
            }
            else {
                [void][Runtime.InteropServices.Marshal]::ReleaseComObject($candidate)
            }
        }
        catch {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($candidate)
        }
    }

    if ($nameMatches.Count -eq 1) {
        return $nameMatches[0]
    }

    foreach ($match in $nameMatches) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($match)
    }

    return $null
}

function Get-CurrentExcelRowData {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$WorksheetName,
        [Parameter(Mandatory = $true)][int]$Row
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Workbook not found: $Path"
    }

    $excel = $null
    $book = $null
    $sheet = $null
    $ownsExcel = $false
    $ownsBook = $false

    try {
        # This launcher runs before elevation, so it can read the values currently
        # displayed in the already-open Excel workbook, including unsaved edits.
        try {
            $excel = [Runtime.InteropServices.Marshal]::GetActiveObject("Excel.Application")
            $book = Find-OpenWorkbook -Excel $excel -TargetPath $Path
        }
        catch {
            $excel = $null
            $book = $null
        }

        if ($null -ne $book) {
            $sheet = $book.Worksheets.Item($WorksheetName)
            return Get-RowDataFromWorksheet -Worksheet $sheet -Row $Row -Source "Live open Excel cells"
        }

        # Fallback for direct CMD execution when the workbook is not open.
        if ($null -ne $excel) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
            $excel = $null
        }

        $excel = New-Object -ComObject Excel.Application
        $ownsExcel = $true
        $excel.Visible = $false
        $excel.DisplayAlerts = $false
        $book = $excel.Workbooks.Open($Path, 0, $true)
        $ownsBook = $true
        $sheet = $book.Worksheets.Item($WorksheetName)
        return Get-RowDataFromWorksheet -Worksheet $sheet -Row $Row -Source "Saved workbook file"
    }
    finally {
        if ($ownsBook -and $null -ne $book) {
            $book.Close($false)
        }
        if ($ownsExcel -and $null -ne $excel) {
            $excel.Quit()
        }

        if ($null -ne $sheet) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($sheet)
        }
        if ($null -ne $book) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($book)
        }
        if ($null -ne $excel) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
        }

        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
}

$inputDataPath = Join-Path $runtimeDirectory ("AP_Row_{0}_{1}.json" -f $RowNumber, [Guid]::NewGuid().ToString("N"))

try {
    $rowData = Get-CurrentExcelRowData -Path $workbookPath -WorksheetName $sheetName -Row $RowNumber
    $rowData | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $inputDataPath -Encoding UTF8

    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$mainScript`" -WorkbookPath `"$workbookPath`" -SheetName `"$sheetName`" -RowNumber $RowNumber -InputDataPath `"$inputDataPath`""

    $process = Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $arguments -PassThru -Wait
}
finally {
    if (Test-Path -LiteralPath $inputDataPath) {
        Remove-Item -LiteralPath $inputDataPath -Force -ErrorAction SilentlyContinue
    }
}
