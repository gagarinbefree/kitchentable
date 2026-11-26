#!/bin/bash
set -euo pipefail
serial=emulator-5554
adb=(adb -s "$serial")
export KITCHENTABLE_ANDROID_PACKAGE=com.example.kitchentable.ci
"${adb[@]}" shell wm size 540x960
"${adb[@]}" shell wm density 210
creation=$("${adb[@]}" shell pm create-user --profileOf 0 --managed KitchenTablePeer)
peer=$(sed -nE 's/.*created user id ([0-9]+).*/\1/p' <<<"$creation")
[[ $peer =~ ^[1-9][0-9]*$ ]] || { echo "$creation"; exit 1; }
"${adb[@]}" shell am start-user -w "$peer"
for user in 0 "$peer"; do
    "${adb[@]}" shell settings --user "$user" put secure stylus_handwriting_enabled 0
done
"${adb[@]}" install -r "$RUNNER_TEMP/apk/app-debug.apk"
"${adb[@]}" shell cmd package install-existing --user "$peer" "$KITCHENTABLE_ANDROID_PACKAGE"
"${adb[@]}" reverse tcp:28788 tcp:28788
test=(python3 -u client/test/android_chat_smoke.py "$serial" --peer-user "$peer")
"${test[@]}" | tee "$RUNNER_TEMP/kt-smoke.log"
marker=$(sed -n 's/^Catch-up: OK. Persistence marker: \(KT-[[:alnum:]]*-back\)$/\1/p' "$RUNNER_TEMP/kt-smoke.log")
test -n "$marker"
docker compose -p kitchentable-actions -f compose.yaml -f ci/compose.yaml restart server
curl -fsS --retry 25 --retry-all-errors --retry-delay 1 --max-time 3 http://127.0.0.1:28788/health
"${test[@]}" --expect "$marker"
