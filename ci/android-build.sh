#!/bin/bash
set -euo pipefail
cd client
flutter pub get --enforce-lockfile
case "${1:?expected debug or release}" in
  debug)
    flutter build apk --debug --no-pub --dart-define=CHAT_SERVER=https://gagarinbefree.clodocd.com:9443
    ;;
  release)
    umask 077
    KT_STORE_FILE=$(mktemp "$RUNNER_TEMP/kt-signing-XXXXXX.p12")
    export KT_STORE_FILE
    trap 'rm -f -- "$KT_STORE_FILE"' EXIT
    printf '%s' "$KT_STORE_BASE64" | base64 -d > "$KT_STORE_FILE"
    unset KT_STORE_BASE64
    flutter build apk --release --no-pub --build-name="1.0.$GITHUB_RUN_NUMBER" \
        --build-number="$GITHUB_RUN_NUMBER" --dart-define=CHAT_SERVER=https://gagarinbefree.clodocd.com:9443
    apk=build/app/outputs/flutter-apk/app-release.apk
    build_tools=$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d | grep -E '/[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
    "$build_tools/apksigner" verify "$apk"
    metadata=$("$build_tools/aapt" dump badging "$apk")
    grep -Fq "name='com.example.kitchentable' versionCode='$GITHUB_RUN_NUMBER'" <<<"$metadata"
    grep -E "^native-code:.*'arm64-v8a'" <<<"$metadata"
    ;;
  *) exit 2 ;;
esac
