[CmdletBinding()]
param(
    [string]$FlutterSdk = $env:FLUTTER_ROOT,
    [switch]$Production
)

$ErrorActionPreference = 'Stop'
$workspacePath = Split-Path -Parent $PSScriptRoot
$versionMatch = [regex]::Match(
    (Get-Content -Raw -LiteralPath (Join-Path $workspacePath 'pubspec.yaml')),
    '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$'
)
if (-not $versionMatch.Success) { throw 'pubspec.yaml needs a version name and build number.' }

if ([string]::IsNullOrWhiteSpace($FlutterSdk)) {
    $flutterCommand = Get-Command flutter -ErrorAction Stop
    $FlutterSdk = Split-Path -Parent (Split-Path -Parent $flutterCommand.Source)
}
$dartPath = Join-Path $FlutterSdk 'bin/cache/dart-sdk/bin/dart.exe'
$flutterSnapshotPath = Join-Path $FlutterSdk 'bin/cache/flutter_tools.snapshot'
if (-not (Test-Path -LiteralPath $dartPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $flutterSnapshotPath -PathType Leaf)) {
    throw 'Pass -FlutterSdk with an initialized Windows Flutter SDK directory.'
}
if ($Production -and -not (Test-Path -LiteralPath (Join-Path $workspacePath 'android/key.properties') -PathType Leaf)) {
    throw 'Production signing requires android/key.properties. See docs/android-release.md.'
}

function Invoke-FlutterStep {
    param([string[]]$FlutterArguments)
    & $dartPath $flutterSnapshotPath @FlutterArguments
    if ($LASTEXITCODE -ne 0) { throw "Flutter step failed: $($FlutterArguments[0])" }
}

$previousProduction = $env:HOMESPACE_PRODUCTION
$mode = if ($Production) { 'production' } else { 'preview' }
$version = "$($versionMatch.Groups[1].Value)+$($versionMatch.Groups[2].Value)"
Push-Location -LiteralPath $workspacePath
try {
    $env:HOMESPACE_PRODUCTION = if ($Production) { 'true' } else { 'false' }
    Invoke-FlutterStep -FlutterArguments @('analyze', '--no-pub')
    Invoke-FlutterStep -FlutterArguments @('test', '--no-pub', '--reporter', 'expanded')
    Invoke-FlutterStep -FlutterArguments @('build', 'apk', '--release', '--no-pub')
    Push-Location -LiteralPath (Join-Path $workspacePath 'android')
    try {
        & './gradlew.bat' ':app:lintRelease' '--console=plain'
        if ($LASTEXITCODE -ne 0) { throw 'Android release lint failed.' }
    }
    finally { Pop-Location }
    if ($Production) {
        Invoke-FlutterStep -FlutterArguments @('build', 'appbundle', '--release', '--no-pub')
    }

    $releaseDirectory = Join-Path $workspacePath 'output/releases'
    New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null
    $stem = "homespace-android-$version-$mode"
    $artifacts = @(@{ source = 'build/app/outputs/flutter-apk/app-release.apk'; extension = 'apk' })
    if ($Production) {
        $artifacts += @{ source = 'build/app/outputs/bundle/release/app-release.aab'; extension = 'aab' }
    }
    $records = foreach ($artifact in $artifacts) {
        $destinationPath = Join-Path $releaseDirectory "$stem.$($artifact.extension)"
        Copy-Item -LiteralPath (Join-Path $workspacePath $artifact.source) -Destination $destinationPath
        [ordered]@{
            file = [IO.Path]::GetFileName($destinationPath)
            bytes = (Get-Item -LiteralPath $destinationPath).Length
            sha256 = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash
        }
    }
    $revision = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Could not read the Git revision for the artifact record.' }
    $dirty = @(& git status --porcelain).Count -gt 0
    [ordered]@{
        applicationId = 'com.homespace.homespace'
        version = $version
        mode = $mode
        revision = $revision
        uncommittedChanges = $dirty
        signing = if ($Production) { 'owner upload key' } else { 'development key' }
        artifacts = @($records)
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $releaseDirectory "$stem.json") -Encoding UTF8
    Write-Output "Archived $mode artifacts: $stem"
}
finally {
    $env:HOMESPACE_PRODUCTION = $previousProduction
    Pop-Location
}
