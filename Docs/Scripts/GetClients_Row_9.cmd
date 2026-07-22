@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Get-APClients.ps1" -RowNumber 9
if errorlevel 1 pause
