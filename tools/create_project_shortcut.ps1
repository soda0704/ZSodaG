$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$editorLauncher = Join-Path $PSScriptRoot "launch_northernlab_editor.ps1"
$gameShortcutPaths = @(
    (Join-Path $projectRoot "NorthernLab.lnk"),
    (Join-Path $projectRoot "NorthernLab - Godot.lnk")
)
$editorShortcutPath = Join-Path $projectRoot "NorthernLab - Editor.lnk"
$localEditor = Join-Path $PSScriptRoot ".local\godotsteam-editor\godot.exe"
$setupScript = Join-Path $PSScriptRoot "setup_godotsteam_editor.ps1"
$powershellExecutable = Join-Path $PSHOME "powershell.exe"

if (-not (Test-Path -LiteralPath $localEditor)) {
    & $setupScript
}

if (-not (Test-Path -LiteralPath $localEditor)) {
    throw "GodotSteam-compatible editor was not created: $localEditor"
}

$shell = New-Object -ComObject WScript.Shell
foreach ($gameShortcutPath in $gameShortcutPaths) {
    $gameShortcut = $shell.CreateShortcut($gameShortcutPath)
    # Steam must launch the rendering process itself for Overlay injection.
    # A PowerShell launcher creates Godot as a child process and is unreliable
    # when the shortcut is added to the Steam library as a non-Steam game.
    $gameShortcut.TargetPath = $localEditor
    $gameShortcut.Arguments = (
        "--path `"$projectRoot`""
    )
    $gameShortcut.WorkingDirectory = $projectRoot
    $gameShortcut.Description = "Start NorthernLab with GodotSteam 4.21"
    if (Test-Path -LiteralPath $localEditor) {
        $gameShortcut.IconLocation = "$localEditor,0"
    }
    $gameShortcut.Save()
}

$editorShortcut = $shell.CreateShortcut($editorShortcutPath)
$editorShortcut.TargetPath = $powershellExecutable
$editorShortcut.Arguments = (
    "-NoProfile -ExecutionPolicy Bypass -File `"$editorLauncher`""
)
$editorShortcut.WorkingDirectory = $projectRoot
$editorShortcut.Description = "Open NorthernLab editor with GodotSteam 4.21"
if (Test-Path -LiteralPath $localEditor) {
    $editorShortcut.IconLocation = "$localEditor,0"
}
$editorShortcut.Save()

foreach ($gameShortcutPath in $gameShortcutPaths) {
    Write-Output "Game shortcut created: $gameShortcutPath"
}
Write-Output "Editor shortcut created: $editorShortcutPath"
