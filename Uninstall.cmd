@echo off
title QuickLock-USB Uninstall
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\QuickLock.ps1" -Uninstall
pause
