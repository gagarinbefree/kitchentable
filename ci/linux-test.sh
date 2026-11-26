#!/bin/bash
set -euo pipefail
docker build --target tests -t "kitchentable-unit:$GITHUB_SHA" server
docker run --rm --network none "kitchentable-unit:$GITHUB_SHA" --filter Category=Unit
docker build --target runtime \
    --label "org.opencontainers.image.source=https://github.com/$GITHUB_REPOSITORY" \
    --label "org.opencontainers.image.revision=$GITHUB_SHA" \
    -t "kitchentable-ci:$GITHUB_SHA" server
docker save "kitchentable-ci:$GITHUB_SHA" | gzip -1 > "$RUNNER_TEMP/kitchentable-image.tar.gz"
