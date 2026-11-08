#Requires -Version 5.1
# Quality/build gate adapted from Flutter Starter. Does not install toolchains or accept licenses.
param(
    [ValidateSet('all', 'quality', 'config', 'build')][string]$Mode = 'quality',
    [ValidateSet('windows', 'android', 'all')][string]$Platform = 'windows',
    [ValidateSet('development', 'staging', 'production')][string]$Environment = 'development',
    [string]$ConfigRoot = ''
)
$ErrorActionPreference = 'Stop'
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}
Set-StrictMode -Version Latest
Set-Location (Split-Path -Parent $PSScriptRoot)
$script:Results = @()
$reportDir = 'build/reports'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
function Invoke-Step {
    param([string]$Name, [string]$File, [string[]]$CommandArgs)
    Write-Host "== $Name =="
    & $File @CommandArgs | Out-Host
    $code = $LASTEXITCODE
    $script:Results += [pscustomobject]@{ name=$Name; status=$(if ($code -eq 0) { 'PASS' } else { 'FAIL' }); exit_code=$code }
    return ($code -eq 0)
}
function Save-Summary {
    $script:Results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$reportDir/verification.json" -Encoding utf8
    $script:Results | Format-Table -AutoSize | Out-Host
}
function Invoke-Config {
    $arguments = @('run', 'tool/check_config.dart')
    if (-not [string]::IsNullOrWhiteSpace($ConfigRoot)) { $arguments += @('--root', $ConfigRoot) }
    return Invoke-Step -Name 'config' -File 'dart' -CommandArgs $arguments
}
function Test-AndroidNdk {
    $command = Get-Command flutter -ErrorAction Stop
    $sdkRoot = Split-Path -Parent (Split-Path -Parent $command.Source)
    $file = Join-Path $sdkRoot 'packages/flutter_tools/lib/src/android/gradle_utils.dart'
    $matched = Select-String -LiteralPath $file -Pattern "const ndkVersion = '([0-9.]+)';" | Select-Object -First 1
    $version = if ($null -eq $matched) { $null } else { $matched.Matches[0].Groups[1].Value }
    $sdk = $env:ANDROID_HOME
    if ([string]::IsNullOrWhiteSpace($sdk)) { $sdk = $env:ANDROID_SDK_ROOT }
    if ([string]::IsNullOrWhiteSpace($version) -or [string]::IsNullOrWhiteSpace($sdk)) {
        Write-Host 'BLOCKED: cannot verify the Flutter NDK or SDK location. No automatic SDK download is attempted.'
        return $false
    }
    if (-not (Test-Path -LiteralPath (Join-Path $sdk "ndk/$version/source.properties"))) {
        Write-Host "BLOCKED: Flutter requires NDK $version; it is not installed. Install it using Android SDK Manager."
        Write-Host 'No Gradle build or automatic SDK download was started.'
        return $false
    }
    return $true
}
function Record-Artifact {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Build returned success but $Name is missing." }
    [pscustomobject]@{name=$Name; bytes=(Get-Item -LiteralPath $Path).Length; sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()} |
        ConvertTo-Json -Compress | Add-Content -LiteralPath "$reportDir/artifacts.jsonl" -Encoding utf8
}
if ($Mode -eq 'config') {
    $ok = Invoke-Config
    Save-Summary
    if ($ok) { exit 0 } else { exit 1 }
}
if ($Mode -eq 'quality' -or $Mode -eq 'all') {
    $steps = @(
        @{Name='format'; File='dart'; CommandArgs=@('format','--output=none','--set-exit-if-changed','lib','test','integration_test','tool')},
        @{Name='analyze'; File='flutter'; CommandArgs=@('analyze','--no-pub','--fatal-infos')},
        @{Name='test'; File='flutter'; CommandArgs=@('test','--no-pub','--reporter','expanded')}
    )
    foreach ($step in $steps) {
        if (-not (Invoke-Step @step)) { Save-Summary; exit 1 }
    }
    if (-not (Invoke-Config)) { Save-Summary; exit 1 }
}
if ($Mode -eq 'build' -or $Mode -eq 'all') {
    if (-not (Invoke-Config)) { Save-Summary; exit 1 }
    $file = switch ($Environment) {'development' {'dev.json'}; 'staging' {'staging.json'}; 'production' {'prod.json'}}
    $define = "--dart-define-from-file=config/$file"
    if ($Platform -eq 'windows' -or $Platform -eq 'all') {
        foreach ($kind in @('debug','release')) {
            $ok = Invoke-Step -Name "windows-$kind" -File 'flutter' -CommandArgs @('build','windows',"--$kind",'--no-pub',$define)
            if ($ok) {
                $folder = if ($kind -eq 'debug') {'Debug'} else {'Release'}
                Record-Artifact -Path "build/windows/x64/runner/$folder/english_learning.exe" -Name "windows-$kind"
            }
        }
    }
    if ($Platform -eq 'android' -or $Platform -eq 'all') {
        if (Test-AndroidNdk) {
            foreach ($kind in @('debug','release')) {
                $ok = Invoke-Step -Name "android-$kind" -File 'flutter' -CommandArgs @('build','apk',"--$kind",'--no-pub',$define)
                if ($ok) { Record-Artifact -Path "build/app/outputs/flutter-apk/app-$kind.apk" -Name "android-$kind" }
            }
            Write-Host 'Release APK uses the inherited debug signing config; it is a test artifact.'
        } else {
            $script:Results += [pscustomobject]@{name='android-debug-and-release';status='BLOCKED';exit_code=$null}
        }
    }
}
Save-Summary
if (@($script:Results | Where-Object {$_.status -ne 'PASS'}).Count -gt 0) { exit 1 }
exit 0
