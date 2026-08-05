@echo off
setlocal

set "PROJECT_ROOT=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_ROOT%tools\build_northernlab_dev.ps1"
if errorlevel 1 (
    echo.
    echo NorthernLab development build failed.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_ROOT%tools\create_project_shortcut.ps1" -SkipBuild
if errorlevel 1 (
    echo.
    echo NorthernLab shortcut update failed.
    pause
    exit /b 1
)

echo.
echo Development build updated. Launch NorthernLab.lnk or the Steam shortcut.
pause
