#!/usr/bin/env bash
# End-to-end Docker registry-mirror test using a disposable Docker-in-Docker
# daemon. It proves that:
#   1. `ayneh --apply docker` writes a valid daemon.json,
#   2. the daemon loads the mirror after a restart,
#   3. an image pull actually goes through the mirror.
#
# Requirements: Docker CLI with permission to run --privileged containers,
# network access, and the docker:dind + ubuntu images.
#
#   bash tests/docker-dind.sh [mirror-url]
#
# Not part of `make test`/CI because it is slow and needs privileges.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MIRROR="${1:-https://docker.arvancloud.ir}"
MIRROR="${MIRROR%/}"
DIND="ayneh-it-dind"
CLIENT="ayneh-it-client"
NET="ayneh-it-net"
VOL="ayneh-it-docker-etc"

say() { printf '\033[36m[i]\033[0m %s\n' "$*"; }
ok()  { printf '\033[32m[+]\033[0m %s\n' "$*"; }
die() { printf '\033[31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

cleanup() {
    docker rm -f "$DIND" "$CLIENT" >/dev/null 2>&1 || true
    docker network rm "$NET" >/dev/null 2>&1 || true
    docker volume rm "$VOL" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

command -v docker >/dev/null 2>&1 || die "docker CLI is required."
docker info >/dev/null 2>&1 || die "cannot talk to the Docker daemon."
[[ -x "$ROOT/dist/ayneh.sh" ]] || die "run ./build.sh first."

cleanup
say "Starting disposable Docker-in-Docker daemon..."
docker network create "$NET" >/dev/null
docker volume create "$VOL" >/dev/null
# Block the direct Docker Hub registry endpoint so a successful pull can only
# come from the mirror (Docker otherwise silently falls back to Hub).
docker run -d --privileged --name "$DIND" --network "$NET" \
    -e DOCKER_TLS_CERTDIR= \
    --add-host registry-1.docker.io:127.0.0.1 \
    --add-host index.docker.io:127.0.0.1 \
    -v "$VOL:/etc/docker" docker:dind --debug >/dev/null

ready=0
for _ in $(seq 1 45); do
    if docker exec "$DIND" docker info >/dev/null 2>&1; then ready=1; break; fi
    sleep 2
done
[[ "$ready" == 1 ]] || { docker logs "$DIND" | tail -30; die "dind did not start"; }
ok "dind is ready"

say "Starting Ubuntu client (shares /etc/docker with the daemon)..."
docker run -d --name "$CLIENT" --network "$NET" \
    -v "$VOL:/etc/docker" -v "$ROOT:/w" -w /w ubuntu:24.04 sleep infinity >/dev/null
docker exec "$CLIENT" bash -c 'apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq curl python3 ca-certificates >/dev/null 2>&1'

say "Applying mirror with ayneh: $MIRROR"
docker exec -e NO_COLOR=1 -e AYNEH_NO_RESTART=1 -e AYNEH_SKIP_VALIDATE=1 \
    "$CLIENT" ./ayneh --apply docker --url "$MIRROR"
docker exec "$CLIENT" python3 -m json.tool /etc/docker/daemon.json >/dev/null
ok "daemon.json is valid JSON"

say "Restarting the daemon so it loads the new config..."
docker restart "$DIND" >/dev/null
ready=0
for _ in $(seq 1 45); do
    if docker exec "$DIND" docker info >/dev/null 2>&1; then ready=1; break; fi
    sleep 2
done
[[ "$ready" == 1 ]] || { docker logs "$DIND" | tail -30; die "dind did not come back"; }

mirrors="$(docker exec "$DIND" docker info --format '{{json .RegistryConfig.Mirrors}}')"
case "$mirrors" in
    *"$MIRROR"*) ok "daemon reports mirror: $mirrors" ;;
    *) die "daemon does not report the mirror: $mirrors" ;;
esac

say "Pulling hello-world through the daemon..."
docker exec "$DIND" docker pull hello-world:latest >/dev/null
sleep 1
host="${MIRROR#*://}"; host="${host%%/*}"
# Capture first: `docker logs | grep -q` can trip pipefail via SIGPIPE.
dind_logs="$(docker logs "$DIND" 2>&1 || true)"
if [[ "$dind_logs" == *"$host"* ]]; then
    ok "pull traffic reached $host"
else
    die "no daemon log entries for $host; pull may not have used the mirror"
fi

printf '\n'
ok "Docker mirror integration test passed."
