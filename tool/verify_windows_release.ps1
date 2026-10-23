$ErrorActionPreference = 'Stop'

if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows') {
  throw 'Run this check only on a fresh Windows CI runner, never a user workspace.'
}

$reports = Join-Path $env:RUNNER_TEMP 'blanko-windows-release'
New-Item -ItemType Directory -Path $reports -Force | Out-Null
flutter build windows --release --target=integration_test/windows_release_test.dart --dart-define=WB_WINDOWS_RELEASE_SMOKE=true --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false
if ($LASTEXITCODE -ne 0) { throw 'Windows Release integration build failed' }
$executable = (Resolve-Path 'build/windows/x64/runner/Release/whiteboard.exe').Path
foreach ($phase in @('write', 'read')) {
  $report = Join-Path $reports "$phase.json"
  if (Test-Path $report) { Remove-Item $report }
  $app = Start-Process -FilePath $executable -ArgumentList @($phase, "`"$report`"") -PassThru `
    -RedirectStandardOutput (Join-Path $reports "$phase.stdout.log") `
    -RedirectStandardError (Join-Path $reports "$phase.stderr.log")
  try {
    if (!$app.WaitForExit(90000)) { throw "Release $phase timed out" }
    if ($app.ExitCode -ne 0) {
      if (Test-Path $report) { Get-Content $report -Raw | Write-Output }
      Get-Content (Join-Path $reports "$phase.stderr.log") | Write-Output
      throw "Release $phase exited with $($app.ExitCode)"
    }
    if (!(Test-Path $report)) { throw "Release $phase produced no result" }
    $result = Get-Content $report -Raw | ConvertFrom-Json
    if ($result.passed -ne $true -or $result.phase -ne $phase) {
      throw "Release $phase failed: $(Get-Content $report -Raw)"
    }
    Write-Output "Windows Release $phase passed: $(Get-Content $report -Raw)"
  } finally {
    if (!$app.HasExited) { $app.Kill(); $app.WaitForExit() }
  }
}

# The distributed executable must use the production entry, not the smoke test.
flutter build windows --release --target=lib/main.dart
if ($LASTEXITCODE -ne 0) { throw 'Normal Windows Release build failed' }

Add-Type -AssemblyName System.Drawing
$actualIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($executable)
if ($null -eq $actualIcon) { throw 'Release executable has no icon' }
$expectedIcon = [System.Drawing.Icon]::new(
  (Resolve-Path 'windows/runner/resources/app_icon.ico').Path,
  $actualIcon.Width, $actualIcon.Height)
$actual = $actualIcon.ToBitmap()
$expected = $expectedIcon.ToBitmap()
try {
  for ($y = 0; $y -lt $actual.Height; $y++) {
    for ($x = 0; $x -lt $actual.Width; $x++) {
      if ($actual.GetPixel($x, $y).ToArgb() -ne $expected.GetPixel($x, $y).ToArgb()) {
        throw 'Release executable does not contain the expected Blanko icon'
      }
    }
  }
  Write-Output 'Actual Windows Release executable contains the Blanko icon.'
} finally {
  $actual.Dispose(); $expected.Dispose()
  $actualIcon.Dispose(); $expectedIcon.Dispose()
}
