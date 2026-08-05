$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$localGodot = Join-Path $PSScriptRoot ".local\godotsteam-editor\godot.exe"
$setupScript = Join-Path $PSScriptRoot "setup_godotsteam_editor.ps1"
$outputDirectory = Join-Path $projectRoot "build\dev"
$outputExecutable = Join-Path $outputDirectory "NorthernLab.exe"

if (-not (Test-Path -LiteralPath $localGodot)) {
    & $setupScript
}
if (-not (Test-Path -LiteralPath $localGodot)) {
    throw "GodotSteam-compatible editor is unavailable: $localGodot"
}

$versionOutput = (& $localGodot --version | Select-Object -First 1).Trim()
if ($versionOutput -notmatch '^(\d+\.\d+\.\d+\.stable)') {
    throw "Could not determine Godot template version from: $versionOutput"
}
$templateVersion = $Matches[1]
$templateFileName = "windows_debug_x86_64.exe"
$sourceTemplate = ""

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
        "steamapps\common\Godot Engine\editor_data\export_templates\" +
        "$templateVersion\$templateFileName"
    )
    if (Test-Path -LiteralPath $candidate) {
        $sourceTemplate = $candidate
        break
    }
}

if ([string]::IsNullOrWhiteSpace($sourceTemplate)) {
    throw (
        "Windows debug export template $templateVersion was not found in " +
        "the Steam Godot installation. Install Export Templates in Godot."
    )
}

$templateDirectory = Join-Path $env:APPDATA (
    "Godot\export_templates\$templateVersion"
)
$localTemplate = Join-Path $templateDirectory $templateFileName
New-Item -ItemType Directory -Path $templateDirectory -Force | Out-Null
if (
    -not (Test-Path -LiteralPath $localTemplate) -or
    (Get-Item -LiteralPath $localTemplate).Length -ne
        (Get-Item -LiteralPath $sourceTemplate).Length
) {
    Write-Output "Preparing Windows debug export template..."
    Copy-Item -LiteralPath $sourceTemplate -Destination $localTemplate -Force
}

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
Write-Output "Building NorthernLab development executable..."
$exportArguments = @(
    "--headless"
    "--path"
    "`"$projectRoot`""
    "--export-debug"
    "`"Windows Dev`""
    "`"$outputExecutable`""
)
$exportProcess = Start-Process `
    -FilePath $localGodot `
    -ArgumentList $exportArguments `
    -WorkingDirectory $projectRoot `
    -WindowStyle Hidden `
    -Wait `
    -PassThru
if ($exportProcess.ExitCode -ne 0) {
    throw "Godot development export failed with code $($exportProcess.ExitCode)"
}
if (-not (Test-Path -LiteralPath $outputExecutable)) {
    throw "Godot reported success but did not create $outputExecutable"
}

Set-Content `
    -LiteralPath (Join-Path $outputDirectory "steam_appid.txt") `
    -Value "480" `
    -Encoding ASCII

$revision = "unavailable"
$gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
if ($gitCommand) {
    $revisionOutput = (& $gitCommand.Source `
        -C $projectRoot rev-parse --short HEAD 2>$null)
    if (
        $LASTEXITCODE -eq 0 -and
        -not [string]::IsNullOrWhiteSpace($revisionOutput)
    ) {
        $revision = $revisionOutput.Trim()
    }
}
Set-Content `
    -LiteralPath (Join-Path $outputDirectory "build_info.txt") `
    -Value @(
        "NorthernLab development build"
        "Revision: $revision"
        "Built: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')"
    ) `
    -Encoding UTF8

Write-Output "Development build ready:"
Write-Output $outputExecutable
