$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$localRuntime = Join-Path $PSScriptRoot ".local\godotsteam-editor\godot.exe"
$setupScript = Join-Path $PSScriptRoot "setup_godotsteam_editor.ps1"

if (-not (Test-Path -LiteralPath $localRuntime)) {
    & $setupScript
}

if (-not (Test-Path -LiteralPath $localRuntime)) {
    throw "GodotSteam-compatible runtime was not created: $localRuntime"
}

Start-Process `
    -FilePath $localRuntime `
    -ArgumentList @("--path", $projectRoot) `
    -WorkingDirectory $projectRoot
