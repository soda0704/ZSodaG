$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$launcher = Join-Path $repoRoot 'tools/northernlab_launcher.ps1'
$parseErrors = $null
$tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($launcher, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw "Launcher parse errors: $parseErrors" }
# Load helpers without opening the launcher or touching the real game build.
foreach ($name in @('Assert-BuildNotRunning', 'Publish-DevelopmentBuild', 'Remove-BuildStagingDirectory', 'Invoke-GodotBuildStep')) {
    $definition = $ast.Find({ param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    Invoke-Expression $definition.Extent.Text
}
$testRoot = Join-Path $repoRoot ('tools/.local/launcher-test-' + [guid]::NewGuid().ToString('N'))
$projectRoot = $testRoot
$outputDirectory = Join-Path $projectRoot 'build/windows-dev'
$outputExecutable = Join-Path $outputDirectory 'NorthernLab.exe'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
Set-Content -LiteralPath $outputExecutable -Value 'previous build'
try {
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
if ($mode -eq 'exit-error') { exit 7 }
exit 0
'@
    $engineArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $fakeEngine + '"'))
    Invoke-GodotBuildStep -Name 'success' -TimeoutSeconds 20 -Arguments ($engineArguments + 'success')
    if (-not (Select-String -LiteralPath (Join-Path $buildLogDirectory 'success.stdout.log') -SimpleMatch 'Console output captured' -Quiet)) {
        throw 'The engine console output was not captured.'
    }
    Write-Output 'PASS Engine output is captured without inheriting the launcher console.'

    Invoke-GodotBuildStep -Name 'large-output' -TimeoutSeconds 20 -Arguments ($engineArguments + 'large-output')
    foreach ($stream in @('stdout', 'stderr')) {
        if ((Get-Item -LiteralPath (Join-Path $buildLogDirectory "large-output.$stream.log")).Length -lt 262144) {
            throw "Incomplete engine output: $stream"
        }
    }
    Write-Output 'PASS Both output streams are drained even when they exceed the pipe buffer.'

    foreach ($mode in @('stderr-error', 'exit-error')) {
        $failed = $false
        try { Invoke-GodotBuildStep -Name $mode -TimeoutSeconds 20 -Arguments ($engineArguments + $mode) }
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
    $resolved = [System.IO.Path]::GetFullPath($testRoot)
    $safeRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'tools/.local'))
    if ([System.IO.Path]::GetDirectoryName($resolved) -eq $safeRoot -and
        [System.IO.Path]::GetFileName($resolved).StartsWith('launcher-test-')) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
