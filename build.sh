#!/usr/bin/env bash
# Build the single-file, curl-friendly script from lib/*.sh.
#
#   ./build.sh            regenerate dist/ayneh.sh
#   ./build.sh --check    fail if dist/ayneh.sh is out of date (CI)
#
# The output is deterministic: no timestamps, so `build.sh --check` is stable.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
out="$root/dist/ayneh.sh"
mode="${1:-build}"

version="$(sed -n 's/^AYNEH_VERSION="\(.*\)"/\1/p' "$root/lib/00-core.sh" | head -1)"
[[ -n "$version" ]] || { echo "build: could not read AYNEH_VERSION" >&2; exit 1; }

tmp="$(mktemp "${TMPDIR:-/tmp}/ayneh-build.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

{
    printf '#!/usr/bin/env bash\n'
    printf '# =============================================================================\n'
    printf '#  ayneh v%s — Iranian repository mirror scanner & configurator\n' "$version"
    printf '# -----------------------------------------------------------------------------\n'
    printf '#  GENERATED FILE — do not edit directly.\n'
    printf '#  Source: https://github.com/ihamedm/ayneh/tree/main/lib\n'
    printf '#  Rebuild: ./build.sh\n'
    printf '#\n'
    printf '#  One-line run:\n'
    printf '#    curl -fsSL https://raw.githubusercontent.com/ihamedm/ayneh/main/dist/ayneh.sh | bash\n'
    printf '#  License: MIT\n'
    printf '# =============================================================================\n'
    for f in "$root"/lib/*.sh; do
        printf '\n# ===== %s =====\n' "$(basename "$f")"
        cat "$f"
    done
    printf '\n# ===== entrypoint =====\n'
    # shellcheck disable=SC2016  # emitted literally into the generated file
    printf 'if [[ "${AYNEH_LIB_ONLY:-0}" != "1" ]]; then\n'
    printf '    main "$@"\n'
    printf 'fi\n'
} > "$tmp"

if ! bash -n "$tmp"; then
    echo "build: generated script has a syntax error" >&2
    exit 1
fi

if [[ "$mode" == "--check" ]]; then
    if [[ ! -f "$out" ]]; then
        echo "build: $out is missing; run ./build.sh" >&2
        exit 1
    fi
    if ! cmp -s "$tmp" "$out"; then
        echo "build: dist/ayneh.sh is out of date; run ./build.sh and commit the result" >&2
        exit 1
    fi
    echo "build: dist/ayneh.sh is up to date (v$version)"
    exit 0
fi

mkdir -p "$root/dist"
install -m 0755 "$tmp" "$out"
echo "build: wrote ${out#"$root"/} (v$version)"
