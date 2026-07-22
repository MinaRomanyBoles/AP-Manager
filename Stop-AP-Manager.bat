@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set RUNTIME=%~dp0Runtime
set PIDFILE=%RUNTIME%\server.pid
set PORT=8787

echo Stopping AP Manager...

if exist "%PIDFILE%" (
    set /p SERVER_PID=<"%PIDFILE%"
    echo Stopping process PID !SERVER_PID!...
    taskkill /PID !SERVER_PID! /F >nul 2>&1
    del "%PIDFILE%" 2>nul
)

for /f "tokens=5" %%p in ('netstat -aon ^| find "127.0.0.1:%PORT%" ^| find "LISTENING"') do (
    echo Stopping listener on port %PORT% PID %%p...
    taskkill /PID %%p /F >nul 2>&1
)

if exist "%RUNTIME%\*.json" del /Q "%RUNTIME%\*.json" 2>nul

echo AP Manager stopped.
pause
exit /b 0
