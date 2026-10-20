$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$launcher = Join-Path $repoRoot 'tools/northernlab_launcher.ps1'
$parseErrors = $null
$tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($launcher, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw "Launcher parse errors: $parseErrors" }
# Load helpers without opening the launcher or touching the real game build.
foreach ($name in @('Assert-BuildNotRunning', 'Publish-DevelopmentBuild', 'Remove-BuildStagingDirectory', 'Initialize-LauncherProcessCapture', 'Invoke-GodotBuildStep', 'Invoke-DevelopmentBuild', 'Get-RuntimeFileHash', 'Copy-LocalRuntimeFile', 'Initialize-LocalGodot')) {
    $definition = $ast.Find({ param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    Invoke-Expression $definition.Extent.Text
}
$projectRoot = $repoRoot
Initialize-LauncherProcessCapture
$testRoot = Join-Path $repoRoot ('tools/.local/launcher-test-' + [guid]::NewGuid().ToString('N'))
$projectRoot = $testRoot
$outputDirectory = Join-Path $projectRoot 'build/windows-dev'
$outputExecutable = Join-Path $outputDirectory 'NorthernLab.exe'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
Set-Content -LiteralPath $outputExecutable -Value 'previous build'
try {
    $buildLock = [System.IO.File]::Open((Join-Path $projectRoot 'build/.windows-dev.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    try {
        $blocked = $false
        try { Invoke-DevelopmentBuild } catch { $blocked = $_.Exception.Message -like '*Another build is already running*' }
        if (-not $blocked) { throw 'Concurrent builds can overwrite the same logs and runtime.' }
    }
    finally { $buildLock.Dispose() }
    Remove-Item -LiteralPath (Join-Path $projectRoot 'build/.windows-dev.lock')
    Write-Output 'PASS Concurrent builds are rejected before changing resources or logs.'

    Add-Type -AssemblyName PresentationFramework, System.Windows.Forms
    $xamlAssignment = $ast.Find({ param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$xaml'
    }, $true)
    $xamlLiteral = $xamlAssignment.Find({ param($node)
        $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
    }, $true)
    $testWindow = [Windows.Markup.XamlReader]::Parse($xamlLiteral.Value)
    $logControl = $testWindow.FindName('BuildLog')
    if ($null -eq $logControl -or -not $logControl.IsReadOnly -or $null -eq $testWindow.FindName('BuildProgress')) {
        throw 'Launcher is missing its visible build log or progress indicator.'
    }
    Write-Output 'PASS Launcher markup loads with a visible build log and progress indicator.'

    # Exercise the real initializer with a shared-read lock like a loaded DLL.
    $godotSteamDirectory = Join-Path $testRoot 'addon'
    $localEditorDirectory = Join-Path $testRoot 'editor'
    $localGodot = Join-Path $localEditorDirectory 'godot.exe'
    $sourceEngine = Join-Path $testRoot 'source-godot.exe'
    New-Item -ItemType Directory -Path (Join-Path $godotSteamDirectory 'win64'), $localEditorDirectory | Out-Null
    foreach ($path in @('godotsteam.gdextension', 'win64/libgodotsteam.windows.template_debug.x86_64.dll', 'win64/libgodotsteam.windows.template_release.x86_64.dll', 'win64/steam_api64.dll')) {
        Set-Content -LiteralPath (Join-Path $godotSteamDirectory $path) -Value 'old runtime'
    }
    Set-Content -LiteralPath $sourceEngine -Value 'old engine'
    function Find-SteamGodot { return $sourceEngine }
    Initialize-LocalGodot
    $runtime = Join-Path $localEditorDirectory 'steam_api64.dll'
    $lock = [System.IO.File]::Open($runtime, 'Open', 'Read', 'Read')
    try {
        Initialize-LocalGodot
        Write-Output 'PASS An unchanged Steam DLL can remain loaded during initialization.'
        Set-Content -LiteralPath (Join-Path $godotSteamDirectory 'win64/steam_api64.dll') -Value 'new runtime'
        $failed = $false
        try { Initialize-LocalGodot } catch {
            $failed = $true
            if ($_.Exception.Message -notlike '*Close Godot*') { throw }
        }
        if (-not $failed -or (Get-Content -LiteralPath $runtime) -ne 'old runtime') {
            throw 'A changed, locked Steam DLL was not protected.'
        }
        Write-Output 'PASS A changed, loaded Steam DLL is preserved with a useful retry message.'
    }
    finally { $lock.Dispose() }
    Set-Content -LiteralPath $sourceEngine -Value 'new engine'
    Initialize-LocalGodot
    if ((Get-Content -LiteralPath $runtime) -ne 'new runtime' -or (Get-Content -LiteralPath $localGodot) -ne 'new engine') {
        throw 'Unlocked runtime updates were not installed, including a same-size engine update.'
    }
    if (@(Get-ChildItem -LiteralPath $localEditorDirectory -Filter '*.pending-*').Count -ne 0) {
        throw 'Runtime initialization left pending files behind.'
    }
    Write-Output 'PASS Unlocked runtime files update by content and leave no pending files.'

    $buildLogDirectory = Join-Path $testRoot 'logs'
    New-Item -ItemType Directory -Path $buildLogDirectory | Out-Null
    $localGodot = (Get-Command powershell.exe -ErrorAction Stop).Source
    $fakeEngine = Join-Path $testRoot 'fake-engine.ps1'
    Set-Content -LiteralPath $fakeEngine -Encoding UTF8 -Value @'
$mode = $args[0]
$logPath = $args[$args.Count - 1]
Set-Content -LiteralPath $logPath -Value 'Engine started'
[Console]::Out.WriteLine('Console output captured')
if ($mode -eq 'large-output') {
    $line = 'x' * 1024
    for ($index = 0; $index -lt 256; $index++) {
        [Console]::Out.WriteLine($line)
        [Console]::Error.WriteLine($line)
    }
}
if ($mode -eq 'stderr-error') {
    [Console]::Error.WriteLine('ERROR: Native shutdown failure')
}
if ($mode -eq 'isolated-environment' -and $env:NORTHERNLAB_LAUNCHER_TEST -ne 'isolated-test-userdata') { exit 9 }
if ($mode -eq 'exit-error') { exit 7 }
if ($mode -eq 'live-output') {
    [Console]::Out.Flush()
    Start-Sleep -Seconds 2
    Set-Content -LiteralPath ($logPath + '.finished') -Value 'done'
}
if ($mode -eq 'timeout') { Start-Sleep -Seconds 30 }
exit 0
'@
    $engineArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $fakeEngine + '"'))
    Invoke-GodotBuildStep -OutputCallback {} -Name 'success' -TimeoutSeconds 20 -Arguments ($engineArguments + 'success')
    if (-not (Select-String -LiteralPath (Join-Path $buildLogDirectory 'success.stdout.log') -SimpleMatch 'Console output captured' -Quiet)) {
        throw 'The engine console output was not captured.'
    }
    Write-Output 'PASS Engine output is captured without inheriting the launcher console.'

    $observed = @{ LiveOutput = $false; LiveFile = $false; Pulses = 0; Ticks = 0 }
    $uiTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $uiTimer.Interval = [TimeSpan]::FromMilliseconds(50)
    $uiTimer.Add_Tick({ $observed.Ticks++ })
    $uiTimer.Start()
    Invoke-GodotBuildStep -Name 'live-output' -TimeoutSeconds 20 -Arguments ($engineArguments + 'live-output') -OutputCallback {
        param($text)
        $logControl.AppendText($text)
        if ($text.Contains('Console output captured') -and -not (Test-Path -LiteralPath (Join-Path $buildLogDirectory 'live-output.log.finished'))) {
            $observed.LiveOutput = $true
        }
    } -PulseCallback {
        $observed.Pulses++
        [System.Windows.Forms.Application]::DoEvents()
        if (-not (Test-Path -LiteralPath (Join-Path $buildLogDirectory 'live-output.log.finished')) -and
            (Select-String -LiteralPath (Join-Path $buildLogDirectory 'live-output.stdout.log') -SimpleMatch 'Console output captured' -Quiet)) {
            $observed.LiveFile = $true
        }
    }
    $uiTimer.Stop()
    if (-not $observed.LiveOutput -or -not $observed.LiveFile -or $observed.Pulses -lt 10 -or $observed.Ticks -lt 5 -or
        -not $logControl.Text.Contains('Console output captured')) {
        throw 'Output or UI pulses were delayed until the child exited.'
    }
    Write-Output 'PASS Console, log files and UI callbacks update before the child exits.'

    $deadline = [System.Diagnostics.Stopwatch]::StartNew()
    $failed = $false
    try { Invoke-GodotBuildStep -OutputCallback {} -Name 'timeout' -TimeoutSeconds 1 -Arguments ($engineArguments + 'timeout') }
    catch { $failed = $_.Exception.Message -like '*timed out*' }
    if (-not $failed -or $deadline.Elapsed.TotalSeconds -gt 8) { throw 'Timeout did not stop a silent child promptly.' }
    Write-Output 'PASS A silent process is terminated on timeout without waiting for its output.'

    $cancelled = $false
    try {
        Invoke-GodotBuildStep -OutputCallback {} -Name 'cancel' -TimeoutSeconds 20 -Arguments ($engineArguments + 'timeout') -PulseCallback {
            throw [System.OperationCanceledException]::new('test cancellation')
        }
    }
    catch { $cancelled = $_.Exception.Message -like '*test cancellation*' }
    if (-not $cancelled) { throw 'UI cancellation was ignored.' }
    Write-Output 'PASS Closing the UI can cancel a running child and release its logs.'

    Invoke-GodotBuildStep -OutputCallback {} -Name 'isolated-environment' -TimeoutSeconds 20 -Arguments ($engineArguments + 'isolated-environment') -Environment @{
        NORTHERNLAB_LAUNCHER_TEST = 'isolated-test-userdata'
    }
    if ($env:NORTHERNLAB_LAUNCHER_TEST -eq 'isolated-test-userdata') { throw 'Child environment leaked into the launcher.' }
    Write-Output 'PASS Package audits receive isolated user data without changing the launcher environment.'

    Invoke-GodotBuildStep -OutputCallback {} -Name 'large-output' -TimeoutSeconds 20 -Arguments ($engineArguments + 'large-output')
    foreach ($stream in @('stdout', 'stderr')) {
        if ((Get-Item -LiteralPath (Join-Path $buildLogDirectory "large-output.$stream.log")).Length -lt 262144) {
            throw "Incomplete engine output: $stream"
        }
    }
    Write-Output 'PASS Both output streams are drained even when they exceed the pipe buffer.'

    foreach ($mode in @('stderr-error', 'exit-error')) {
        $failed = $false
        try { Invoke-GodotBuildStep -OutputCallback {} -Name $mode -TimeoutSeconds 20 -Arguments ($engineArguments + $mode) }
        catch { $failed = $true }
        if (-not $failed) { throw "Engine failure was ignored: $mode" }
    }
    Write-Output 'PASS Native stderr errors and unsuccessful exits stop the build.'

    $missingStage = Join-Path $projectRoot 'build/.windows-dev-missing'
    $failed = $false
    try { Publish-DevelopmentBuild $missingStage } catch { $failed = $true }
    if (-not $failed -or (Get-Content -LiteralPath $outputExecutable) -ne 'previous build') {
        throw 'Failed publication did not restore the previous build.'
    }
    Write-Output 'PASS Failed publication restores the previous build.'

    $stage = Join-Path $projectRoot 'build/.windows-dev-test'
    New-Item -ItemType Directory -Path $stage | Out-Null
    Set-Content -LiteralPath (Join-Path $stage 'NorthernLab.exe') -Value 'new build'
    $lock = [System.IO.File]::Open($outputExecutable, 'Open', 'Read', 'None')
    try {
        $failed = $false
        try { Publish-DevelopmentBuild $stage } catch { $failed = $true }
        if (-not $failed -or -not (Test-Path -LiteralPath $stage)) {
            throw 'A locked game was not protected.'
        }
    }
    finally { $lock.Dispose() }
    if ((Get-Content -LiteralPath $outputExecutable) -ne 'previous build') { throw 'Locked build changed.' }
    Write-Output 'PASS A locked game is kept and publication can be retried.'

    Publish-DevelopmentBuild $stage
    if ((Get-Content -LiteralPath $outputExecutable) -ne 'new build' -or (Test-Path -LiteralPath $stage)) {
        throw 'Successful publication failed.'
    }
    if (@(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'build') -Force).Count -ne 1) {
        throw 'Staging or backup directory was left behind.'
    }
    Write-Output 'PASS Successful publication replaces the build and removes its backup.'

    $failed = $false
    try { Remove-BuildStagingDirectory $outputDirectory } catch { $failed = $true }
    if (-not $failed -or -not (Test-Path -LiteralPath $outputExecutable)) { throw 'Unsafe cleanup allowed.' }
    Write-Output 'PASS Cleanup rejects the active build directory.'
}
finally {
    if ($uiTimer) { $uiTimer.Stop() }
    if ($testWindow) { $testWindow.Close() }
    $resolved = [System.IO.Path]::GetFullPath($testRoot)
    $safeRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'tools/.local'))
    if ([System.IO.Path]::GetDirectoryName($resolved) -eq $safeRoot -and
        [System.IO.Path]::GetFileName($resolved).StartsWith('launcher-test-')) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
