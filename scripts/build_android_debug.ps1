#Requires -Version 5.1
# Select a project-local SDK/cache without changing global Android/Flutter settings.
param(
    [Parameter(Mandatory=$true)][string]$AndroidSdkRoot,
    [string]$GradleCacheDir = ''
)
$ErrorActionPreference = 'Stop'
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}
$root = Split-Path -Parent $PSScriptRoot
$sdk = [IO.Path]::GetFullPath($AndroidSdkRoot)
$expectedNdk = '28.2.13676358'
$properties = Join-Path $sdk "ndk/$expectedNdk/source.properties"
if (-not (Test-Path -LiteralPath $properties)) { throw "NDK $expectedNdk is missing from the selected SDK." }
$revision = Select-String -LiteralPath $properties -Pattern '^Pkg.Revision\s*=\s*(.+)$' | Select-Object -First 1
if ($null -eq $revision -or $revision.Matches[0].Groups[1].Value.Trim() -ne $expectedNdk) {
    throw 'Installed NDK revision does not match the project requirement.'
}
$previousHome = $env:ANDROID_HOME
$previousRoot = $env:ANDROID_SDK_ROOT
$previousGradle = $env:GRADLE_USER_HOME
Push-Location $root
try {
    $env:ANDROID_HOME = $sdk
    $env:ANDROID_SDK_ROOT = $sdk
    if (-not [string]::IsNullOrWhiteSpace($GradleCacheDir)) {
        $env:GRADLE_USER_HOME = [IO.Path]::GetFullPath($GradleCacheDir)
    }
    & flutter build apk --debug --no-pub --dart-define-from-file=config/dev.json
    $code = $LASTEXITCODE
    if ($code -eq 0) {
        $apk = 'build/app/outputs/flutter-apk/app-debug.apk'
        if (-not (Test-Path -LiteralPath $apk)) { throw 'Build returned success without an APK.' }
        Get-FileHash -LiteralPath $apk -Algorithm SHA256 | Format-List | Out-Host
    }
    exit $code
}
finally {
    $env:ANDROID_HOME = $previousHome
    $env:ANDROID_SDK_ROOT = $previousRoot
    $env:GRADLE_USER_HOME = $previousGradle
    Pop-Location
}
