param(
    [string]$Executable,
    [switch]$Graphical,
    [string[]]$Only = @()
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $Executable) { $Executable = Join-Path $projectRoot 'build/windows-dev/NorthernLab.exe' }
$Executable = (Resolve-Path -LiteralPath $Executable).Path
$localGodot = Join-Path $projectRoot 'tools/.local/godotsteam-editor/godot.exe'
$buildLogDirectory = Join-Path $projectRoot ('tools/.local/export-audit-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $buildLogDirectory -Force | Out-Null
# Reuse the launcher's timeout, output capture and engine-error handling.
$parseErrors = $null
$tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $projectRoot 'tools/northernlab_launcher.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw "Launcher parse errors: $parseErrors" }
foreach ($name in @('Get-RuntimeFileHash', 'Copy-LocalRuntimeFile', 'Initialize-ExportAuditRuntime', 'Initialize-LauncherProcessCapture', 'Invoke-GodotBuildStep')) {
    $definition = $ast.Find({ param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    Invoke-Expression $definition.Extent.Text
}
$auditEngine = Initialize-ExportAuditRuntime -BuildDirectory (Split-Path -Parent $Executable) -RuntimeDirectory (Join-Path $projectRoot 'tools/.local/launcher-logs/export-runtime')
$userData = Join-Path $buildLogDirectory 'userdata'
$captures = Join-Path $buildLogDirectory 'screens'
New-Item -ItemType Directory -Path $userData, $captures -Force | Out-Null
$testEnvironment = @{
    APPDATA = $userData
    LOCALAPPDATA = $userData
    NORTHERNLAB_EXPORT_MANIFEST = Join-Path $projectRoot 'tools/.local/export_resources.json'
    NORTHERNLAB_EXPORT_CAPTURE_DIR = $captures
}
$tests = @('export_resources_regression', 'export_new_game_regression', 'controls_binding_regression',
    'expedition_save_slots_regression', 'expedition_resume_regression', 'plant_watering_regression',
    'elevator_reliability_regression', 'medical_corpse_recovery_regression', 'gameplay_polish_regression')
if ($Graphical) { $tests = @('menu_export_render_regression', 'northern_lab_hud_regression', 'export_new_game_regression') }
if ($Only.Count) {
    foreach ($name in $Only) { if ($name -notin $tests) { throw "Unknown test for this mode: $name" } }
    $tests = @($tests | Where-Object { $_ -in $Only })
}
$results = @()
foreach ($test in $tests) {
    Write-Output "Checking exported game: $test"
    $started = Get-Date
    $arguments = @('--path', ('"' + (Split-Path -Parent $Executable) + '"'), '--main-pack', ('"' + $Executable + '"'), '--script', ('"' + (Join-Path $PSScriptRoot "$test.gd") + '"'))
    if ($Graphical) {
        $arguments += @('--windowed', '--resolution', '1280x720', '--max-fps', '60', '--', ('"--capture-dir=' + $captures + '"'))
    } else { $arguments = @('--headless') + $arguments }
    $problem = ''
    try {
        Invoke-GodotBuildStep -Name $test -TimeoutSeconds 240 -Executable $auditEngine -Environment $testEnvironment -Arguments $arguments
        $log = Get-Content -LiteralPath (Join-Path $buildLogDirectory "$test.stdout.log") -Raw
        if ($log -notmatch '(?m)^PASS ' -or $log -match '(?m)^FAIL ') { throw 'Regression did not complete successfully; inspect its log.' }
    } catch { $problem = $_.Exception.Message }
    $count = @((Select-String -LiteralPath (Join-Path $buildLogDirectory "$test.stdout.log") -Pattern '^PASS ')).Count
    $results += [pscustomobject]@{ Test = $test; Passed = ($problem -eq ''); Checks = $count; Seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1); Error = $problem }
    Write-Output ("{0}: {1} checks, {2}" -f $test, $count, $(if ($problem) { $problem } else { 'PASS' }))
    $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $buildLogDirectory 'results.json') -Encoding UTF8
}
Write-Output "Package audit logs: $buildLogDirectory"
if (@($results | Where-Object { -not $_.Passed }).Count) { exit 1 }
exit 0
