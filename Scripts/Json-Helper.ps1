function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Object
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $json = $Object | ConvertTo-Json -Depth 8 -Compress
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Write-JsonResult {
    param(
        [string]$OutputJsonPath,
        [Parameter(Mandatory = $true)]$Object,
        [switch]$ToStdout
    )

    if ($OutputJsonPath) {
        Write-JsonFile -Path $OutputJsonPath -Object $Object
    }

    if ($ToStdout -or -not $OutputJsonPath) {
        Write-Output ($Object | ConvertTo-Json -Depth 8 -Compress)
    }
}
