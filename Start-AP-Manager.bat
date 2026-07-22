@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set RUNTIME=%~dp0Runtime
set PIDFILE=%RUNTIME%\server.pid
set PORT=8787

if not exist "%RUNTIME%" mkdir "%RUNTIME%"

if exist "%PIDFILE%" (
    set /p OLD_PID=<"%PIDFILE%"
    tasklist /FI "PID eq !OLD_PID!" 2>nul | find /I "node.exe" >nul
    if not errorlevel 1 (
        echo AP Manager is already running on http://127.0.0.1:%PORT%  (PID !OLD_PID!)
        start "" "http://127.0.0.1:%PORT%"
        exit /b 0
    )
    del "%PIDFILE%" 2>nul
)

where node >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Node.js not found. Run Install-AP-Manager.bat first.
    pause
    exit /b 1
)

if not exist "%~dp0frontend\dist\index.html" (
    echo Building frontend...
    cd frontend
    call npm run build
    cd ..
)

if not exist "%~dp0backend\dist\index.js" (
    echo Building backend...
    cd backend
    call npm run build
    cd ..
)

echo Starting AP Manager backend on http://127.0.0.1:%PORT% ...
start "AP Manager Backend" /MIN cmd /c "cd /d "%~dp0backend" && node dist\index.js >> "%RUNTIME%\server.log" 2>&1"

echo Waiting for server to start...
timeout /t 3 /nobreak >nul

for /f "tokens=2" %%a in ('tasklist /FI "WINDOWTITLE eq AP Manager Backend*" /FO LIST ^| find "PID:"') do set SERVER_PID=%%a

if not defined SERVER_PID (
    for /f "tokens=5" %%p in ('netstat -aon ^| find ":%PORT%" ^| find "LISTENING"') do set SERVER_PID=%%p
)

if defined SERVER_PID (
    echo !SERVER_PID!>"%PIDFILE%"
    echo Server PID: !SERVER_PID!
) else (
    echo [WARN] Could not detect server PID. Check Runtime\server.log
)

start "" "http://127.0.0.1:%PORT%"
echo AP Manager started.
exit /b 0
