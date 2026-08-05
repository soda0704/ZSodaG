$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$localEditor = Join-Path $PSScriptRoot ".local\godotsteam-editor\godot.exe"
$setupScript = Join-Path $PSScriptRoot "setup_godotsteam_editor.ps1"

if (-not (Test-Path -LiteralPath $localEditor)) {
    & $setupScript
}

if (-not (Test-Path -LiteralPath $localEditor)) {
    throw "GodotSteam-compatible editor was not created: $localEditor"
}

Start-Process `
    -FilePath $localEditor `
    -ArgumentList @("--editor", "--path", $projectRoot) `
    -WorkingDirectory $projectRoot
