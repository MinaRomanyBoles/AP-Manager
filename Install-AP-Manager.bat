@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ============================================================
echo   AP Manager - Installation
echo ============================================================
echo.

where node >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Node.js is not installed or not in PATH.
    echo Download Node.js LTS from https://nodejs.org/
    goto :fail
)

echo [OK] Node.js found:
node --version
echo.

echo Installing backend dependencies...
cd backend
call npm install
if errorlevel 1 goto :fail
cd ..

echo.
echo Installing frontend dependencies...
cd frontend
call npm install
if errorlevel 1 goto :fail
cd ..

echo.
echo Installing Posh-SSH PowerShell module (for SSH support)...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "if (-not (Get-Module -ListAvailable -Name Posh-SSH)) { Install-Module -Name Posh-SSH -Scope CurrentUser -Force -AllowClobber; Write-Host '[OK] Posh-SSH installed.' } else { Write-Host '[OK] Posh-SSH already installed.' }"
if errorlevel 1 (
    echo [WARN] Posh-SSH installation failed. Telnet fallback will still work.
)

echo.
echo Building frontend...
cd frontend
call npm run build
if errorlevel 1 goto :fail
cd ..

echo.
echo Building backend...
cd backend
call npm run build
if errorlevel 1 goto :fail
cd ..

echo.
echo ============================================================
echo   Installation completed successfully!
echo   Run Start-AP-Manager.bat to launch the dashboard.
echo ============================================================
pause
exit /b 0

:fail
echo.
echo [ERROR] Installation failed. Review the messages above.
pause
exit /b 1
