param(
    [switch]$BuildOnly,
    [string]$BuildSessionDirectory,
    [switch]$InitializeOnly,
    [switch]$Hosted,
    [switch]$BootstrapOnly
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$launcherScript = $MyInvocation.MyCommand.Path
$backgroundPath = Join-Path $PSScriptRoot "launcher\northernlab_launcher.png"
$applicationIcon = Join-Path $projectRoot "assets\ui\application\northernlab.ico"
$localEditorDirectory = Join-Path $PSScriptRoot ".local\godotsteam-editor"
$localGodot = Join-Path $localEditorDirectory "godot.exe"
$godotSteamDirectory = Join-Path $projectRoot "addons\godotsteam"
$outputDirectory = Join-Path $projectRoot "build\windows-dev"
$outputExecutable = Join-Path $outputDirectory "NorthernLab.exe"
$shortcutPath = Join-Path $projectRoot "NorthernLab.lnk"
$settingsDirectory = Join-Path $env:LOCALAPPDATA "NorthernLab"
$settingsPath = Join-Path $settingsDirectory "launcher_settings.json"
$mainMenuVideo = Join-Path $projectRoot "assets\ui\main_menu.ogv"
$buildLogDirectory = Join-Path $PSScriptRoot ".local\launcher-logs"


function Get-SteamLibraries {
    $libraries = @()
    $steamInstall = Get-ItemPropertyValue `
        -Path "HKCU:\Software\Valve\Steam" `
        -Name "SteamPath" `
        -ErrorAction SilentlyContinue

    if (-not [string]::IsNullOrWhiteSpace($steamInstall)) {
        $libraries += $steamInstall
        $libraryFile = Join-Path $steamInstall "steamapps\libraryfolders.vdf"
        if (Test-Path -LiteralPath $libraryFile) {
            foreach ($line in Get-Content -LiteralPath $libraryFile) {
                if ($line -match '"path"\s+"([^"]+)"') {
                    $libraries += ($Matches[1] -replace '\\\\', '\')
                }
            }
        }
    }

    return @($libraries | Select-Object -Unique)
}


function Find-SteamGodot {
    foreach ($steamLibrary in Get-SteamLibraries) {
        $candidate = Join-Path $steamLibrary (
            "steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
        )
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    $runningGodot = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -like "godot*" -and $_.Path } |
        Select-Object -First 1
    if ($runningGodot) {
        return $runningGodot.Path
    }

    $godotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($godotCommand) {
        return $godotCommand.Source
    }
    return $null
}


function Test-GitLfsPointer {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -gt 1024) {
        return $false
    }
    $firstLine = Get-Content -LiteralPath $Path -TotalCount 1
    return $firstLine -eq "version https://git-lfs.github.com/spec/v1"
}


function Initialize-GitLfsAssets {
    $assetMissing = -not (Test-Path -LiteralPath $mainMenuVideo)
    $assetIsPointer = Test-GitLfsPointer $mainMenuVideo
    if (-not $assetMissing -and -not $assetIsPointer) {
        return
    }

    $gitDirectory = Join-Path $projectRoot ".git"
    if (-not (Test-Path -LiteralPath $gitDirectory)) {
        throw (
            "The menu video was not downloaded. This project must be " +
            "cloned with Git, not downloaded as a ZIP archive."
        )
    }

    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $gitCommand) {
        throw (
            "Git was not found. Install Git for Windows with Git LFS, " +
            "then run northern_lab.cmd again."
        )
    }

    New-Item -ItemType Directory -Path $buildLogDirectory -Force | Out-Null
    Invoke-GodotBuildStep -PlainArguments -Name 'git_lfs_version' -TimeoutSeconds 30 -Executable $gitCommand.Source -Arguments @('lfs', 'version')
    Invoke-GodotBuildStep -PlainArguments -Name 'git_lfs_install' -TimeoutSeconds 30 -Executable $gitCommand.Source -Arguments @('-C', "`"$projectRoot`"", 'lfs', 'install', '--local')
    Invoke-GodotBuildStep -PlainArguments -Name 'git_lfs_pull' -TimeoutSeconds 600 -Executable $gitCommand.Source -Arguments @('-C', "`"$projectRoot`"", 'lfs', 'pull', '--include=assets/ui/main_menu.ogv')

    if (
        -not (Test-Path -LiteralPath $mainMenuVideo) -or
        (Test-GitLfsPointer $mainMenuVideo)
    ) {
        throw (
            "Git LFS finished without downloading assets/ui/main_menu.ogv. " +
            "Check repository access and try again."
        )
    }
}


function Get-RuntimeFileHash {
    param([string]$Path)

    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    $stream = $null
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        return [System.Convert]::ToBase64String($algorithm.ComputeHash($stream))
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        $algorithm.Dispose()
    }
}


function Copy-LocalRuntimeFile {
    param([string]$Source, [string]$Destination)

    if (Test-Path -LiteralPath $Destination) {
        if ((Get-Item -LiteralPath $Source).Length -eq (Get-Item -LiteralPath $Destination).Length -and
            (Get-RuntimeFileHash $Source) -eq (Get-RuntimeFileHash $Destination)) {
            # Loaded runtime files can be read but Windows forbids overwriting them.
            return
        }
    }

    $pending = $Destination + '.pending-' + [guid]::NewGuid().ToString('N')
    try {
        Copy-Item -LiteralPath $Source -Destination $pending
        if (Test-Path -LiteralPath $Destination) {
            # Atomic replacement keeps the existing file intact if it is in use.
            [System.IO.File]::Replace($pending, $Destination, [NullString]::Value)
        }
        else {
            [System.IO.File]::Move($pending, $Destination)
        }
    }
    catch {
        throw "Cannot update $Destination. Close Godot or the test process using this runtime, then retry. Existing runtime files have been kept. $($_.Exception.Message)"
    }
    finally {
        if (Test-Path -LiteralPath $pending) {
            Remove-Item -LiteralPath $pending -Force
        }
    }
}


function Initialize-LocalGodot {
    $requiredFiles = @(
        (Join-Path $godotSteamDirectory "godotsteam.gdextension"),
        (Join-Path $godotSteamDirectory "win64\libgodotsteam.windows.template_debug.x86_64.dll"),
        (Join-Path $godotSteamDirectory "win64\libgodotsteam.windows.template_release.x86_64.dll"),
        (Join-Path $godotSteamDirectory "win64\steam_api64.dll")
    )
    $missingFiles = @(
        $requiredFiles | Where-Object { -not (Test-Path -LiteralPath $_) }
    )
    if ($missingFiles.Count -gt 0) {
        throw "GodotSteam incomplete. Missing: $($missingFiles -join '; ')"
    }

    $sourceGodot = Find-SteamGodot
    if ([string]::IsNullOrWhiteSpace($sourceGodot)) {
        if (Test-Path -LiteralPath $localGodot) {
            return
        }
        throw "Godot was not found. Install it through Steam or add it to PATH."
    }

    New-Item -ItemType Directory -Path $localEditorDirectory -Force | Out-Null
    $resolvedSource = (Resolve-Path -LiteralPath $sourceGodot).Path
    $resolvedLocal = $localGodot
    if (Test-Path -LiteralPath $localGodot) {
        $resolvedLocal = (Resolve-Path -LiteralPath $localGodot).Path
    }
    if ($resolvedSource -ne $resolvedLocal) {
        Copy-LocalRuntimeFile -Source $resolvedSource -Destination $localGodot
    }

    Copy-LocalRuntimeFile `
        -Source (Join-Path $godotSteamDirectory "win64\steam_api64.dll") `
        -Destination (Join-Path $localEditorDirectory "steam_api64.dll")
}


function Initialize-ExportTemplate {
    New-Item -ItemType Directory -Path $buildLogDirectory -Force | Out-Null
    Invoke-GodotBuildStep -Name 'version' -TimeoutSeconds 30 -Arguments @('--version') -OutputCallback {}
    $versionOutput = (Get-Content -LiteralPath (Join-Path $buildLogDirectory 'version.stdout.log') -Encoding UTF8 | Select-Object -First 1).Trim()
    if ($versionOutput -notmatch '^(\d+\.\d+\.\d+\.stable)') {
        throw "Cannot determine Godot template version from: $versionOutput"
    }

    $templateVersion = $Matches[1]
    $templateFileName = "windows_debug_x86_64.exe"
    $templateDirectory = Join-Path $env:APPDATA (
        "Godot\export_templates\$templateVersion"
    )
    $installedTemplate = Join-Path $templateDirectory $templateFileName
    if (Test-Path -LiteralPath $installedTemplate) {
        return $templateVersion
    }

    $sourceTemplate = $null
    foreach ($steamLibrary in Get-SteamLibraries) {
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
            "Export template $templateVersion is not installed. " +
            "In Godot open Editor > Manage Export Templates and install it."
        )
    }

    New-Item -ItemType Directory -Path $templateDirectory -Force | Out-Null
    Copy-Item -LiteralPath $sourceTemplate -Destination $installedTemplate -Force
    return $templateVersion
}


function Remove-LegacyArtifacts {
    $safeBuildRoot = (Join-Path $projectRoot "build")
    foreach ($legacyDirectoryName in @("audit", "dev")) {
        $legacyDirectory = Join-Path $safeBuildRoot $legacyDirectoryName
        if (Test-Path -LiteralPath $legacyDirectory) {
            $resolvedLegacy = (Resolve-Path -LiteralPath $legacyDirectory).Path
            $resolvedBuildRoot = (Resolve-Path -LiteralPath $safeBuildRoot).Path
            if (
                $resolvedLegacy.StartsWith(
                    $resolvedBuildRoot + "\",
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            ) {
                Remove-Item -LiteralPath $resolvedLegacy -Recurse -Force
            }
        }
    }

    foreach ($legacyShortcutName in @(
        "NorthernLab - Editor.lnk",
        "NorthernLab - Godot.lnk",
        "NorthernLab Dev.lnk"
    )) {
        $legacyShortcut = Join-Path $projectRoot $legacyShortcutName
        if (Test-Path -LiteralPath $legacyShortcut) {
            Remove-Item -LiteralPath $legacyShortcut -Force
        }
    }
}


function New-LauncherShortcut {
    $hostExecutable = Initialize-LauncherHost
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $hostExecutable
    $shortcut.Arguments = ''
    $shortcut.WindowStyle = 1
    $shortcut.WorkingDirectory = $projectRoot
    $shortcut.Description = "Build and launch NorthernLab"
    if (Test-Path -LiteralPath $outputExecutable) {
        $shortcut.IconLocation = "$outputExecutable,0"
    }
    else {
        $shortcut.IconLocation = "$applicationIcon,0"
    }
    $shortcut.Save()
}

function Initialize-LauncherHost {
    $source = Join-Path $projectRoot 'tools/launcher/launcher_host.cs'
    $destination = Join-Path $projectRoot 'tools/.local/NorthernLabLauncher.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    $stamp = $destination + '.sha256'
    $hash = Get-RuntimeFileHash $source
    if ((Test-Path -LiteralPath $destination) -and (Test-Path -LiteralPath $stamp) -and (Get-Content -LiteralPath $stamp -Raw).Trim() -eq $hash) { return $destination }
    $pending = Join-Path $projectRoot ('tools/.local/launcher-host-' + [guid]::NewGuid().ToString('N') + '.exe')
    try {
        Add-Type -Path $source -OutputAssembly $pending -OutputType WindowsApplication -ReferencedAssemblies @([System.Management.Automation.PowerShell].Assembly.Location, 'System.Windows.Forms.dll')
        Copy-Item -LiteralPath $pending -Destination $destination -Force
        Set-Content -LiteralPath $stamp -Value $hash -Encoding ASCII
    }
    finally { if (Test-Path -LiteralPath $pending) { Remove-Item -LiteralPath $pending -Force } }
    return $destination
}


function Get-GameVersion {
    $projectConfig = Get-Content -LiteralPath (Join-Path $projectRoot "project.godot") -Raw
    $versionMatch = [regex]::Match($projectConfig, '(?m)^config/version="([^"]+)"\s*$')
    if (-not $versionMatch.Success) {
        throw "Set Application > Config > Version in Godot Project Settings."
    }
    return $versionMatch.Groups[1].Value
}

function Assert-BuildNotRunning {
    if (Test-Path -LiteralPath $outputExecutable) {
        try {
            $handle = [System.IO.File]::Open($outputExecutable, 'Open', 'ReadWrite', 'None')
            $handle.Dispose()
        }
        catch {
            throw "Close NorthernLab.exe before rebuilding. The current build has been kept."
        }
    }
}


function Initialize-ExportAuditRuntime {
    param([string]$BuildDirectory, [string]$RuntimeDirectory)

    New-Item -ItemType Directory -Path $RuntimeDirectory -Force | Out-Null
    # Export templates forbid external scripts. Run their embedded pack with the
    # matching editor and the exact native libraries shipped beside the game.
    $auditEngine = Join-Path $RuntimeDirectory 'godot.exe'
    Copy-LocalRuntimeFile -Source $localGodot -Destination $auditEngine
    foreach ($runtimeFile in Get-ChildItem -LiteralPath $BuildDirectory -File -Filter '*.dll') {
        Copy-LocalRuntimeFile -Source $runtimeFile.FullName -Destination (Join-Path $RuntimeDirectory $runtimeFile.Name)
    }
    foreach ($configurationFile in @('steam_appid.txt', 'game_actions_480.vdf')) {
        Copy-Item -LiteralPath (Join-Path $BuildDirectory $configurationFile) -Destination (Join-Path $RuntimeDirectory $configurationFile) -Force
    }
    return $auditEngine
}

function Initialize-LauncherProcessCapture {
    if (-not ('NorthernLab.Launcher.ProcessCapture' -as [type])) {
        Add-Type -Path (Join-Path $projectRoot 'tools/launcher/process_capture.cs')
    }
}

function Invoke-GodotBuildStep {
    param([string]$Name, [int]$TimeoutSeconds, [string[]]$Arguments, [hashtable]$Environment = @{}, [string]$Executable = $localGodot,
        [scriptblock]$OutputCallback, [scriptblock]$PulseCallback, [switch]$PlainArguments)

    $logPath = Join-Path $buildLogDirectory "$Name.log"
    $stdoutPath = Join-Path $buildLogDirectory "$Name.stdout.log"
    $stderrPath = Join-Path $buildLogDirectory "$Name.stderr.log"
    # Truncate the previous run so a startup failure cannot reuse its success log.
    foreach ($stepLog in @($logPath, $stdoutPath, $stderrPath)) {
        Set-Content -LiteralPath $stepLog -Value "" -Encoding UTF8
    }
    # Native startup/shutdown errors may only appear on stdout/stderr.
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Executable
    $finalArguments = @()
    $insertedLog = $false
    foreach ($argument in $Arguments) {
        if (-not $PlainArguments -and $argument -eq '--' -and -not $insertedLog) {
            $finalArguments += @('--log-file', "`"$logPath`"")
            $insertedLog = $true
        }
        $finalArguments += $argument
    }
    if (-not $PlainArguments -and -not $insertedLog) { $finalArguments += @('--log-file', "`"$logPath`"") }
    $startInfo.Arguments = $finalArguments -join ' '
    $startInfo.WorkingDirectory = if ($Executable -eq $localGodot) { $projectRoot } else { Split-Path -Parent $Executable }
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($key in $Environment.Keys) {
        $startInfo.EnvironmentVariables[$key] = [string]$Environment[$key]
    }
    Initialize-LauncherProcessCapture
    $process = [NorthernLab.Launcher.ProcessCapture]::new($startInfo.FileName, $startInfo.Arguments, $startInfo.WorkingDirectory, $Environment)
    $timedOut = $false
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $process.Start($stdoutPath, $stderrPath)
        while ($true) {
            foreach ($chunk in $process.Drain()) {
                $displayChunk = [regex]::Replace($chunk.Text, '\x1B\[[0-?]*[ -/]*[@-~]', '')
                if ($OutputCallback) { & $OutputCallback $displayChunk $chunk.IsError | Out-Null }
                else { Write-Host -NoNewline $displayChunk }
            }
            if ($PulseCallback) { & $PulseCallback | Out-Null }
            $process.CheckOutput()
            if (-not $process.HasExited -and $clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                $timedOut = $true
                $process.Kill()
            }
            if ($process.HasExited -and $process.OutputFinished) { break }
            if ($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds + 2) { $timedOut = $true; break }
            [System.Threading.Thread]::Sleep(20)
        }
        $exitCode = $process.ExitCode
    }
    finally { $process.Dispose() }
    if ($timedOut) {
        throw "Godot $Name timed out. See $logPath. The current build has been kept."
    }
    $engineError = Select-String -LiteralPath @($logPath, $stdoutPath, $stderrPath) -Pattern '^(SCRIPT ERROR:|ERROR:)' |
        Select-Object -First 1
    if ($exitCode -ne 0 -or $engineError) {
        throw "Godot $Name failed (code $exitCode). See $logPath. $engineError"
    }
}


function Publish-DevelopmentBuild {
    param([string]$StagingDirectory)

    Assert-BuildNotRunning
    $backupDirectory = Join-Path $projectRoot ("build\.windows-dev-previous-" + [guid]::NewGuid().ToString("N"))
    $safeRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot "build"))
    foreach ($candidate in @($StagingDirectory, $outputDirectory, $backupDirectory)) {
        $absolute = [System.IO.Path]::GetFullPath($candidate)
        $leaf = [System.IO.Path]::GetFileName($absolute)
        if ([System.IO.Path]::GetDirectoryName($absolute) -ne $safeRoot -or
            ($leaf -ne 'windows-dev' -and -not $leaf.StartsWith('.windows-dev-'))) {
            throw "Unsafe build publication path: $absolute"
        }
    }
    $hadPrevious = Test-Path -LiteralPath $outputDirectory
    if ($hadPrevious) {
        Move-Item -LiteralPath $outputDirectory -Destination $backupDirectory
    }
    try {
        Move-Item -LiteralPath $StagingDirectory -Destination $outputDirectory
    }
    catch {
        if ($hadPrevious) {
            Move-Item -LiteralPath $backupDirectory -Destination $outputDirectory
        }
        throw
    }
    if ($hadPrevious) {
        Remove-BuildStagingDirectory $backupDirectory
    }
}


function Remove-BuildStagingDirectory {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path) {
        $resolved = (Resolve-Path -LiteralPath $Path).Path
        $safeRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot "build"))
        if ([System.IO.Path]::GetDirectoryName($resolved) -ne $safeRoot -or
            -not [System.IO.Path]::GetFileName($resolved).StartsWith(".windows-dev-")) {
            throw "Unsafe staging path: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}


function Invoke-DevelopmentBuild {
    param([scriptblock]$StatusCallback, [scriptblock]$OutputCallback, [scriptblock]$PulseCallback)

    $buildRoot = Join-Path $projectRoot "build"
    New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
    try {
        $buildLock = [System.IO.File]::Open((Join-Path $buildRoot '.windows-dev.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    }
    catch { throw "Another build is already running. Wait for it to finish before rebuilding." }
    try {
        $stepCallbacks = @{ OutputCallback = $OutputCallback; PulseCallback = $PulseCallback }

        if ($StatusCallback) {
            & $StatusCallback "Checking Git LFS, Godot and GodotSteam..."
        }
        Initialize-GitLfsAssets
        Remove-LegacyArtifacts
        Initialize-LocalGodot
        $templateVersion = Initialize-ExportTemplate

        if ($StatusCallback) {
            & $StatusCallback "Building NorthernLab v$(Get-GameVersion)..."
        }

        Assert-BuildNotRunning
        New-Item -ItemType Directory -Path $buildLogDirectory -Force | Out-Null
        $stagingDirectory = Join-Path $buildRoot (".windows-dev-" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $stagingDirectory -Force | Out-Null
        $stagingExecutable = Join-Path $stagingDirectory "NorthernLab.exe"

        try {
            $exportArguments = @(
                "--headless",
                "--path",
                "`"$projectRoot`"",
                "--export-debug",
                "`"Windows Dev`"",
                "`"$stagingExecutable`""
            )
            if ($StatusCallback) {
                & $StatusCallback "Importing project resources and script classes..."
            }
            # Script mode reads the editor's class cache; refresh it before loading autoloads.
            Invoke-GodotBuildStep @stepCallbacks -Name "import" -TimeoutSeconds 600 -Arguments @(
                "--headless", "--editor", "--path", "`"$projectRoot`"", "--import"
            )
            Invoke-GodotBuildStep @stepCallbacks -Name "identity" -TimeoutSeconds 120 -Arguments @(
                "--headless", "--path", "`"$projectRoot`"", "--script", "res://tools/write_build_identity.gd"
            )
            Invoke-GodotBuildStep @stepCallbacks -Name "resources" -TimeoutSeconds 120 -Arguments @(
                "--headless", "--path", "`"$projectRoot`"", "--script", "res://tools/prepare_export_resources.gd"
            )
            if ($StatusCallback) {
                & $StatusCallback "Exporting NorthernLab v$(Get-GameVersion)..."
            }
            Invoke-GodotBuildStep @stepCallbacks -Name "export" -TimeoutSeconds 600 -Arguments $exportArguments
            if (-not (Test-Path -LiteralPath $stagingExecutable)) {
                throw "Godot reported success but did not create $stagingExecutable"
            }

            Set-Content `
                -LiteralPath (Join-Path $stagingDirectory "steam_appid.txt") `
                -Value "480" `
                -Encoding ASCII
            Copy-Item `
                -LiteralPath (Join-Path $projectRoot "game_actions_480.vdf") `
                -Destination (Join-Path $stagingDirectory "game_actions_480.vdf") `
                -Force

            Copy-Item -LiteralPath (Join-Path $projectRoot "assets/monsters/attribution.md") -Destination (Join-Path $stagingDirectory "MONSTER_CREDITS.md") -Force
            Copy-Item -LiteralPath (Join-Path $projectRoot "assets/environments/snow/mountain_source_license.txt") -Destination (Join-Path $stagingDirectory "MOUNTAIN_CREDITS.txt") -Force
            Copy-Item -LiteralPath (Join-Path $projectRoot "assets/models/pine_tree/attribution.md") -Destination (Join-Path $stagingDirectory "PINE_CREDITS.md") -Force

            Copy-Item -LiteralPath (Join-Path $projectRoot "assets/models/snowmobile_ski_patrol/attribution.md") -Destination (Join-Path $stagingDirectory "SNOWMOBILE_CREDITS.md") -Force
            Copy-Item -LiteralPath (Join-Path $projectRoot "assets/models/lewis_corpse/attribution.md") -Destination (Join-Path $stagingDirectory "CORPSE_CREDITS.md") -Force
            Copy-Item -LiteralPath (Join-Path $projectRoot "assets/models/leather_journal/attribution.md") -Destination (Join-Path $stagingDirectory "JOURNAL_CREDITS.md") -Force
            Copy-Item -LiteralPath (Join-Path $projectRoot "assets/characters/attribution.md") -Destination (Join-Path $stagingDirectory "CHARACTER_CREDITS.md") -Force
            Copy-Item -LiteralPath (Join-Path $projectRoot "assets/models/item_model_credits.md") -Destination (Join-Path $stagingDirectory "item_model_credits.md") -Force

            $revision = "unavailable"
            $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
            if ($gitCommand) {
                Invoke-GodotBuildStep -PlainArguments -Name 'git_revision' -TimeoutSeconds 30 -Executable $gitCommand.Source -Arguments @('-C', "`"$projectRoot`"", 'rev-parse', '--short', 'HEAD') -OutputCallback {}
                $revisionOutput = Get-Content -LiteralPath (Join-Path $buildLogDirectory 'git_revision.stdout.log') -Raw -Encoding UTF8
                if (
                    -not [string]::IsNullOrWhiteSpace($revisionOutput)
                ) {
                    $revision = $revisionOutput.Trim()
                    Invoke-GodotBuildStep -PlainArguments -Name 'git_status' -TimeoutSeconds 30 -Executable $gitCommand.Source -Arguments @('-C', "`"$projectRoot`"", 'status', '--porcelain') -OutputCallback {}
                    $workingTreeStatus = Get-Content -LiteralPath (Join-Path $buildLogDirectory 'git_status.stdout.log') -Raw -Encoding UTF8
                    if (-not [string]::IsNullOrWhiteSpace($workingTreeStatus)) {
                        $revision += "-dirty"
                    }
                }
            }
            Set-Content `
                -LiteralPath (Join-Path $stagingDirectory "build_info.txt") `
                -Value @(
                    "NorthernLab development build"
                    "Revision: $revision"
                    "Built: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')"
                ) `
                -Encoding UTF8

            if ($StatusCallback) {
                & $StatusCallback "Checking packaged resources, New Game and saved-game loading..."
            }
            # Run outside the source project so omitted resources cannot be resolved locally.
            # Redirect user data before autoloads start; never touch the player's real saves.
            $auditUserData = Join-Path $buildLogDirectory ("export-audit-" + [guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Path $auditUserData -Force | Out-Null
            $auditEnvironment = @{
                APPDATA = $auditUserData
                LOCALAPPDATA = $auditUserData
                NORTHERNLAB_EXPORT_MANIFEST = Join-Path $projectRoot "tools/.local/export_resources.json"
            }
            $auditEngine = Initialize-ExportAuditRuntime -BuildDirectory $stagingDirectory -RuntimeDirectory (Join-Path $buildLogDirectory 'export-runtime')
            foreach ($audit in @('export_resources_regression', 'export_new_game_regression')) {
                if ($StatusCallback) {
                    $auditMessage = if ($audit -eq 'export_resources_regression') {
                        "Checking packaged resources (1/3)..."
                    } else { "Checking New Game, save and Continue (2/3)..." }
                    & $StatusCallback $auditMessage
                }
                $auditScript = Join-Path $projectRoot "tools/tests/$audit.gd"
                Invoke-GodotBuildStep @stepCallbacks -Name $audit -TimeoutSeconds 180 -Environment $auditEnvironment -Executable $auditEngine -Arguments @(
                    "--headless", "--path", "`"$stagingDirectory`"",
                    "--main-pack", "`"$stagingExecutable`"", "--script", "`"$auditScript`""
                )
            }
            if ($StatusCallback) { & $StatusCallback "Checking game executable startup (3/3)..." }
            Invoke-GodotBuildStep @stepCallbacks -Name 'export_startup' -TimeoutSeconds 60 -Environment $auditEnvironment -Executable $stagingExecutable -Arguments @(
                '--headless', '--', '--startup-check'
            )
            if ($StatusCallback) { & $StatusCallback "Publishing verified build to build/windows-dev..." }
            Publish-DevelopmentBuild $stagingDirectory
        }
        finally {
            Remove-BuildStagingDirectory $stagingDirectory
        }
        New-LauncherShortcut
        if ($StatusCallback) {
            & $StatusCallback "Build ready: build/windows-dev"
        }
        return $outputExecutable
    }
    finally { $buildLock.Dispose() }
}


function Get-LauncherSettings {
    $defaults = [ordered]@{
        Resolution = "1920x1080"
        WindowMode = "fullscreen"
        Screen = 0
        VSync = $true
        MasterVolume = 80.0
        MusicVolume = 70.0
        MouseSensitivity = 1.0
    }
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        return [PSCustomObject]$defaults
    }
    try {
        $saved = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json
        foreach ($property in $saved.PSObject.Properties) {
            if ($null -ne $property.Value) {
                $defaults[$property.Name] = $property.Value
            }
        }
    }
    catch {
        # Invalid settings should never prevent a development build.
    }
    return [PSCustomObject]$defaults
}


function Save-LauncherSettings {
    param($Settings)
    New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null
    $Settings | ConvertTo-Json -Depth 8 | Set-Content `
        -LiteralPath $settingsPath `
        -Encoding UTF8
}


function Start-NorthernLab {
    param($Settings)
    if (-not (Test-Path -LiteralPath $outputExecutable)) {
        throw "Build was not found: $outputExecutable"
    }

    $arguments = @()
    switch ($Settings.WindowMode) {
        "windowed" { $arguments += "--windowed" }
        "maximized" { $arguments += "--maximized" }
        default { $arguments += "--fullscreen" }
    }
    if (-not [string]::IsNullOrWhiteSpace($Settings.Resolution)) {
        $arguments += @("--resolution", $Settings.Resolution)
    }
    $arguments += @("--screen", [string]$Settings.Screen)
    if (-not [bool]$Settings.VSync) {
        $arguments += "--disable-vsync"
    }

    # Suppress a console without hiding the interactive game window.
    $gameStart = [System.Diagnostics.ProcessStartInfo]::new()
    $gameStart.FileName = $outputExecutable
    $gameStart.Arguments = $arguments -join ' '
    $gameStart.WorkingDirectory = $outputDirectory
    $gameStart.UseShellExecute = $false
    $gameStart.CreateNoWindow = $true
    $gameProcess = [System.Diagnostics.Process]::Start($gameStart)
    $gameProcess.Dispose()
}

function Write-BuildSessionState {
    param([string]$Directory, [string]$State, [string]$Message)
    $path = Join-Path $Directory 'state.json'
    $pending = Join-Path $Directory 'state.pending.json'
    [IO.File]::WriteAllText($pending, (@{ state = $State; message = $Message; updated = (Get-Date).ToString('o') } | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $path) { [IO.File]::Replace($pending, $path, [System.Management.Automation.Language.NullString]::Value) }
    else { [IO.File]::Move($pending, $path) }
}

if ($BuildOnly) {
    try {
        Invoke-DevelopmentBuild -StatusCallback {
            param($message)
            if ($BuildSessionDirectory) { Write-BuildSessionState $BuildSessionDirectory 'running' $message }
            Write-Host $message
        } -PulseCallback {
            if ($BuildSessionDirectory -and (Test-Path -LiteralPath (Join-Path $BuildSessionDirectory 'cancel.flag'))) {
                throw [System.OperationCanceledException]::new('Build cancelled by the launcher.')
            }
        } | Out-Null
        if ($BuildSessionDirectory) { Write-BuildSessionState $BuildSessionDirectory 'complete' 'Ready. Build and shortcut updated.' }
        Write-Output "NorthernLab build and shortcut are ready."
    }
    catch {
        if ($BuildSessionDirectory) { Write-BuildSessionState $BuildSessionDirectory 'failed' $_.Exception.ToString() }
        Write-Error $_ -ErrorAction Continue
        if ($Hosted) { throw }
        exit 1
    }
    if ($Hosted) { return }
    exit 0
}

if ($BootstrapOnly) {
    New-LauncherShortcut
    Start-Process -FilePath (Initialize-LauncherHost) -WindowStyle Hidden
    return
}


Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NorthernLab Launcher"
        Width="760" Height="900"
        MinWidth="700" MinHeight="620"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResizeWithGrip"
        Background="#071018">
    <Grid x:Name="RootGrid">
        <Grid.Background>
            <SolidColorBrush Color="#071018"/>
        </Grid.Background>
        <Rectangle>
            <Rectangle.Fill>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                    <GradientStop Color="#44030A10" Offset="0"/>
                    <GradientStop Color="#AA071018" Offset="0.58"/>
                    <GradientStop Color="#F2071018" Offset="1"/>
                </LinearGradientBrush>
            </Rectangle.Fill>
        </Rectangle>

        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <Grid Margin="40,34">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <StackPanel>
                <TextBlock Text="NORTHERN LAB"
                           Foreground="#F4F8FA"
                           FontFamily="Segoe UI Semibold"
                           FontSize="34"
                           FontWeight="SemiBold"/>
                <TextBlock Text="DEVELOPMENT LAUNCHER"
                           Margin="2,2,0,0"
                           Foreground="#8EB2C5"
                           FontFamily="Segoe UI"
                           FontSize="12"/>
            </StackPanel>

            <Border Grid.Row="1"
                    Width="370"
                    HorizontalAlignment="Right"
                    VerticalAlignment="Center"
                    Padding="24"
                    CornerRadius="8"
                    Background="#DD0A151D"
                    BorderBrush="#385364"
                    BorderThickness="1">
                <StackPanel>
                    <TextBlock Text="&#x41D;&#x410;&#x421;&#x422;&#x420;&#x41E;&#x419;&#x41A;&#x418; &#x417;&#x410;&#x41F;&#x423;&#x421;&#x41A;&#x410;"
                               Foreground="#F0F5F7"
                               FontSize="17"
                               FontWeight="SemiBold"
                               Margin="0,0,0,20"/>

                    <TextBlock Text="&#x420;&#x435;&#x436;&#x438;&#x43C; &#x43E;&#x43A;&#x43D;&#x430;" Foreground="#9CB4C1" FontSize="12"/>
                    <ComboBox x:Name="WindowModeBox" Height="34" Margin="0,6,0,14">
                        <ComboBoxItem Tag="fullscreen" Content="&#x41F;&#x43E;&#x43B;&#x43D;&#x44B;&#x439; &#x44D;&#x43A;&#x440;&#x430;&#x43D;"/>
                        <ComboBoxItem Tag="windowed" Content="&#x41E;&#x43A;&#x43E;&#x43D;&#x43D;&#x44B;&#x439;"/>
                        <ComboBoxItem Tag="maximized" Content="&#x420;&#x430;&#x437;&#x432;&#x451;&#x440;&#x43D;&#x443;&#x442;&#x43E;&#x435; &#x43E;&#x43A;&#x43D;&#x43E;"/>
                    </ComboBox>

                    <TextBlock Text="&#x420;&#x430;&#x437;&#x440;&#x435;&#x448;&#x435;&#x43D;&#x438;&#x435;" Foreground="#9CB4C1" FontSize="12"/>
                    <ComboBox x:Name="ResolutionBox" Height="34" Margin="0,6,0,14"/>

                    <TextBlock Text="&#x41C;&#x43E;&#x43D;&#x438;&#x442;&#x43E;&#x440;" Foreground="#9CB4C1" FontSize="12"/>
                    <ComboBox x:Name="ScreenBox" Height="34" Margin="0,6,0,14"/>

                    <CheckBox x:Name="VSyncBox"
                              Content="&#x412;&#x435;&#x440;&#x442;&#x438;&#x43A;&#x430;&#x43B;&#x44C;&#x43D;&#x430;&#x44F; &#x441;&#x438;&#x43D;&#x445;&#x440;&#x43E;&#x43D;&#x438;&#x437;&#x430;&#x446;&#x438;&#x44F;"
                              Foreground="#D5E1E7"
                              Margin="0,2,0,22"/>

                    <Button x:Name="PlayButton"
                            Content="&#x418;&#x413;&#x420;&#x410;&#x422;&#x42C;"
                            Height="46"
                            IsEnabled="False"
                            Background="#B72B24"
                            Foreground="White"
                            BorderBrush="#E45D53"
                            FontSize="15"
                            FontWeight="SemiBold"/>
                    <Grid Margin="0,10,0,0">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="10"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Button x:Name="RebuildButton" Content="&#x41F;&#x415;&#x420;&#x415;&#x421;&#x41E;&#x411;&#x420;&#x410;&#x422;&#x42C;" Height="34"/>
                        <Button x:Name="OpenBuildButton" Grid.Column="2" Content="&#x41F;&#x410;&#x41F;&#x41A;&#x410; BUILD" Height="34"/>
                    </Grid>
                </StackPanel>
            </Border>

            <StackPanel Grid.Row="2">
            <Border
                    Padding="14,10"
                    CornerRadius="5"
                    Background="#C40A151D"
                    BorderBrush="#2D4857"
                    BorderThickness="1">
                <DockPanel>
                    <Ellipse x:Name="StatusDot" Width="8" Height="8" Fill="#D6A338" Margin="0,0,10,0"/>
                    <TextBlock x:Name="StatusText"
                               Text="Preparing launcher..."
                               Foreground="#D6E2E8"
                               FontSize="12"
                               TextWrapping="Wrap"
                               VerticalAlignment="Center"/>
                </DockPanel>
            </Border>
            <ProgressBar x:Name="BuildProgress" Height="3" Margin="0,6,0,6"
                         IsIndeterminate="False" Visibility="Collapsed"/>
            <Expander Header="Build log" Foreground="#9CB4C1" IsExpanded="True" Margin="0,6,0,0">
                <TextBox x:Name="BuildLog" Height="110" IsReadOnly="True" IsUndoEnabled="False"
                         Background="#DD0A151D" Foreground="#D6E2E8" BorderBrush="#2D4857"
                         FontFamily="Consolas" FontSize="11" Padding="8"
                         VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
            </Expander>
            </StackPanel>
        </Grid>
        </ScrollViewer>
    </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$window.Height = [Math]::Min($window.Height, [System.Windows.SystemParameters]::WorkArea.Height)
$window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([System.Uri]::new($applicationIcon))
$rootGrid = $window.FindName("RootGrid")
$windowModeBox = $window.FindName("WindowModeBox")
$resolutionBox = $window.FindName("ResolutionBox")
$screenBox = $window.FindName("ScreenBox")
$vSyncBox = $window.FindName("VSyncBox")
$playButton = $window.FindName("PlayButton")
$rebuildButton = $window.FindName("RebuildButton")
$openBuildButton = $window.FindName("OpenBuildButton")
$statusText = $window.FindName("StatusText")
$statusDot = $window.FindName("StatusDot")
$buildLog = $window.FindName("BuildLog")
$buildProgress = $window.FindName("BuildProgress")
$script:buildInProgress = $false
$script:buildCancelled = $false

if (Test-Path -LiteralPath $backgroundPath) {
    $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.UriSource = [System.Uri]::new($backgroundPath)
    $bitmap.EndInit()
    $brush = New-Object System.Windows.Media.ImageBrush
    $brush.ImageSource = $bitmap
    $brush.Stretch = [System.Windows.Media.Stretch]::UniformToFill
    $brush.AlignmentX = [System.Windows.Media.AlignmentX]::Center
    $brush.AlignmentY = [System.Windows.Media.AlignmentY]::Center
    $rootGrid.Background = $brush
}

foreach ($resolution in @(
    "3840x2160",
    "2560x1440",
    "1920x1080",
    "1600x900",
    "1366x768",
    "1280x720"
)) {
    [void]$resolutionBox.Items.Add($resolution)
}
$screens = [System.Windows.Forms.Screen]::AllScreens
for ($screenIndex = 0; $screenIndex -lt $screens.Count; $screenIndex++) {
    $screen = $screens[$screenIndex]
    $label = "Screen $($screenIndex + 1) - $($screen.Bounds.Width)x$($screen.Bounds.Height)"
    [void]$screenBox.Items.Add($label)
}

$script:launcherSettings = Get-LauncherSettings
for ($modeIndex = 0; $modeIndex -lt $windowModeBox.Items.Count; $modeIndex++) {
    if (
        [string]$windowModeBox.Items[$modeIndex].Tag -eq
        [string]$script:launcherSettings.WindowMode
    ) {
        $windowModeBox.SelectedIndex = $modeIndex
        break
    }
}
if ($windowModeBox.SelectedIndex -lt 0) {
    $windowModeBox.SelectedIndex = 0
}
$resolutionBox.SelectedItem = [string]$script:launcherSettings.Resolution
$screenBox.SelectedIndex = [Math]::Min(
    [Math]::Max([int]$script:launcherSettings.Screen, 0),
    [Math]::Max($screenBox.Items.Count - 1, 0)
)
$vSyncBox.IsChecked = [bool]$script:launcherSettings.VSync

function Update-SettingsFromUi {
    $script:launcherSettings.Resolution = [string]$resolutionBox.SelectedItem
    $script:launcherSettings.WindowMode = [string]$windowModeBox.SelectedItem.Tag
    $script:launcherSettings.Screen = [int]$screenBox.SelectedIndex
    $script:launcherSettings.VSync = [bool]$vSyncBox.IsChecked
    Save-LauncherSettings $script:launcherSettings
}

function Set-LauncherStatus {
    param(
        [string]$Message,
        [string]$Color = "#D6A338"
    )
    $statusText.Text = $Message
    $statusDot.Fill = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($Color)
    )

}

function Add-LauncherBuildOutput {
    param([string]$Text)
    if ($buildLog.Text.Length -gt 60000) { $buildLog.Text = $buildLog.Text.Substring($buildLog.Text.Length - 40000) }
    $buildLog.AppendText([regex]::Replace($Text, '\x1B\[[0-?]*[ -/]*[@-~]', ''))
    $buildLog.ScrollToEnd()
}

function Update-LauncherBuild {
    if (-not $script:buildInProgress -or $null -eq $script:buildWorker) { return }
    try {
        foreach ($chunk in $script:buildWorker.Drain()) { Add-LauncherBuildOutput $chunk.Text }
        $statePath = Join-Path $script:buildSession 'state.json'
        $state = $null
        if (Test-Path -LiteralPath $statePath) {
            $stateFile = [IO.File]::Open($statePath, 'Open', 'Read', ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            $stateReader = [IO.StreamReader]::new($stateFile, [Text.Encoding]::UTF8)
            try { $state = $stateReader.ReadToEnd() | ConvertFrom-Json }
            finally { $stateReader.Dispose() }
            if (-not $script:closeAfterBuild) { Set-LauncherStatus $state.message }
        }
        $script:buildWorker.CheckOutput()
        if (-not $script:buildWorker.HasExited -or -not $script:buildWorker.OutputFinished) { return }
        $exitCode = $script:buildWorker.ExitCode
        $script:buildWorker.Dispose()
        $script:buildWorker = $null
        $script:buildTimer.Stop()
        $script:buildInProgress = $false
        $buildProgress.IsIndeterminate = $false
        $buildProgress.Visibility = 'Collapsed'
        $rebuildButton.IsEnabled = $true
        if ($exitCode -eq 0 -and $state -and $state.state -eq 'complete' -and (Test-Path -LiteralPath $outputExecutable)) {
            Set-LauncherStatus 'Ready. Build and shortcut updated.' '#55C58A'
            $playButton.IsEnabled = $true
        }
        else {
            $message = if ($state -and $state.state -eq 'failed') { $state.message } else {
                "Build worker stopped unexpectedly (code $exitCode). Logs: $script:buildSession"
            }
            Add-LauncherBuildOutput "`r`n$message`r`n"
            Set-LauncherStatus "Build error. Logs: $script:buildSession" '#E45D53'
        }
        [IO.File]::WriteAllText((Join-Path $script:buildSession 'ui-result.json'), (@{
            hostPid = $PID; workerExitCode = $exitCode; playEnabled = $playButton.IsEnabled
            status = $statusText.Text; completedAt = (Get-Date).ToString('o')
        } | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
        if ($script:closeAfterBuild) { $window.Close() }
    }
    catch {
        # A display/logging failure must not bring down the launcher or worker.
        $detail = $_.ToString()
        try { Set-LauncherStatus "Launcher error: $detail" '#E45D53' } catch {}
        try { [IO.File]::AppendAllText((Join-Path $script:buildSession 'launcher-error.log'), $detail + "`r`n") } catch {}
    }
}

function Invoke-LauncherBuild {
    if ($script:buildInProgress) { return }
    $script:closeAfterBuild = $false
    $buildLog.Clear()
    $playButton.IsEnabled = $false
    try {
        Initialize-LauncherProcessCapture
        $script:buildSession = Join-Path $buildLogDirectory ('sessions/' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:buildSession -Force | Out-Null
        $hostExecutable = Initialize-LauncherHost
        $workerArguments = '--build "' + $script:buildSession + '"'
        $script:buildWorker = [NorthernLab.Launcher.ProcessCapture]::new($hostExecutable, $workerArguments, $projectRoot, @{})
        $script:buildWorker.Start((Join-Path $script:buildSession 'worker.stdout.log'), (Join-Path $script:buildSession 'worker.stderr.log'))
        $script:buildInProgress = $true
        $rebuildButton.IsEnabled = $false
        $buildProgress.Visibility = 'Visible'
        $buildProgress.IsIndeterminate = $true
        Set-LauncherStatus 'Starting build...'
        $script:buildTimer.Start()
    }
    catch {
        if ($script:buildWorker) { $script:buildWorker.Dispose(); $script:buildWorker = $null }
        $script:buildInProgress = $false
        $rebuildButton.IsEnabled = $true
        Set-LauncherStatus "Build error: $($_.Exception.Message)" '#E45D53'
        Add-LauncherBuildOutput $_.Exception.ToString()
    }
}

$script:buildWorker = $null
$script:closeAfterBuild = $false
$script:buildTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:buildTimer.Interval = [TimeSpan]::FromMilliseconds(100)
$script:buildTimer.Add_Tick({ Update-LauncherBuild })

$window.Add_Closing({
    param($sender, $eventArgs)
    if ($script:buildInProgress) {
        $eventArgs.Cancel = $true
        $script:closeAfterBuild = $true
        [IO.File]::WriteAllText((Join-Path $script:buildSession 'cancel.flag'), 'cancel')
        Set-LauncherStatus 'Stopping build safely...'
    }
})

$window.Add_ContentRendered({
    Invoke-LauncherBuild
})

$playButton.Add_Click({
    try {
        Update-SettingsFromUi
        Start-NorthernLab $script:launcherSettings
        $window.Close()
    }
    catch {
        Set-LauncherStatus "Launch error: $($_.Exception.Message)" "#E45D53"
    }
})

$rebuildButton.Add_Click({
    Invoke-LauncherBuild
})

$openBuildButton.Add_Click({
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    Start-Process explorer.exe -ArgumentList @("`"$outputDirectory`"")
})

$windowModeBox.Add_SelectionChanged({ Update-SettingsFromUi })
$resolutionBox.Add_SelectionChanged({ Update-SettingsFromUi })
$screenBox.Add_SelectionChanged({ Update-SettingsFromUi })
$vSyncBox.Add_Click({ Update-SettingsFromUi })

if (-not $InitializeOnly) { [void]$window.ShowDialog() }
