#Requires -Version 5.1
# Restore the existing lockfile, without upgrading packages or changing global configuration.
param([switch]$Offline, [switch]$UseWindowsTrustedRoots)
$ErrorActionPreference = 'Stop'
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
$previousHost = $env:PUB_HOSTED_URL
$previousFlutterRoot = $env:FLUTTER_ROOT
try {
    $env:PUB_HOSTED_URL = 'https://pub.dev'
    if ($Offline) {
        & flutter pub get --offline --enforce-lockfile
        exit $LASTEXITCODE
    }
    if ($UseWindowsTrustedRoots) {
        # Public roots already trusted by Windows. No certificate installation or validation bypass.
        $certDirectory = Join-Path $root '.dart_tool/local_trust'
        New-Item -ItemType Directory -Force -Path $certDirectory | Out-Null
        $certFile = Join-Path $certDirectory 'windows-trusted-roots.pem'
        $roots = Get-ChildItem -Path 'Cert:/CurrentUser/Root', 'Cert:/LocalMachine/Root' |
            Sort-Object Thumbprint -Unique
        if (@($roots).Count -eq 0) { throw 'No existing Windows trusted roots were found.' }
        $pem = foreach ($cert in $roots) {
            '-----BEGIN CERTIFICATE-----'
            [Convert]::ToBase64String($cert.RawData, [Base64FormattingOptions]::InsertLineBreaks)
            '-----END CERTIFICATE-----'
        }
        $pem | Set-Content -LiteralPath $certFile -Encoding ascii
        $flutterCommand = Get-Command flutter -ErrorAction Stop
        $env:FLUTTER_ROOT = Split-Path -Parent (Split-Path -Parent $flutterCommand.Source)
        $dart = Join-Path $env:FLUTTER_ROOT 'bin/cache/dart-sdk/bin/dart.exe'
        & $dart "--root-certs-file=$certFile" pub get --enforce-lockfile
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        # Flutter also generates platform plugin registration; all packages are cached now.
        & flutter pub get --offline --enforce-lockfile
    }
    else {
        & flutter pub get --enforce-lockfile
    }
    exit $LASTEXITCODE
}
finally {
    $env:PUB_HOSTED_URL = $previousHost
    $env:FLUTTER_ROOT = $previousFlutterRoot
    Pop-Location
}
