#!/usr/bin/env bash
# =============================================================================
# ayneh installer — downloads the single-file release and installs the `ayneh`
# command. Intended to be piped through sudo:
#
#   curl -fsSL https://raw.githubusercontent.com/ihamedm/ayneh/main/install.sh | sudo bash
#
# Environment overrides:
#   AYNEH_REF=main          git ref (branch/tag) to install
#   AYNEH_REPO=ihamedm/ayneh
#   AYNEH_BASE_URL=...      override the download base (mirrors/testing)
#   PREFIX=/usr/local       install prefix (binary goes to $PREFIX/bin)
#   BINDIR=...              explicit binary directory
# =============================================================================
set -euo pipefail

AYNEH_REF="${AYNEH_REF:-main}"
AYNEH_REPO="${AYNEH_REPO:-ihamedm/ayneh}"
PREFIX="${PREFIX:-/usr/local}"
BINDIR="${BINDIR:-${PREFIX}/bin}"
TARGET="${BINDIR}/ayneh"

say()  { printf '\033[36m[i]\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m[+]\033[0m %s\n' "$*"; }
die()  { printf '\033[31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

if [[ "${1:-}" == "--uninstall" ]]; then
    [[ "${EUID}" -eq 0 ]] || die "Run with sudo: curl ... | sudo bash -s -- --uninstall"
    rm -f "$TARGET"
    ok "Removed $TARGET"
    exit 0
fi

if [[ "${EUID}" -ne 0 ]]; then
    die "Root is required to write to $BINDIR. Re-run with: curl ... | sudo bash"
fi

command -v bash >/dev/null 2>&1 || die "bash is required."
(( BASH_VERSINFO[0] >= 4 )) || die "bash 4+ is required (you have ${BASH_VERSION})."

base_url="${AYNEH_BASE_URL:-https://raw.githubusercontent.com/${AYNEH_REPO}/${AYNEH_REF}}"
url="${base_url%/}/dist/ayneh.sh"
tmp="$(mktemp "${TMPDIR:-/tmp}/ayneh-install.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

say "Downloading ${url}"
if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 2 --connect-timeout 10 -o "$tmp" "$url" || die "Download failed."
elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$tmp" "$url" || die "Download failed."
else
    die "Either curl or wget is required."
fi

[[ -s "$tmp" ]] || die "Downloaded file is empty."
bash -n "$tmp" || die "Downloaded script failed the syntax check; aborting."
install -d -m 0755 "$BINDIR"
install -m 0755 "$tmp" "$TARGET"
ok "Installed ayneh to $TARGET"

if [[ ":${PATH}:" != *":${BINDIR}:"* ]]; then
    say "Note: $BINDIR is not in your PATH."
fi
"$TARGET" --version 2>/dev/null || true
say "Run 'ayneh' to start, or 'ayneh --help' for the CLI."
