param(
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$candidates = @()
$command = Get-Command flutter -ErrorAction SilentlyContinue
if ($command) { $candidates += $command.Source }
if ($env:FLUTTER_HOME) {
    $candidates += (Join-Path $env:FLUTTER_HOME 'bin\flutter.bat')
}
$candidates += @(
    (Join-Path $env:USERPROFILE 'flutter\bin\flutter.bat'),
    (Join-Path $env:USERPROFILE 'development\flutter\bin\flutter.bat'),
    (Join-Path $env:USERPROFILE 'Documents\Codex\2026-08-02\vdpk\work\flutter_sdk_extract\flutter\bin\flutter.bat'),
    'C:\src\flutter\bin\flutter.bat',
    'C:\flutter\bin\flutter.bat'
)

$flutter = $candidates |
    Where-Object { $_ -and (Test-Path $_) } |
    Select-Object -First 1

if (-not $flutter) {
    Write-Host ''
    Write-Host 'Flutter SDK was not found.' -ForegroundColor Red
    Write-Host 'Install Flutter, add flutter\bin to PATH, or set FLUTTER_HOME.'
    Write-Host 'Example: setx FLUTTER_HOME "C:\src\flutter"'
    Write-Host ''
    exit 1
}

Write-Host "Using Flutter: $flutter" -ForegroundColor Cyan
Push-Location $projectRoot
try {
    & $flutter --version
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & $flutter pub get
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & $flutter analyze
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & $flutter test
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    if (-not $CheckOnly) {
        & $flutter run
        exit $LASTEXITCODE
    }
}
finally {
    Pop-Location
}
