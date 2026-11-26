#!/bin/bash
set -euo pipefail
umask 077
export DOCKER_CONFIG
DOCKER_CONFIG=$(mktemp -d)
trap 'rm -rf -- "$DOCKER_CONFIG"' EXIT
repo=ghcr.io/gagarinbefree/kitchentable
image=$repo:sha-$GITHUB_SHA
docker tag "kitchentable-ci:$GITHUB_SHA" "$image"
printf '%s' "$GH_TOKEN" | docker login ghcr.io -u "$GITHUB_ACTOR" --password-stdin
docker push "$image"
digest=$(docker inspect "$image" --format '{{range .RepoDigests}}{{println .}}{{end}}' | sed -n "s|^$repo@||p" | head -1)
[[ $digest =~ ^sha256:[0-9a-f]{64}$ ]]
printf '%s\n' "$DEPLOY_KEY" | tr -d '\r' > "$DOCKER_CONFIG/key"
printf '%s\n' "$DEPLOY_HOST_KEYS" > "$DOCKER_CONFIG/hosts"
printf '%s\n' "$digest" "$GITHUB_ACTOR" "$GH_TOKEN" | ssh -T -o BatchMode=yes -o StrictHostKeyChecking=yes -o IdentitiesOnly=yes -o UserKnownHostsFile="$DOCKER_CONFIG/hosts" -i "$DOCKER_CONFIG/key" kitchentable-deploy@157.22.180.167 deploy
curl -fsS --retry 5 --retry-all-errors --max-time 8 https://gagarinbefree.clodocd.com:9443/health
