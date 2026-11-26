$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$adb = 'C:\DevTools\Android\Sdk\platform-tools\adb.exe'
$serial = 'emulator-5554'
$key = Join-Path $env:RUNNER_TEMP ([Guid]::NewGuid().ToString() + '.key')
$hostsFile = "$key.hosts"
$startedHere = $false
$handwriting = @{}
try {
    $devices = & $adb devices
    if (!($devices -match "^$serial\s+device\s*$")) {
        if ($devices -match '^emulator-\d+\s') { throw 'Another emulator is already running on Windows' }
        $env:ANDROID_AVD_HOME = 'D:\windows\KitchenTableCI\avd'
        Start-Process -FilePath 'C:\DevTools\Android\Sdk\emulator\emulator.exe' -ArgumentList '-avd','KitchenTableCI_API35','-port','5554','-no-window','-no-audio','-no-snapshot','-no-boot-anim','-gpu','software' -WindowStyle Hidden
        $startedHere = $true
        $deadline = (Get-Date).AddMinutes(8)
        do {
            Start-Sleep -Seconds 3
            $devices = & $adb devices
            $ready = ($devices -match "^$serial\s+device\s*$") -and ((& $adb -s $serial shell getprop sys.boot_completed).Trim() -eq '1')
        } until ($ready -or (Get-Date) -gt $deadline)
        if (!$ready) { throw 'CI emulator failed to boot' }
    }
    $name = (& $adb -s $serial shell getprop ro.boot.qemu.avd_name).Trim()
    if ($name -notin 'KitchenTablePeer_API35','KitchenTableCI_API35') { throw 'Unexpected Android device on port 5554' }
    $profiles = & $adb -s $serial shell pm list users
    if (!($profiles -match 'UserInfo\{10:KitchenTablePeer:')) {
        if ($name -ne 'KitchenTableCI_API35' -or ($profiles -match 'UserInfo\{10:')) { throw 'Missing KitchenTable test profile' }
        $created = & $adb -s $serial shell pm create-user --profileOf 0 --managed KitchenTablePeer
        if ($created -notmatch 'created user id 10') { throw 'Failed to create test profile' }
    }
    & $adb -s $serial shell am start-user -w 10
    & $adb -s $serial install -r client/build/app/outputs/flutter-apk/app-debug.apk
    & $adb -s $serial shell cmd package install-existing --user 10 com.example.kitchentable.ci
    foreach ($id in 0,10) {
        $handwriting[$id] = (& $adb -s $serial shell settings --user $id get secure stylus_handwriting_enabled).Trim()
        & $adb -s $serial shell settings --user $id put secure stylus_handwriting_enabled 0
    }
    [IO.File]::WriteAllText($key, ($env:LAB_ADB_KEY.Trim() + [char]10).Replace("`r", ''))
    icacls $key /inheritance:r /grant:r "$([Security.Principal.WindowsIdentity]::GetCurrent().Name):R" | Out-Null
    [IO.File]::WriteAllText($hostsFile, ($env:LAB_HOST_KEYS.Trim() + [char]10).Replace("`r", ''))
    $OutputEncoding = [Text.UTF8Encoding]::new($false)
    Get-Content -LiteralPath client/test/android_chat_smoke.py -Encoding utf8 -Raw | ssh -T -i $key -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$hostsFile" -o ExitOnForwardFailure=yes -R 127.0.0.1:15041:127.0.0.1:5037 kt-smoke@192.168.31.84 smoke
} finally {
    foreach ($path in @($key, $hostsFile)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    }
    foreach ($id in $handwriting.Keys) {
        & $adb -s $serial shell am force-stop --user $id com.example.kitchentable.ci
        if ($handwriting[$id] -eq 'null') {
            & $adb -s $serial shell settings --user $id delete secure stylus_handwriting_enabled
        } else {
            & $adb -s $serial shell settings --user $id put secure stylus_handwriting_enabled $handwriting[$id]
        }
    }
    if ($startedHere) { & $adb -s $serial emu kill }
}
