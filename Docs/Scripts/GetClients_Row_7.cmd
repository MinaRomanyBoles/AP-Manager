@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Get-APClients.ps1" -RowNumber 7
if errorlevel 1 pause
