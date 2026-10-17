@echo off
title QuickLock-USB Setup
echo ============================================
echo   QuickLock-USB Setup
echo   1. Choose your USB key   2. Enable auto-start
echo ============================================
echo.
echo Plug in the USB drive you want to use as your key, then press any key.
pause >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\QuickLock.ps1" -Register
if errorlevel 1 goto failed
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\QuickLock.ps1" -Install
if errorlevel 1 goto failed
echo.
echo Setup complete. Pull out your USB key to test it - Windows will lock.
pause
exit /b 0
:failed
echo.
echo Setup did not finish. See the error above, or docs\Troubleshooting.md
pause
exit /b 1
