#!/bin/bash
# Installed root-owned. The deployment account can invoke only this command.
set -euo pipefail
umask 077
cd /opt/kitchentable
exec 9>.deploy.lock
flock -w 120 9
read -r digest
read -r registry_user
read -r registry_token
[[ $digest =~ ^sha256:[0-9a-f]{64}$ && $registry_user =~ ^[A-Za-z0-9_-]+(\[bot\])?$ && -n $registry_token ]]
repository=ghcr.io/gagarinbefree/kitchentable
export DOCKER_CONFIG
DOCKER_CONFIG=$(mktemp -d)
trap 'rm -rf -- "$DOCKER_CONFIG"; rm -f -- .candidate' EXIT
printf '%s' "$registry_token" | docker login ghcr.io -u "$registry_user" --password-stdin >/dev/null
unset registry_token
docker pull "$repository@$digest"
printf 'CHAT_IMAGE=%s@%s\n' "$repository" "$digest" > .candidate
compose() {
    docker compose --project-name kitchentable --env-file .env --env-file "$1" -f compose.yaml up -d --no-build --pull missing
}
if compose .candidate && curl -fsS --retry 20 --retry-all-errors --retry-delay 2 --max-time 4 -o /dev/null https://gagarinbefree.clodocd.com:9443/health --resolve gagarinbefree.clodocd.com:9443:127.0.0.1; then
    mv -f .candidate .active
    printf 'Healthy: %s@%s\n' "$repository" "$digest"
else
    if [[ -s .active ]]; then compose .active; fi
    exit 1
fi
