# AP Manager

Local web dashboard for managing Cisco Aironet 3600 Access Points.

## Requirements

- Windows 10/11
- Node.js 18+ LTS
- Microsoft Excel Desktop (for live workbook integration)
- Ethernet connection to APs during configuration changes
- PowerShell 5.1+

## Quick Start

1. Run `Install-AP-Manager.bat`
2. Run `Start-AP-Manager.bat`
3. Open http://127.0.0.1:8787
4. Stop with `Stop-AP-Manager.bat`

## Project Structure

```
AP Manager/
├── frontend/          React + Vite + TypeScript + Tailwind
├── backend/           Node.js + Express + TypeScript
├── Scripts/           PowerShell automation (Excel, SSH/Telnet)
├── Backups/           Running-config backups
├── Logs/              Operation logs
├── Runtime/           PID and temp files
├── AP-Info-Manager.xlsx
├── logo.png
└── *.bat              Install / Start / Stop
```

## Security

- Server binds to `127.0.0.1:8787` only (local access)
- Passwords are read from Excel on the backend; never sent to the browser
- CSRF protection on mutating API calls
- Allowed PowerShell scripts whitelist

## Excel

Data is read/written via Excel COM automation. If Excel is open, live cell values are used. Client counts are always written to column K.

See `README-Arabic.txt` for full Arabic documentation.
