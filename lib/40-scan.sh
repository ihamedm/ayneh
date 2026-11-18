# shellcheck shell=bash
# =============================================================================
# UPSTREAM SCANNERS — test the default upstream (and configured repos) for each
# service. These functions only read configuration; they never modify anything.
# =============================================================================

scan_npm() {
    hdr "npm registry"
    if ! has_npm; then warn "npm not installed — skipped."; return; fi
    local cur=""
    cur="$(npm config get registry 2>/dev/null || true)"
    info "current registry: ${cur:-unknown}"
    probe_url "npm upstream" "https://registry.npmjs.org/" 200
}

scan_pypi() {
    hdr "Python PyPI / pip"
    if ! has_pip; then warn "pip not installed — skipped."; return; fi
    local cur=""
    cur="$("$(pip_cmd)" config get global.index-url 2>/dev/null || true)"
    info "current index-url: ${cur:-default (https://pypi.org/simple)}"
    probe_url "PyPI upstream" "https://pypi.org/simple/" 200
}

scan_docker() {
    hdr "Docker registry"
    if ! has_docker; then warn "Docker not installed — skipped."; return; fi
    info "configured registry-mirrors:"
    if [[ -f /etc/docker/daemon.json ]]; then
        maybe_sudo grep -A5 registry-mirrors /etc/docker/daemon.json 2>/dev/null \
            | sed 's/^/    /' || info "    (none configured)"
    else
        info "    (no /etc/docker/daemon.json — using Docker Hub defaults)"
    fi
    # Docker registry answers 401 to anonymous /v2/ — that is "reachable".
    probe_url "Docker Hub upstream" "https://registry-1.docker.io/v2/" 401
}

# Return the configured apt source URIs (one per line, deduped).
# Handles classic .list (deb/deb-src lines) and deb822 .sources (URIs: lines).
_apt_uris() {
    {
        [[ -f /etc/apt/sources.list ]] && cat /etc/apt/sources.list 2>/dev/null
        for f in /etc/apt/sources.list.d/*.list; do
            [[ -e "$f" ]] && cat "$f" 2>/dev/null
        done
        for f in /etc/apt/sources.list.d/*.sources; do
            [[ -e "$f" ]] || continue
            awk '/^URIs:/{sub(/^URIs:[ \t]*/,""); gsub(/[ \t]+/,"\n"); print}' "$f" 2>/dev/null
        done
    } 2>/dev/null \
      | grep -oE 'https?://[^[:space:]"]+' | sed 's|/$||' | sort -u
}

# Print "uri|suite" pairs from apt sources (classic .list + deb822 .sources).
# Used for scanning the ACTUAL configured suite (e.g. trixie-security) rather
# than guessing from the codename — avoids false 404s on security repos.
_apt_sources() {
    local f
    {
        [[ -f /etc/apt/sources.list ]] && cat /etc/apt/sources.list 2>/dev/null
        for f in /etc/apt/sources.list.d/*.list; do [[ -e "$f" ]] && cat "$f" 2>/dev/null; done
    } 2>/dev/null | awk '
        /^[[:space:]]*(deb|deb-src)[[:space:]]/{
            sub(/^[[:space:]]*(deb|deb-src)[[:space:]]+/, "")
            while ($0 ~ /^\[/) sub(/^\[[^]]*\][[:space:]]*/, "")
            if ($1 != "" && $2 != "") print $1"|"$2
        }'
    for f in /etc/apt/sources.list.d/*.sources; do
        [[ -e "$f" ]] || continue
        awk '
            BEGIN{RS=""; FS="\n"}
            {
                uri=""; suite=""
                for (i=1; i<=NF; i++) {
                    if      ($i ~ /^URIs:/)   { sub(/^URIs:[ \t]*/,"",$i);   uri=$i }
                    else if ($i ~ /^Suites:/) { sub(/^Suites:[ \t]*/,"",$i); suite=$i }
                }
                if (uri != "" && suite != "") {
                    split(suite, S, /[ \t]+/); split(uri, U, /[ \t]+/)
                    for (k in U) if (U[k] != "") print U[k]"|"S[1]
                }
            }' "$f" 2>/dev/null
    done
}

scan_apt() {
    hdr "apt repositories ($DISTRO_ID)"
    if ! has_apt; then warn "apt not available — skipped."; return; fi
    local count=0 uri suite base
    while IFS='|' read -r uri suite; do
        [[ -z "$uri" || -z "$suite" ]] && continue
        count=$((count+1))
        base="${uri%/}"
        probe_url "apt $suite" "${base}/dists/${suite}/Release" 200
    done < <(_apt_sources | sort -u)
    [[ "$count" -eq 0 ]] && warn "No apt sources found."
}

# Return yum baseurls / metalinks (with $releasever/$basearch expanded).
_yum_repos() {
    local f
    for f in /etc/yum.repos.d/*.repo; do
        [[ -e "$f" ]] || continue
        awk -v rel="$DISTRO_VERSION" -v arch="$DISTRO_ARCH" '
            /^\[/{name=$0; next}
            /^[[:space:]]*baseurl[[:space:]]*=/{
                sub(/^[[:space:]]*baseurl[[:space:]]*=/,""); gsub(/\$releasever/, rel); gsub(/\$basearch/, arch); gsub(/\$arch/, arch);
                print "B|"name"|"$0
            }
            /^[[:space:]]*metalink[[:space:]]*=/{
                sub(/^[[:space:]]*metalink[[:space:]]*=/,""); gsub(/\$releasever/, rel); gsub(/\$basearch/, arch); gsub(/\$arch/, arch);
                print "M|"name"|"$0
            }
            /^[[:space:]]*mirrorlist[[:space:]]*=/{
                sub(/^[[:space:]]*mirrorlist[[:space:]]*=/,""); gsub(/\$releasever/, rel); gsub(/\$basearch/, arch); gsub(/\$arch/, arch);
                print "L|"name"|"$0
            }
        ' "$f" 2>/dev/null
    done
}

scan_yum() {
    hdr "dnf/yum repositories"
    if ! has_yum; then warn "dnf/yum not available — skipped."; return; fi
    local count=0 kind repoid url
    while IFS='|' read -r kind repoid url; do
        [[ -z "$url" ]] && continue
        count=$((count+1))
        case "$kind" in
            B) probe_url "baseurl $repoid" "${url%/}/repodata/repomd.xml" 200 ;;
            M|L) probe_url "metalink $repoid" "$url" 200,302,301 ;;
        esac
    done < <(_yum_repos)
    [[ "$count" -eq 0 ]] && warn "No yum/dnf repos found."
}

scan_pacman() {
    hdr "pacman mirrorlist"
    if ! has_pacman; then warn "pacman not available — skipped."; return; fi
    local first=""
    first="$(awk '/^[[:space:]]*Server[[:space:]]*=/{print $3; exit}' /etc/pacman.d/mirrorlist 2>/dev/null)"
    if [[ -z "$first" ]]; then
        warn "No Server entries in /etc/pacman.d/mirrorlist."
        return
    fi
    info "first mirror: $first"
    # Expand $repo/$arch to test with the core repo.
    local test_url="${first//\$repo/core}"
    test_url="${test_url//\$arch/$DISTRO_ARCH}"
    probe_url "pacman mirror" "$test_url" 200
}

scan_apk() {
    hdr "apk repositories"
    if ! has_apk; then warn "apk not available — skipped."; return; fi
    local count=0 line url test
    while IFS= read -r line; do
        line="${line%%#*}"
        # Trim surrounding whitespace.
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue
        count=$((count+1))
        url="${line%/}"
        if [[ "$url" == http://* || "$url" == https://* ]]; then
            test="${url}/${DISTRO_ARCH}/APKINDEX.tar.gz"
            probe_url "apk repo #$count" "$test" 200
        else
            info "apk repo #$count: $url (local path — not probed)"
        fi
    done < /etc/apk/repositories 2>/dev/null
    [[ "$count" -eq 0 ]] && warn "No apk repositories configured."
}

# Run the scanner for a single service key (aliases like apt/yum allowed).
scan_service() {
    local key
    key="$(resolve_service_key "$1")"
    if [[ -z "$key" ]]; then
        err "Cannot map '$1' to a package family on this system."
        return 1
    fi
    case "$key" in
        npm)                scan_npm ;;
        pypi)               scan_pypi ;;
        docker)             scan_docker ;;
        ubuntu|debian)      scan_apt ;;
        centos|rocky|almalinux|alma|fedora|epel) scan_yum ;;
        pacman)             scan_pacman ;;
        apk)                scan_apk ;;
        *) err "Unknown service: $1"; return 1 ;;
    esac
}

scan_all() {
    require_curl
    AYNEH_PROBE_FAILURES=0
    hdr "System"
    os_summary
    scan_npm
    scan_pypi
    scan_docker
    if has_apt;    then scan_apt;    fi
    if has_yum;    then scan_yum;    fi
    if has_pacman; then scan_pacman; fi
    if has_apk;    then scan_apk;    fi
    echo
    if [[ "${AYNEH_PROBE_FAILURES:-0}" -eq 0 ]]; then
        ok "Scan complete. All probed endpoints responded."
    else
        warn "Scan complete. ${AYNEH_PROBE_FAILURES} endpoint(s) need attention — see the lines marked UNREACHABLE / HTTP 4xx/5xx."
        info "Run 'ayneh' → 3) Apply / switch a mirror to fix them."
    fi
}

# =============================================================================
# CURRENT CONFIG DISPLAY
# =============================================================================
show_config() {
    hdr "Current configuration"
    os_summary

    if has_npm; then
        printf '\n%s\n' "${C_BOLD}npm:${C_OFF}"
        printf '  registry: %s\n' "$(npm config get registry 2>/dev/null || echo '?')"
    fi
    if has_pip; then
        printf '\n%s\n' "${C_BOLD}pip:${C_OFF}"
        printf '  index-url: %s\n' "$("$(pip_cmd)" config get global.index-url 2>/dev/null || echo 'default (https://pypi.org/simple)')"
    fi
    if has_docker; then
        printf '\n%s\n' "${C_BOLD}docker:${C_OFF}"
        if [[ -f /etc/docker/daemon.json ]]; then
            printf '  daemon.json:\n'
            maybe_sudo sed 's/^/    /' /etc/docker/daemon.json 2>/dev/null
        else
            printf '  daemon.json: (none — Docker Hub defaults)\n'
        fi
    fi
    if has_apt; then
        printf '\n%s\n' "${C_BOLD}apt sources:${C_OFF}"
        _apt_uris | sed 's/^/  /'
    fi
    if has_yum; then
        printf '\n%s\n' "${C_BOLD}yum/dnf baseurls:${C_OFF}"
        _yum_repos | awk -F'|' '{print "  "$2"  "$3}'
    fi
    if has_pacman; then
        printf '\n%s\n' "${C_BOLD}pacman mirrors:${C_OFF}"
        awk '/^[[:space:]]*Server[[:space:]]*=/{print "  "$0}' /etc/pacman.d/mirrorlist 2>/dev/null | head -3
    fi
    if has_apk; then
        printf '\n%s\n' "${C_BOLD}apk repositories:${C_OFF}"
        sed 's/^/  /' /etc/apk/repositories 2>/dev/null
    fi
    echo
}
