param(
    [string]$GodotExecutable = ""
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$godotSteamDirectory = Join-Path $projectRoot "addons\godotsteam"
$requiredGodotSteamFiles = @(
    (Join-Path $godotSteamDirectory "godotsteam.gdextension"),
    (Join-Path $godotSteamDirectory "win64\libgodotsteam.windows.template_debug.x86_64.dll"),
    (Join-Path $godotSteamDirectory "win64\libgodotsteam.windows.template_release.x86_64.dll"),
    (Join-Path $godotSteamDirectory "win64\steam_api64.dll")
)
$localEditorDirectory = Join-Path $PSScriptRoot ".local\godotsteam-editor"
$localEditorExecutable = Join-Path $localEditorDirectory "godot.exe"

$missingGodotSteamFiles = @(
    $requiredGodotSteamFiles |
        Where-Object { -not (Test-Path -LiteralPath $_) }
)
if ($missingGodotSteamFiles.Count -gt 0) {
    throw (
        "GodotSteam is incomplete. Pull all Git files before setup. Missing: " +
        ($missingGodotSteamFiles -join "; ")
    )
}

$steamApiSource = Join-Path $godotSteamDirectory "win64\steam_api64.dll"

if ([string]::IsNullOrWhiteSpace($GodotExecutable)) {
    $steamInstall = Get-ItemPropertyValue `
        -Path "HKCU:\Software\Valve\Steam" `
        -Name "SteamPath" `
        -ErrorAction SilentlyContinue
    $steamLibraries = @()

    if ($steamInstall) {
        $steamLibraries += $steamInstall
        $libraryFile = Join-Path $steamInstall "steamapps\libraryfolders.vdf"
        if (Test-Path -LiteralPath $libraryFile) {
            foreach ($line in Get-Content -LiteralPath $libraryFile) {
                if ($line -match '"path"\s+"([^"]+)"') {
                    $steamLibraries += ($Matches[1] -replace '\\\\', '\')
                }
            }
        }
    }

    foreach ($steamLibrary in $steamLibraries | Select-Object -Unique) {
        $candidate = Join-Path $steamLibrary (
            "steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
        )
        if (Test-Path -LiteralPath $candidate) {
            $GodotExecutable = $candidate
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($GodotExecutable)) {
    $runningGodot = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -like "godot*" -and $_.Path } |
        Select-Object -First 1

    if ($runningGodot) {
        $GodotExecutable = $runningGodot.Path
    }
}

if ([string]::IsNullOrWhiteSpace($GodotExecutable)) {
    $godotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($godotCommand) {
        $GodotExecutable = $godotCommand.Source
    }
}

if (
    [string]::IsNullOrWhiteSpace($GodotExecutable) -or
    -not (Test-Path -LiteralPath $GodotExecutable)
) {
    throw (
        "Godot executable was not found. Run this script while Godot is open " +
        "or pass -GodotExecutable 'C:\path\to\godot.exe'."
    )
}

$resolvedGodotExecutable = (Resolve-Path -LiteralPath $GodotExecutable).Path
New-Item -ItemType Directory -Path $localEditorDirectory -Force | Out-Null
if ($resolvedGodotExecutable -ne $localEditorExecutable) {
    Copy-Item `
        -LiteralPath $resolvedGodotExecutable `
        -Destination $localEditorExecutable `
        -Force
}
Copy-Item -LiteralPath $steamApiSource -Destination (
    Join-Path $localEditorDirectory "steam_api64.dll"
) -Force

Write-Output "GodotSteam-compatible editor prepared:"
Write-Output $localEditorExecutable
Write-Output "Source Godot:"
Write-Output $resolvedGodotExecutable
Write-Output "Launch with:"
Write-Output "& '$localEditorExecutable' --editor --path '$projectRoot'"
