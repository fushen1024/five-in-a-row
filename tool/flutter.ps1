param([Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArgs)
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path $PSScriptRoot -Parent
$env:GIT_CONFIG_COUNT = '1'
$env:GIT_CONFIG_KEY_0 = 'safe.directory'
$env:GIT_CONFIG_VALUE_0 = "$projectPath/.tools/flutter"
$env:PUB_CACHE = "$projectPath/.tools/pub-cache"
$env:APPDATA = "$projectPath/.tools/appdata"
$env:LOCALAPPDATA = "$projectPath/.tools/localappdata"
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
if (Test-Path "$projectPath/.tools/android-sdk/platform-tools") {
    $env:ANDROID_HOME = "$projectPath/.tools/android-sdk"
    $env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
}
$env:GRADLE_USER_HOME = "$projectPath/.tools/gradle"
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
& "$projectPath/.tools/flutter/bin/flutter.bat" @FlutterArgs
exit $LASTEXITCODE
