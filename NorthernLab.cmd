@echo off
start "NorthernLab Launcher" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0tools\northernlab_launcher.ps1"
