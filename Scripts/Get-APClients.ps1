[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [int]$RowNumber
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$PackageRoot = Split-Path -Parent $PSScriptRoot
$ExpectedWorkbookPath = Join-Path $PackageRoot "AP-Info-Manager.xlsx"
$SheetName = "Sheet1"
$ResultColumn = 11 # Column K

function Release-ComObject {
    param($Object)
    if ($null -ne $Object) {
        try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Object) } catch {}
    }
}

function Test-ManagerWorksheet {
    param($Worksheet)

    try {
        $ipHeader = [Convert]::ToString($Worksheet.Cells.Item(1, 3).Value2, [Globalization.CultureInfo]::InvariantCulture)
        $userHeader = [Convert]::ToString($Worksheet.Cells.Item(1, 5).Value2, [Globalization.CultureInfo]::InvariantCulture)
        $passwordHeader = [Convert]::ToString($Worksheet.Cells.Item(1, 6).Value2, [Globalization.CultureInfo]::InvariantCulture)
        return (
            $ipHeader -match "Access Point IP" -and
            $userHeader -match "Access User" -and
            $passwordHeader -match "Access Password"
        )
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
            $candidateSheet = $candidate.Worksheets.Item($SheetName)
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

            if ($null -eq $fallback) {
                $fallback = $candidate
            }
            else {
                Release-ComObject $candidate
            }
        }
        catch {
            Release-ComObject $candidateSheet
            Release-ComObject $candidate
        }
    }

    return $fallback
}

function Open-WorkbookContext {
    $excel = $null
    $book = $null
    $sheet = $null
    $ownsExcel = $false
    $ownsBook = $false

    try {
        try {
            $excel = [Runtime.InteropServices.Marshal]::GetActiveObject("Excel.Application")
            $book = Find-OpenManagerWorkbook -Excel $excel -PackageDirectory $PackageRoot
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
                $candidate = Get-ChildItem -LiteralPath $PackageRoot -Filter "*.xlsx" -File |
                    Where-Object { $_.Name -notlike "~$*" } |
                    Select-Object -First 1

                if ($null -eq $candidate) {
                    throw "Excel workbook was not found in $PackageRoot."
                }
                $workbookPath = $candidate.FullName
            }

            $excel = New-Object -ComObject Excel.Application
            $ownsExcel = $true
            $excel.Visible = $false
            $excel.DisplayAlerts = $false
            $book = $excel.Workbooks.Open($workbookPath, 0, $false)
            $ownsBook = $true
        }

        $sheet = $book.Worksheets.Item($SheetName)
        if (-not (Test-ManagerWorksheet -Worksheet $sheet)) {
            throw "The expected AP Manager headers were not found in $SheetName."
        }

        return [pscustomobject]@{
            Excel = $excel
            Book = $book
            Sheet = $sheet
            OwnsExcel = $ownsExcel
            OwnsBook = $ownsBook
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
        throw
    }
}

function Close-WorkbookContext {
    param($Context)

    if ($null -eq $Context) { return }

    try {
        if ($Context.OwnsBook -and $null -ne $Context.Book) {
            $Context.Book.Save()
            $Context.Book.Close($true)
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

function Set-ResultCell {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Value,
        [string]$FontColor = "000000",
        [switch]$Numeric
    )

    $cell = $Context.Sheet.Cells.Item($RowNumber, $ResultColumn)
    try {
        # Excel COM can fail when an Int32 is passed through a late-bound Value2 setter.
        # For numeric results, use a tiny numeric formula (for example =2), which keeps
        # the cell numeric while passing a String to COM. Status values remain plain text.
        if ($Numeric) {
            $numberText = [Convert]::ToString(
                [int]$Value,
                [Globalization.CultureInfo]::InvariantCulture
            )
            $cell.NumberFormat = "0"
            $cell.FormulaR1C1 = "=" + $numberText
        }
        else {
            $cell.NumberFormat = "General"
            $cell.Value2 = [Convert]::ToString(
                $Value,
                [Globalization.CultureInfo]::InvariantCulture
            )
        }

        $cell.HorizontalAlignment = -4108 # xlCenter
        $cell.Font.Bold = $true
        $cell.Font.Color = [Convert]::ToInt32(
            $FontColor.Substring(4, 2) + $FontColor.Substring(2, 2) + $FontColor.Substring(0, 2),
            16
        )

        if ($Context.OwnsBook) {
            $Context.Book.Save()
        }
    }
    finally {
        Release-ComObject $cell
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
        [int]$TimeoutSeconds = 20
    )

    $allText = ""
    $watch = [Diagnostics.Stopwatch]::StartNew()

    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $chunk = Read-TelnetChunk -Session $Session -IdleMilliseconds 250 -MaximumMilliseconds 1200
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

    throw "Timed out waiting for the Cisco prompt. Received: $allText"
}

function Invoke-CiscoCommand {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string]$Command,
        [int]$TimeoutSeconds = 25
    )

    Send-TelnetLine -Session $Session -Text $Command
    $result = Read-Until -Session $Session -Patterns @("(?m)^[^`r`n]*#\s*$") -TimeoutSeconds $TimeoutSeconds

    if ($result.Text -match "(?im)^%\s*(Invalid input|Incomplete command|Ambiguous command|Error|Failed)") {
        throw "Cisco rejected command '$Command'."
    }

    return $result.Text
}

function Connect-CiscoTelnet {
    param(
        [Parameter(Mandatory = $true)][string]$IPAddress,
        [Parameter(Mandatory = $true)][string]$Username,
        [Parameter(Mandatory = $true)][string]$Password
    )

    $client = New-Object Net.Sockets.TcpClient
    $async = $client.BeginConnect($IPAddress, 23, $null, $null)

    if (-not $async.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds(10))) {
        $client.Close()
        throw "Telnet port 23 did not respond on $IPAddress."
    }

    $client.EndConnect($async)
    $client.ReceiveTimeout = 4000
    $client.SendTimeout = 5000

    $session = [pscustomobject]@{
        Client = $client
        Stream = $client.GetStream()
    }

    try {
        $first = Read-Until -Session $session -Patterns @(
            "(?i)Username:",
            "(?i)login:",
            "(?i)Password:",
            "(?m)^[^`r`n]*[>#]\s*$"
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
            "(?m)^[^`r`n]*>\s*$",
            "(?m)^[^`r`n]*#\s*$",
            "(?i)Authentication failed",
            "(?i)Login invalid"
        ) -TimeoutSeconds 15

        if ($login.Text -match "(?i)Authentication failed|(?i)Login invalid") {
            throw "Login failed for $IPAddress."
        }

        if ($login.Text -match "(?m)^[^`r`n]*>\s*$") {
            Send-TelnetLine -Session $session -Text "enable"
            $enablePrompt = Read-Until -Session $session -Patterns @(
                "(?i)Password:",
                "(?m)^[^`r`n]*#\s*$"
            ) -TimeoutSeconds 10

            if ($enablePrompt.Text -match "(?i)Password:") {
                Send-TelnetLine -Session $session -Text $Password
                $enabled = Read-Until -Session $session -Patterns @(
                    "(?m)^[^`r`n]*#\s*$",
                    "(?i)Access denied",
                    "(?i)Bad passwords"
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
        try { $session.Stream.Close() } catch {}
        try { $session.Client.Close() } catch {}
        throw
    }
}

function Close-CiscoTelnet {
    param($Session)
    if ($null -ne $Session) {
        try { $Session.Stream.Close() } catch {}
        try { $Session.Client.Close() } catch {}
    }
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

$context = $null
$session = $null
$currentStage = "initialization"

try {
    $currentStage = "opening the Excel workbook"
    $context = Open-WorkbookContext

    $currentStage = "reading the row values from Excel"
    $ipAddress = Get-CellText -Worksheet $context.Sheet -Row $RowNumber -Column 3
    $username = Get-CellText -Worksheet $context.Sheet -Row $RowNumber -Column 5
    $password = Get-CellText -Worksheet $context.Sheet -Row $RowNumber -Column 6

    if ([string]::IsNullOrWhiteSpace($ipAddress)) {
        throw "Access Point IP is empty in row $RowNumber."
    }
    $parsedIP = $null
    if (-not [Net.IPAddress]::TryParse($ipAddress, [ref]$parsedIP)) {
        throw "Invalid Access Point IP: $ipAddress"
    }
    if ([string]::IsNullOrWhiteSpace($username)) {
        throw "Access User is empty in row $RowNumber."
    }
    if ([string]::IsNullOrEmpty($password)) {
        throw "Access Password is empty in row $RowNumber."
    }

    $currentStage = "writing the pending status to column K"
    Set-ResultCell -Context $context -Value "..." -FontColor "C55A11"
    Write-Host "Connecting to Cisco AP $ipAddress..." -ForegroundColor Cyan

    $currentStage = "connecting to the Cisco AP and entering privileged mode"
    $session = Connect-CiscoTelnet -IPAddress $ipAddress -Username $username -Password $password

    $currentStage = "reading the wireless client associations"
    try {
        $associationOutput = Invoke-CiscoCommand -Session $session -Command "show dot11 associations client" -TimeoutSeconds 35
    }
    catch {
        $associationOutput = Invoke-CiscoCommand -Session $session -Command "show dot11 associations" -TimeoutSeconds 35
    }

    $currentStage = "counting Dot11Radio0 clients"
    $clientCount = [int](Get-Radio0ClientCount -Output $associationOutput)

    $currentStage = "writing the client count to column K"
    Set-ResultCell -Context $context -Value $clientCount -FontColor "008000" -Numeric

    Write-Host "Dot11Radio0 clients: $clientCount" -ForegroundColor Green
    Start-Sleep -Seconds 1
}
catch {
    if ($null -ne $context) {
        try { Set-ResultCell -Context $context -Value "ERROR" -FontColor "C00000" } catch {}
    }

    Write-Host "" 
    Write-Host ("ERROR during " + $currentStage + ": " + $_.Exception.Message) -ForegroundColor Red
    if ($null -ne $_.InvocationInfo -and $_.InvocationInfo.ScriptLineNumber -gt 0) {
        Write-Host ("Script line: " + $_.InvocationInfo.ScriptLineNumber) -ForegroundColor DarkYellow
    }
    Write-Host "The Clients cell in column K was set to ERROR." -ForegroundColor Yellow
    Read-Host "Press Enter to close"
    exit 1
}
finally {
    Close-CiscoTelnet -Session $session
    Close-WorkbookContext -Context $context
}
