param(
    [switch]$BuildOnly
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$launcherScript = $MyInvocation.MyCommand.Path
$backgroundPath = Join-Path $PSScriptRoot "launcher\northernlab_launcher.png"
$localEditorDirectory = Join-Path $PSScriptRoot ".local\godotsteam-editor"
$localGodot = Join-Path $localEditorDirectory "godot.exe"
$godotSteamDirectory = Join-Path $projectRoot "addons\godotsteam"
$outputDirectory = Join-Path $projectRoot "build\windows-dev"
$outputExecutable = Join-Path $outputDirectory "NorthernLab.exe"
$shortcutPath = Join-Path $projectRoot "NorthernLab.lnk"
$settingsDirectory = Join-Path $env:LOCALAPPDATA "NorthernLab"
$settingsPath = Join-Path $settingsDirectory "launcher_settings.json"
$mainMenuVideo = Join-Path $projectRoot "assets\ui\main_menu.ogv"


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
            "The 4K menu video was not downloaded. This project must be " +
            "cloned with Git, not downloaded as a ZIP archive."
        )
    }

    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $gitCommand) {
        throw (
            "Git was not found. Install Git for Windows with Git LFS, " +
            "then run NorthernLab.cmd again."
        )
    }

    & $gitCommand.Source lfs version *> $null
    if ($LASTEXITCODE -ne 0) {
        throw (
            "Git LFS is not installed. Install Git LFS (or enable it in " +
            "Git for Windows), then run NorthernLab.cmd again."
        )
    }

    & $gitCommand.Source -C $projectRoot lfs install --local *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Git LFS could not be initialized for this project."
    }

    & $gitCommand.Source `
        -C $projectRoot `
        lfs pull `
        --include="assets/ui/main_menu.ogv" *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Git LFS could not download the 4K menu video."
    }

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
    if (
        $resolvedSource -ne $resolvedLocal -and
        (
            -not (Test-Path -LiteralPath $localGodot) -or
            (Get-Item -LiteralPath $resolvedSource).Length -ne
                (Get-Item -LiteralPath $localGodot).Length
        )
    ) {
        Copy-Item -LiteralPath $resolvedSource -Destination $localGodot -Force
    }

    Copy-Item `
        -LiteralPath (Join-Path $godotSteamDirectory "win64\steam_api64.dll") `
        -Destination (Join-Path $localEditorDirectory "steam_api64.dll") `
        -Force
}


function Initialize-ExportTemplate {
    $versionOutput = (& $localGodot --version | Select-Object -First 1).Trim()
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
    $powershellExecutable = Join-Path `
        $env:SystemRoot `
        "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path -LiteralPath $powershellExecutable)) {
        $powershellExecutable = (
            Get-Command powershell.exe -ErrorAction Stop
        ).Source
    }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $powershellExecutable
    $shortcut.Arguments = (
        "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden " +
        "-File `"$launcherScript`""
    )
    $shortcut.WorkingDirectory = $projectRoot
    $shortcut.Description = "Build and launch NorthernLab"
    if (Test-Path -LiteralPath $outputExecutable) {
        $shortcut.IconLocation = "$outputExecutable,0"
    }
    $shortcut.Save()
}


function Invoke-DevelopmentBuild {
    param([scriptblock]$StatusCallback)

    if ($StatusCallback) {
        & $StatusCallback "Checking Git LFS, Godot and GodotSteam..."
    }
    Initialize-GitLfsAssets
    Remove-LegacyArtifacts
    Initialize-LocalGodot
    $templateVersion = Initialize-ExportTemplate

    if ($StatusCallback) {
        & $StatusCallback "Building NorthernLab ($templateVersion)..."
    }

    $buildRoot = Join-Path $projectRoot "build"
    New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
    if (Test-Path -LiteralPath $outputDirectory) {
        $resolvedOutput = (Resolve-Path -LiteralPath $outputDirectory).Path
        $resolvedBuildRoot = (Resolve-Path -LiteralPath $buildRoot).Path
        if (
            -not $resolvedOutput.StartsWith(
                $resolvedBuildRoot + "\",
                [System.StringComparison]::OrdinalIgnoreCase
            )
        ) {
            throw "Unsafe build output path: $resolvedOutput"
        }
        Remove-Item -LiteralPath $resolvedOutput -Recurse -Force
    }
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

    $exportArguments = @(
        "--headless",
        "--path",
        "`"$projectRoot`"",
        "--export-debug",
        "`"Windows Dev`"",
        "`"$outputExecutable`""
    )
    $identityProcess = Start-Process `
        -FilePath $localGodot `
        -ArgumentList @("--headless", "--path", "`"$projectRoot`"", "--script", "res://tools/write_build_identity.gd") `
        -WorkingDirectory $projectRoot `
        -WindowStyle Hidden `
        -Wait `
        -PassThru
    if ($identityProcess.ExitCode -ne 0) {
        throw "Could not generate the network build identity."
    }
    $exportProcess = Start-Process `
        -FilePath $localGodot `
        -ArgumentList $exportArguments `
        -WorkingDirectory $projectRoot `
        -WindowStyle Hidden `
        -Wait `
        -PassThru
    if ($exportProcess.ExitCode -ne 0) {
        throw "Godot export failed with code $($exportProcess.ExitCode)."
    }
    if (-not (Test-Path -LiteralPath $outputExecutable)) {
        throw "Godot reported success but did not create $outputExecutable"
    }

    Set-Content `
        -LiteralPath (Join-Path $outputDirectory "steam_appid.txt") `
        -Value "480" `
        -Encoding ASCII
    Copy-Item `
        -LiteralPath (Join-Path $projectRoot "game_actions_480.vdf") `
        -Destination (Join-Path $outputDirectory "game_actions_480.vdf") `
        -Force

    Copy-Item -LiteralPath (Join-Path $projectRoot "assets/monsters/ATTRIBUTION.md") -Destination (Join-Path $outputDirectory "MONSTER_CREDITS.md") -Force

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
            $workingTreeStatus = (& $gitCommand.Source `
                -C $projectRoot status --porcelain 2>$null)
            if (-not [string]::IsNullOrWhiteSpace($workingTreeStatus)) {
                $revision += "-dirty"
            }
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

    New-LauncherShortcut
    if ($StatusCallback) {
        & $StatusCallback "Build ready: build/windows-dev"
    }
    return $outputExecutable
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

    Start-Process `
        -FilePath $outputExecutable `
        -ArgumentList $arguments `
        -WorkingDirectory $outputDirectory
}


if ($BuildOnly) {
    Invoke-DevelopmentBuild {
        param($message)
        Write-Output $message
    } | Out-Null
    Write-Output "NorthernLab build and shortcut are ready."
    exit 0
}


Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NorthernLab Launcher"
        Width="760" Height="760"
        MinWidth="700" MinHeight="700"
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

            <Border Grid.Row="2"
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
                               VerticalAlignment="Center"/>
                </DockPanel>
            </Border>
        </Grid>
    </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
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
    [System.Windows.Forms.Application]::DoEvents()
}

function Invoke-LauncherBuild {
    $playButton.IsEnabled = $false
    $rebuildButton.IsEnabled = $false
    try {
        Invoke-DevelopmentBuild {
            param($message)
            Set-LauncherStatus $message
        } | Out-Null
        Set-LauncherStatus "Ready. Build and shortcut updated." "#55C58A"
        $playButton.IsEnabled = $true
    }
    catch {
        Set-LauncherStatus "Build error: $($_.Exception.Message)" "#E45D53"
        [System.Windows.MessageBox]::Show(
            $_.Exception.Message,
            "NorthernLab - build error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    }
    finally {
        $rebuildButton.IsEnabled = $true
    }
}

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

[void]$window.ShowDialog()
