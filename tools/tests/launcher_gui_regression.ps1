$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'tools/northernlab_launcher.ps1') -InitializeOnly
$testRoot = Join-Path $repoRoot ('tools/.local/launcher-gui-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$outputDirectory = Join-Path $testRoot 'build'
New-Item -ItemType Directory -Path $outputDirectory | Out-Null
$outputExecutable = Join-Path $outputDirectory 'NorthernLab.exe'
Set-Content -LiteralPath $outputExecutable -Value 'test build'
Initialize-LauncherProcessCapture
$testHost = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$fake = Join-Path $testRoot 'worker.ps1'
Set-Content -LiteralPath $fake -Encoding UTF8 -Value @'
param($Mode, $Directory)
Add-Type -MemberDefinition '[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();' -Name ConsoleProbe -Namespace LauncherTest
[Console]::WriteLine('CONSOLE_HANDLE=' + [LauncherTest.ConsoleProbe]::GetConsoleWindow().ToInt64())
[Console]::WriteLine('Worker output is visible')
Start-Sleep -Milliseconds 600
if ($Mode -eq 'failure') { Stop-Process -Id $PID -Force }
if ($Mode -eq 'cancel') {
    while (-not (Test-Path -LiteralPath (Join-Path $Directory 'cancel.flag'))) { Start-Sleep -Milliseconds 50 }
    exit 8
}
@{ state = 'complete'; message = 'Ready.' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Directory 'state.json')
exit 0
'@

function Test-WorkerUi {
    param([string]$Mode)
    $script:buildSession = Join-Path $testRoot $Mode
    New-Item -ItemType Directory -Path $script:buildSession | Out-Null
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $fake + '" ' + $Mode + ' "' + $script:buildSession + '"'
    $script:buildWorker = [NorthernLab.Launcher.ProcessCapture]::new($testHost, $arguments, $repoRoot, @{})
    $script:buildWorker.Start((Join-Path $script:buildSession 'worker.stdout.log'), (Join-Path $script:buildSession 'worker.stderr.log'))
    $script:buildInProgress = $true
    $script:closeAfterBuild = $false
    $playButton.IsEnabled = $false
    $rebuildButton.IsEnabled = $false
    $buildLog.Clear()
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $observations = @{ ticks = 0; timedOut = $false; liveOutput = $false }
    $frame = [System.Windows.Threading.DispatcherFrame]::new()
    $observer = [System.Windows.Threading.DispatcherTimer]::new()
    $observer.Interval = [TimeSpan]::FromMilliseconds(50)
    $observer.Add_Tick({
        $observations.ticks++
        if ($script:buildInProgress -and $buildLog.Text.Contains('Worker output is visible')) { $observations.liveOutput = $true }
        if ($Mode -eq 'cancel' -and $observations.ticks -eq 6) { $window.Close() }
        if (-not $script:buildInProgress) { $frame.Continue = $false }
        if ($clock.Elapsed.TotalSeconds -gt 15) { $observations.timedOut = $true; $frame.Continue = $false }
    })
    $script:buildTimer.Start()
    $observer.Start()
    try { [System.Windows.Threading.Dispatcher]::PushFrame($frame) }
    finally { $observer.Stop(); $script:buildTimer.Stop() }
    if ($observations.timedOut -or $observations.ticks -lt 8) { throw "UI stalled: $Mode" }
    if (-not (Select-String -LiteralPath (Join-Path $script:buildSession 'worker.stdout.log') -SimpleMatch 'CONSOLE_HANDLE=0' -Quiet)) {
        throw 'Worker created a console window.'
    }
    if ($Mode -eq 'failure' -and ($playButton.IsEnabled -or -not $rebuildButton.IsEnabled -or -not $statusText.Text.Contains('Build error'))) {
        throw 'A worker crash did not leave the UI available for retry.'
    }
    if ($Mode -eq 'success' -and (-not $playButton.IsEnabled -or -not $statusText.Text.Contains('Ready.'))) {
        throw 'Worker completion did not enable Play.'
    }
    if ($Mode -ne 'cancel' -and -not $observations.liveOutput) { throw 'Worker log was delayed until exit.' }
    Write-Output "PASS UI stays responsive and handles $Mode without a console window."
}

try {
    Test-WorkerUi 'failure'
    Test-WorkerUi 'success'
    Test-WorkerUi 'cancel'
}
finally {
    if ($script:buildWorker) { $script:buildWorker.Dispose(); $script:buildWorker = $null }
    $script:buildInProgress = $false
    $window.Close()
    $absolute = [IO.Path]::GetFullPath($testRoot)
    if ([IO.Path]::GetDirectoryName($absolute) -eq [IO.Path]::GetFullPath((Join-Path $repoRoot 'tools/.local')) -and
        [IO.Path]::GetFileName($absolute).StartsWith('launcher-gui-test-')) {
        Remove-Item -LiteralPath $absolute -Recurse -Force
    }
}
