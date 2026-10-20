$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'tools/northernlab_launcher.ps1') -InitializeOnly
# Exercise the real ContentRendered handler, dispatcher, worker and publication.
# Keep the test's own window off screen; do not operate on the user's windows.
$window.ShowInTaskbar = $false
$window.ShowActivated = $false
$window.WindowStartupLocation = 'Manual'
$window.Left = -30000
$window.Top = -30000
$observed = @{ ticks = 0; started = $false; passed = $false; detail = '' }
$deadline = [Diagnostics.Stopwatch]::StartNew()
$observer = [System.Windows.Threading.DispatcherTimer]::new()
$observer.Interval = [TimeSpan]::FromMilliseconds(100)
$observer.Add_Tick({
    $observed.ticks++
    if ($script:buildInProgress) { $observed.started = $true }
    if ($observed.started -and -not $script:buildInProgress) {
        $observed.passed = $playButton.IsEnabled -and $rebuildButton.IsEnabled -and $statusText.Text.StartsWith('Ready.')
        $observed.detail = $statusText.Text
        $observer.Stop()
        $window.Close()
    }
    if ($deadline.Elapsed.TotalSeconds -gt 900) {
        $observed.detail = 'Full GUI build timed out.'
        $observer.Stop()
        $window.Close()
    }
})
$observer.Start()
try { [void]$window.ShowDialog() }
finally { $observer.Stop() }
if (-not $observed.passed -or $observed.ticks -lt 50) {
    throw "Full GUI build failed: $($observed.detail), ticks=$($observed.ticks), session=$script:buildSession"
}
Write-Output "PASS Full GUI build completed, Play enabled, dispatcher ticks=$($observed.ticks)."
Write-Output "PASS Session: $script:buildSession"
