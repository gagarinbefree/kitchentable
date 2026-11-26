#!/bin/bash
set -euo pipefail
flutter=/opt/kitchentable-ci/tools/flutter/bin/flutter
(
    cd client
    "$flutter" pub get --enforce-lockfile
    "$flutter" analyze --no-pub
    "$flutter" test --no-pub --reporter expanded
)
export POSTGRES_PASSWORD CHAT_BIND=192.168.31.84 CHAT_PORT=28788
POSTGRES_PASSWORD=$(openssl rand -hex 32)
compose=(docker --context default compose -p kitchentable-actions -f compose.yaml -f ci/compose.yaml)
"${compose[@]}" down --volumes --remove-orphans
"${compose[@]}" build server tests
"${compose[@]}" up -d db server
curl -fsS --retry 25 --retry-all-errors --retry-delay 1 --max-time 3 http://192.168.31.84:28788/health
"${compose[@]}" run --rm tests
