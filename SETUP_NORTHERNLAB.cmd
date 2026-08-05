@echo off
setlocal

set "PROJECT_ROOT=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_ROOT%tools\create_project_shortcut.ps1"
if errorlevel 1 (
    echo.
    echo NorthernLab setup failed.
    echo Pull all Git files and make sure Godot is installed through Steam.
    pause
    exit /b 1
)

echo.
echo NorthernLab is ready.
echo Use NorthernLab.lnk to play or NorthernLab - Editor.lnk to edit.
pause
