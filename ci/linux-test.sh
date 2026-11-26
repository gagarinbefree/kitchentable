#!/bin/bash
set -euo pipefail
export POSTGRES_PASSWORD CHAT_BIND=127.0.0.1 CHAT_PORT=28788
POSTGRES_PASSWORD=$(openssl rand -hex 32)
compose=(docker compose -p kitchentable-actions -f compose.yaml -f ci/compose.yaml)
trap '"${compose[@]}" down --volumes --remove-orphans' EXIT
"${compose[@]}" build server tests
"${compose[@]}" up -d db server
curl -fsS --retry 25 --retry-all-errors --retry-delay 1 --max-time 3 http://127.0.0.1:28788/health
"${compose[@]}" run --rm tests
docker save "kitchentable-ci:$GITHUB_SHA" | gzip -1 > "$RUNNER_TEMP/kitchentable-image.tar.gz"
