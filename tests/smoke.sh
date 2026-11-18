#!/usr/bin/env bash
# Offline smoke tests for ayneh. No network access is required.
#   bash tests/smoke.sh
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist/ayneh.sh"

pass=0
fail=0
OUT=""
RC=0

ok_test()   { pass=$((pass+1)); printf '  \033[32mok\033[0m   %s\n' "$1"; }
bad_test()  { fail=$((fail+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2"; }

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then ok_test "$desc"; else bad_test "$desc" "expected [$expected], got [$actual]"; fi
}
assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then ok_test "$desc"; else bad_test "$desc" "missing [$needle]"; fi
}
assert_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if [[ "$haystack" != *"$needle"* ]]; then ok_test "$desc"; else bad_test "$desc" "unexpected [$needle]"; fi
}
assert_rc() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then ok_test "$desc"; else bad_test "$desc" "expected exit $expected, got $actual"; fi
}

run_cli() {
    set +e
    OUT="$("$@" 2>&1)"
    RC=$?
    set -e
}

printf '\n== build ==\n'
if [[ -f "$DIST" ]]; then ok_test "dist/ayneh.sh exists"; else bad_test "dist/ayneh.sh exists"; fi
run_cli bash "$ROOT/build.sh" --check
assert_rc "dist is up to date" 0 "$RC"
assert_contains "build check message" "$OUT" "up to date"
run_cli bash -n "$DIST"
assert_rc "generated script parses" 0 "$RC"

printf '\n== CLI ==\n'
version="$(sed -n 's/^AYNEH_VERSION="\(.*\)"/\1/p' "$ROOT/lib/00-core.sh" | head -1)"
run_cli bash "$DIST" --version
assert_rc "--version exits 0" 0 "$RC"
assert_eq "--version output" "ayneh v$version" "$OUT"

run_cli bash "$DIST" --help
assert_rc "--help exits 0" 0 "$RC"
assert_contains "--help shows usage" "$OUT" "Usage:"
assert_contains "--help shows services" "$OUT" "pacman"
assert_contains "--help shows curl URL" "$OUT" "dist/ayneh.sh"

run_cli bash "$DIST" --list npm
assert_rc "--list npm exits 0" 0 "$RC"
assert_contains "--list npm shows Liara" "$OUT" "Liara"
assert_contains "--list npm shows ArvanCloud URL" "$OUT" "package-mirror.liara.ir"
assert_eq "--list npm line count" 7 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"

run_cli bash "$DIST" --list pypi
assert_rc "--list pypi exits 0" 0 "$RC"
assert_eq "--list pypi line count" 7 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"

run_cli bash "$DIST" --list
assert_rc "--list all exits 0" 0 "$RC"
assert_contains "--list all has apt section" "$OUT" "apt — Ubuntu"

run_cli bash "$DIST" --list bogus
assert_rc "--list bogus fails" 1 "$RC"
assert_contains "--list bogus explains" "$OUT" "Unknown service"

run_cli bash "$DIST" --scan bogus
assert_rc "--scan bogus fails fast" 1 "$RC"

run_cli bash "$DIST" --definitely-not-an-option
assert_rc "unknown option fails" 1 "$RC"

run_cli bash "$DIST" --apply npm NoSuchMirror
assert_rc "--apply unknown mirror fails" 1 "$RC"
assert_contains "--apply lists known names" "$OUT" "Liara"

printf '\n== library ==\n'
export AYNEH_LIB_ONLY=1
# shellcheck source=/dev/null
. "$DIST"

# shellcheck disable=SC2034  # consumed by alpine_branch
DISTRO_VERSION="3.20.3"
assert_eq "alpine branch from 3.20.3" "v3.20" "$(alpine_branch)"
# shellcheck disable=SC2034
DISTRO_VERSION="edge"
assert_eq "alpine branch for edge" "edge" "$(alpine_branch)"

if is_service alma; then ok_test "alma is a service alias"; else bad_test "alma is a service alias"; fi
if is_service nope; then bad_test "unknown service rejected"; else ok_test "unknown service rejected"; fi
assert_eq "centos probes as yum" "yum" "$(service_kind centos)"
assert_eq "ubuntu probes as apt" "apt" "$(service_kind ubuntu)"
assert_eq "resolve is case-insensitive" "https://package-mirror.liara.ir/repository/npm/" "$(resolve_mirror npm liara)"
if resolve_mirror npm no-such >/dev/null 2>&1; then bad_test "resolve rejects unknown"; else ok_test "resolve rejects unknown"; fi

# shellcheck disable=SC2034  # consumed by resolve_service_key
DISTRO_ID="ubuntu"; DISTRO_FAMILY="debian"
assert_eq "apt alias on ubuntu" "ubuntu" "$(resolve_service_key apt)"
DISTRO_ID="debian"
assert_eq "apt alias on debian" "debian" "$(resolve_service_key apt)"
DISTRO_ID="almalinux"
assert_eq "yum alias on almalinux" "almalinux" "$(resolve_service_key yum)"
# shellcheck disable=SC2034
DISTRO_ID="alpine"
# shellcheck disable=SC2034
DISTRO_FAMILY="alpine"
assert_eq "apt alias unavailable on alpine" "" "$(resolve_service_key apt)"

bad_urls=0
while IFS='|' read -r _ url; do
    [[ "$url" == */ ]] || bad_urls=$((bad_urls+1))
done < <(get_mirrors npm)
assert_eq "npm mirror URLs end with /" 0 "$bad_urls"

bad_urls=0
while IFS='|' read -r _ url; do
    [[ "$url" == */simple ]] || bad_urls=$((bad_urls+1))
done < <(get_mirrors pypi)
assert_eq "PyPI mirror URLs end with /simple" 0 "$bad_urls"

bad_urls=0
while IFS='|' read -r _ url; do
    [[ "$url" == https://* ]] || bad_urls=$((bad_urls+1))
done < <(get_mirrors docker)
assert_eq "Docker mirror URLs are https hosts" 0 "$bad_urls"

parsed="$(_parse_apply_target npm Liara)"
assert_eq "_parse_apply_target name" "Liara" "$(printf '%s\n' "$parsed" | sed -n '1p')"
assert_eq "_parse_apply_target url" "https://package-mirror.liara.ir/repository/npm/" "$(printf '%s\n' "$parsed" | sed -n '2p')"

printf '\n== backup / restore ==\n'
tmp="$(mktemp -d "${TMPDIR:-/tmp}/ayneh-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
# shellcheck disable=SC2034  # consumed by backup_file
USER_BACKUP_DIR="$tmp/backups"
printf 'version-one\n' > "$tmp/config.conf"
bak="$(backup_file "$tmp/config.conf" unit)"
if [[ -f "$bak" ]]; then ok_test "backup file created"; else bad_test "backup file created"; fi
if [[ -f "${bak}.meta" ]]; then ok_test "backup metadata created"; else bad_test "backup metadata created"; fi
assert_contains "metadata records source" "$(cat "${bak}.meta" 2>/dev/null || true)" "source=$tmp/config.conf"
printf 'version-two\n' > "$tmp/config.conf"
restore_backup "$bak" >/dev/null
assert_eq "restore recovers content" "version-one" "$(cat "$tmp/config.conf")"

printf '\n== result ==\n'
printf '  %s passed, ' "$pass"
printf '%s failed\n\n' "$fail"
[[ "$fail" -eq 0 ]]
