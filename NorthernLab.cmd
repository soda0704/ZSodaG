@echo off
if exist "%~dp0tools\.local\NorthernLabLauncher.exe" (
    start "" "%~dp0tools\.local\NorthernLabLauncher.exe"
) else (
    start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0tools\northernlab_launcher.ps1" -BootstrapOnly
)
