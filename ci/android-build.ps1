param([ValidateSet('Debug','Release')] [string]$Mode)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$env:JAVA_HOME = 'C:\DevTools\Android\Jdk'
$env:ANDROID_HOME = 'C:\DevTools\Android\Sdk'
$env:GRADLE_USER_HOME = 'D:\windows\KitchenTableCI\gradle'
$flutter = 'D:\windows\KitchenTableCI\flutter\bin\flutter.bat'
Set-Location client
& $flutter pub get --enforce-lockfile
if ($Mode -eq 'Debug') {
    $env:ORG_GRADLE_PROJECT_kitchenTableCi = 'true'
    & $flutter build apk --debug --no-pub --target-platform android-x64 --dart-define=CHAT_SERVER=http://192.168.31.84:28788
} else {
    $env:KT_STORE_FILE = Join-Path $env:RUNNER_TEMP ("kitchentable-" + [Guid]::NewGuid() + ".p12")
    try {
        [IO.File]::WriteAllBytes($env:KT_STORE_FILE, [Convert]::FromBase64String($env:KT_STORE_BASE64))
        Remove-Item Env:KT_STORE_BASE64
        & $flutter build apk --release --no-pub --build-name="1.0.$env:GITHUB_RUN_NUMBER" --build-number=$env:GITHUB_RUN_NUMBER --dart-define=CHAT_SERVER=https://gagarinbefree.clodocd.com:9443
        $tools = Get-ChildItem "$env:ANDROID_HOME\build-tools" -Directory | Where-Object Name -Match '^\d+\.\d+\.\d+$' | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
        $apk = 'build/app/outputs/flutter-apk/app-release.apk'
        & "$($tools.FullName)\apksigner.bat" verify $apk
        $metadata = & "$($tools.FullName)\aapt.exe" dump badging $apk
        if (!(($metadata -match '^package:') -match "name='com.example.kitchentable' versionCode='$env:GITHUB_RUN_NUMBER'") -or !(($metadata -match '^native-code:') -match 'arm64-v8a')) {
            throw 'Unexpected Android release package, version or architectures'
        }
    } finally {
        if (Test-Path -LiteralPath $env:KT_STORE_FILE) { Remove-Item -LiteralPath $env:KT_STORE_FILE }
    }
}
