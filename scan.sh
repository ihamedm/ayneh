#!/usr/bin/env bash
# Compatibility wrapper. `scan.sh` was the monolithic 1.x script; the project
# now lives in `ayneh` + lib/. This wrapper keeps old muscle memory and old
# links working.
set -uo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "$root/ayneh" "$@"
