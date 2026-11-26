$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$adb = 'C:\DevTools\Android\Sdk\platform-tools\adb.exe'
$serial = 'emulator-5554'
$avd = & $adb -s $serial emu avd name
if ($avd -notcontains 'KitchenTablePeer_API35') { throw 'Start the KitchenTablePeer_API35 emulator on Windows, port 5554' }
& $adb -s $serial install -r client/build/app/outputs/flutter-apk/app-debug.apk
& $adb -s $serial shell am start-user -w 10
& $adb -s $serial shell cmd package install-existing --user 10 com.example.kitchentable.ci
$key = Join-Path $env:RUNNER_TEMP ([Guid]::NewGuid().ToString() + '.key')
$hostsFile = "$key.hosts"
try {
    [IO.File]::WriteAllText($key, ($env:LAB_ADB_KEY.Trim() + [char]10).Replace("`r", ''))
    icacls $key /inheritance:r /grant:r "$([Security.Principal.WindowsIdentity]::GetCurrent().Name):R" | Out-Null
    [IO.File]::WriteAllText($hostsFile, ($env:LAB_HOST_KEYS.Trim() + [char]10).Replace("`r", ''))
    $OutputEncoding = [Text.UTF8Encoding]::new($false)
    Get-Content -LiteralPath client/test/android_chat_smoke.py -Encoding utf8 -Raw | ssh -T -i $key -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$hostsFile" -o ExitOnForwardFailure=yes -R 127.0.0.1:15041:127.0.0.1:5037 kt-smoke@192.168.31.84 smoke
} finally {
    foreach ($path in @($key, $hostsFile)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    }
    foreach ($userId in 0,10) { & $adb -s $serial shell am force-stop --user $userId com.example.kitchentable.ci }
}
