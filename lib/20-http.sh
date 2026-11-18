# shellcheck shell=bash
# =============================================================================
# HTTP probe helpers
# =============================================================================

# The tool is written around curl; fail early with an actionable message.
require_curl() {
    have curl || die "curl is required but was not found in PATH. Install it (e.g. apt install curl) and retry."
}

# Print HTTP status code for a URL ("000" on failure). Fast and reliable.
# --max-filesize aborts the body download the instant it starts (we only need
# the status line), so probes stay quick even for multi-MB responses. We do NOT
# add a "|| echo 000" fallback: %{http_code} already prints "000" when curl
# never reached the server, and appending "000" after a real code on curl's
# non-zero exit (63=max-filesize, 28=timeout) would corrupt the value.
http_code() {
    local url="$1"
    curl -s -o /dev/null -w '%{http_code}' \
         --max-filesize 1024 \
         --connect-timeout "$AYNEH_CONNECT_TIMEOUT" \
         --max-time "$AYNEH_MAX_TIME" \
         -L "$url" 2>/dev/null
}

# Probe a URL and print a human-readable status line.
# $1=label  $2=url  $3=comma-separated "good" codes (default 200)
probe_url() {
    local label="$1" url="$2" good="${3:-200}" code
    code="$(http_code "$url")"
    local status color
    if [[ ",$good," == *",$code,"* ]]; then
        status="OK"; color="$C_GREEN"
    elif [[ "$code" == "000" ]]; then
        status="UNREACHABLE"; color="$C_RED"
    else
        status="HTTP $code"; color="$C_YELLOW"
    fi
    printf '  %s%-12s%s  %-6s  %s  %s%s%s\n' \
        "$color" "$status" "$C_OFF" "$code" "$label" "$C_DIM" "$url" "$C_OFF"
    [[ ",$good," == *",$code,"* ]] || AYNEH_PROBE_FAILURES=$((AYNEH_PROBE_FAILURES + 1))
}

# Test whether a mirror actually serves packages (not just a landing page).
# Returns 0 (reachable & serving) or 1. The probe path depends on the kind of
# repository; several candidate paths are tried for layouts that vary between
# mirrors (notably yum and apk).
mirror_reachable() {
    local kind="$1" url="$2" svc="${3:-$1}" base="${2%/}" code
    case "$kind" in
        npm)
            code="$(http_code "${base}/npm")"
            [[ "$code" == "200" || "$code" == "301" || "$code" == "302" ]]
            ;;
        pypi)
            code="$(http_code "${base}/pip/")"
            [[ "$code" == "200" || "$code" == "301" || "$code" == "302" ]]
            ;;
        docker)
            code="$(http_code "${base}/v2/")"
            # Docker registry answers 401 on /v2/ — that means it is alive.
            [[ "$code" == "200" || "$code" == "401" ]]
            ;;
        apt)
            [[ -z "$DISTRO_CODENAME" ]] && return 1
            code="$(http_code "${base}/dists/${DISTRO_CODENAME}/Release")"
            [[ "$code" == "200" || "$code" == "301" || "$code" == "302" ]]
            ;;
        yum)
            # Mirror roots differ in their distro layout (e.g. /rocky vs
            # /rocky/9), and each RHEL flavor has its own tree. Probe the real
            # repodata path for the running release first, then fall back to
            # generic layouts.
            local major="${DISTRO_VERSION%%.*}"
            local -a cands=()
            case "$svc" in
                rocky)      cands=("${base}/${major}/BaseOS/${DISTRO_ARCH}/os/repodata/repomd.xml"
                                   "${base}/${DISTRO_VERSION}/BaseOS/${DISTRO_ARCH}/os/repodata/repomd.xml") ;;
                almalinux)  cands=("${base}/${major}/BaseOS/${DISTRO_ARCH}/os/repodata/repomd.xml"
                                   "${base}/${DISTRO_VERSION}/BaseOS/${DISTRO_ARCH}/os/repodata/repomd.xml") ;;
                centos)     cands=("${base}/${major}-stream/BaseOS/${DISTRO_ARCH}/os/repodata/repomd.xml"
                                   "${base}/${major}/BaseOS/${DISTRO_ARCH}/os/repodata/repomd.xml") ;;
                fedora)     cands=("${base}/releases/${DISTRO_VERSION}/Everything/${DISTRO_ARCH}/os/repodata/repomd.xml") ;;
                epel)       cands=("${base}/${major}/Everything/${DISTRO_ARCH}/repodata/repomd.xml"
                                   "${base}/${DISTRO_VERSION}/Everything/${DISTRO_ARCH}/repodata/repomd.xml") ;;
            esac
            cands+=("${base}/repodata/repomd.xml" "${base}/")
            for cand in "${cands[@]}"; do
                code="$(http_code "$cand")"
                case "$code" in
                    200|301|302) return 0 ;;
                    403) [[ "$cand" == "${base}/" ]] && return 0 ;;
                esac
            done
            return 1
            ;;
        pacman)
            code="$(http_code "${base}/core/os/${DISTRO_ARCH}/")"
            [[ "$code" == "200" || "$code" == "301" || "$code" == "302" ]]
            ;;
        apk)
            local branch cand
            branch="$(alpine_branch)"
            for cand in \
                "${base}/${branch}/main/${DISTRO_ARCH}/APKINDEX.tar.gz" \
                "${base}/${branch}/community/${DISTRO_ARCH}/APKINDEX.tar.gz" \
                "${base}/${DISTRO_ARCH}/APKINDEX.tar.gz"; do
                code="$(http_code "$cand")"
                [[ "$code" == "200" || "$code" == "301" || "$code" == "302" ]] && return 0
            done
            return 1
            ;;
        *)
            code="$(http_code "$base")"
            [[ "$code" == "200" || "$code" == "301" || "$code" == "302" ]]
            ;;
    esac
}
