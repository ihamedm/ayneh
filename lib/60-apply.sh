# shellcheck shell=bash
# =============================================================================
# MIRROR APPLIERS
# Each applier: verifies the mirror, backs up what it touches, applies the
# change, and tells the user how to refresh package indexes. Returns 0 on
# success, non-zero on any failure.
# =============================================================================

apply_npm() {
    local name="$1" url="$2"
    hdr "Applying npm mirror: $name"
    ensure_tmpdir
    if ! mirror_reachable npm "$url"; then
        err "Mirror is not serving npm packages — aborting (try another)."
        return 1
    fi
    ok "Mirror reachable."

    local npmrc; npmrc="$(real_home)/.npmrc"
    [[ -f "$npmrc" ]] && backup_file "$npmrc" npm >/dev/null && info "Backed up $npmrc"

    if running_as_root && [[ -n "${SUDO_USER:-}" ]]; then
        if has_npm; then
            sudo -u "$SUDO_USER" npm config set registry "$url" 2>/dev/null \
                || printf 'registry=%s\n' "$url" | sudo -u "$SUDO_USER" tee -a "$npmrc" >/dev/null
        else
            printf 'registry=%s\n' "$url" | sudo -u "$SUDO_USER" tee -a "$npmrc" >/dev/null
        fi
    else
        if has_npm; then
            npm config set registry "$url" 2>/dev/null \
                || { printf 'registry=%s\n' "$url" >> "$npmrc"; }
        else
            warn "npm not installed — writing $npmrc directly."
            printf 'registry=%s\n' "$url" >> "$npmrc"
        fi
    fi
    ok "npm registry set to: $url"
    info "Check with: npm config get registry"
}

apply_pypi() {
    local name="$1" url="$2"
    hdr "Applying PyPI mirror: $name"
    ensure_tmpdir
    if ! mirror_reachable pypi "$url"; then
        err "Mirror is not serving PyPI packages — aborting."
        return 1
    fi
    ok "Mirror reachable."

    local host="${url#*://}"; host="${host%%/*}"
    local conf_file conf_dir
    if running_as_root; then
        conf_file="/etc/pip.conf"
    else
        conf_dir="$(real_home)/.config/pip"; mkdir -p "$conf_dir"
        conf_file="$conf_dir/pip.conf"
    fi
    [[ -f "$conf_file" ]] && backup_file "$conf_file" pip >/dev/null && info "Backed up $conf_file"

    local newconf="$AYNEH_TMPDIR/pip.conf.new"
    {
        printf '[global]\n'
        printf 'index-url = %s\n' "$url"
        printf 'trusted-host = %s\n' "$host"
    } > "$newconf"

    if running_as_root; then maybe_sudo install -m 0644 "$newconf" "$conf_file" || return 1
    else cp "$newconf" "$conf_file" || return 1; fi
    ok "pip index-url set to: $url"
    [[ -n "$conf_file" ]] && info "Config file: $conf_file"
}

apply_docker() {
    local name="$1" url="$2"
    hdr "Applying Docker registry mirror: $name"
    ensure_tmpdir
    require_root docker "$name" || return 1
    if ! mirror_reachable docker "$url"; then
        err "Mirror is not responding as a Docker registry — aborting."
        return 1
    fi
    ok "Mirror reachable."

    local dj=/etc/docker/daemon.json
    local tmpjson="$AYNEH_TMPDIR/daemon.json"
    maybe_sudo mkdir -p /etc/docker || return 1
    [[ -f "$dj" ]] && backup_file "$dj" docker >/dev/null && info "Backed up $dj"

    if have python3; then
        if ! python3 - "$dj" "$url" "$tmpjson" <<'PY'
import json, os, sys

path, mirror, out = sys.argv[1], sys.argv[2], sys.argv[3]
data = {}
if os.path.exists(path) and os.path.getsize(path) > 0:
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception as exc:  # keep going; the broken file has been backed up
        print("warning: existing daemon.json is not valid JSON: %s" % exc,
              file=sys.stderr)
        data = {}
mirrors = data.get("registry-mirrors", [])
if mirror in mirrors:
    mirrors.remove(mirror)
mirrors.insert(0, mirror)
seen, deduped = set(), []
for item in mirrors:
    if isinstance(item, str) and item not in seen:
        seen.add(item)
        deduped.append(item)
data["registry-mirrors"] = deduped
with open(out, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
        then
            err "Could not merge daemon.json (python3 failed). Nothing changed."
            return 1
        fi
        maybe_sudo install -m 0644 "$tmpjson" "$dj" || return 1
    elif [[ ! -e "$dj" ]]; then
        printf '{\n  "registry-mirrors": ["%s"]\n}\n' "$url" | maybe_sudo tee "$dj" >/dev/null || return 1
    else
        err "python3 is required to safely merge an existing daemon.json."
        err "Install python3 and retry, or edit $dj manually."
        return 1
    fi

    ok "registry-mirrors now:"
    maybe_sudo sed 's/^/    /' "$dj"
    warn "Restart the Docker daemon to apply:"
    printf '    %s\n' "sudo systemctl restart docker   # or: sudo service docker restart"
}

# Generic apt host-swap for Ubuntu/Debian.
# $1=service (ubuntu|debian)  $2=mirror name  $3=mirror url
apply_apt() {
    local svc="$1" name="$2" url="$3"
    hdr "Applying apt mirror ($svc): $name"
    ensure_tmpdir
    require_root "$svc" "$name" || return 1
    if ! mirror_reachable apt "$url"; then
        err "Mirror is not serving the ${DISTRO_CODENAME:-configured} release — aborting."
        return 1
    fi
    ok "Mirror reachable for ${DISTRO_CODENAME:-this release}."

    # Host-swap per distro:
    #  - Ubuntu: any *ubuntu.com/ubuntu host/path → <mirror>
    #  - Debian: any *debian.org/debian host/path → <mirror>
    #    (this also rewrites /debian-security correctly, because only the
    #     substring ".../debian" is replaced and "-security" is kept)
    local sed_expr
    if [[ "$svc" == "ubuntu" ]]; then
        sed_expr="s|https?://[a-z0-9.-]*ubuntu\\.com/ubuntu|${url}|g"
    else
        sed_expr="s|https?://[a-z0-9.-]*debian\\.org/debian|${url}|g"
    fi

    local files=() f
    [[ -f /etc/apt/sources.list ]] && files+=(/etc/apt/sources.list)
    for f in /etc/apt/sources.list.d/*.list; do [[ -e "$f" ]] && files+=("$f"); done
    for f in /etc/apt/sources.list.d/*.sources; do [[ -e "$f" ]] && files+=("$f"); done
    if [[ "${#files[@]}" -eq 0 ]]; then
        warn "No apt sources files found to edit."
        return 1
    fi

    local tmpf before after changed=0
    for f in "${files[@]}"; do
        tmpf="$AYNEH_TMPDIR/$(basename "$f")"
        if ! maybe_sudo cat "$f" > "$tmpf" 2>/dev/null; then
            cat "$f" > "$tmpf" 2>/dev/null || continue
        fi
        before="$(cksum < "$tmpf")"
        sed -E -i "$sed_expr" "$tmpf"
        after="$(cksum < "$tmpf")"
        if [[ "$before" == "$after" ]]; then
            info "No upstream Ubuntu/Debian hosts in $f — left unchanged."
            continue
        fi
        backup_file "$f" apt >/dev/null && info "Backed up $f"
        if running_as_root; then
            maybe_sudo install -m 0644 "$tmpf" "$f" || return 1
        else
            maybe_sudo install -m 0644 "$tmpf" "$f" 2>/dev/null || cp "$tmpf" "$f" || return 1
        fi
        changed=$((changed+1))
    done
    if [[ "$changed" -eq 0 ]]; then
        warn "No apt sources were rewritten (no matching upstream hosts)."
        return 1
    fi
    ok "apt sources rewritten to: $url"
    warn "Refresh indexes:"
    printf '    %s\n' "sudo apt update"
}

apply_pacman() {
    local name="$1" url="$2"
    hdr "Applying pacman mirror: $name"
    ensure_tmpdir
    require_root pacman "$name" || return 1
    if ! mirror_reachable pacman "$url"; then
        err "Mirror is not serving Arch packages — aborting."
        return 1
    fi
    ok "Mirror reachable."

    local ml=/etc/pacman.d/mirrorlist
    local server="${url%/}/\$repo/os/\$arch"
    if grep -qF "Server = $server" "$ml" 2>/dev/null; then
        info "This mirror is already present in $ml."
    fi
    [[ -f "$ml" ]] && backup_file "$ml" pacman >/dev/null && info "Backed up $ml"

    local tmpf="$AYNEH_TMPDIR/mirrorlist"
    if ! maybe_sudo cat "$ml" > "$tmpf" 2>/dev/null; then
        cat "$ml" > "$tmpf" 2>/dev/null || return 1
    fi
    {
        printf '## Added by ayneh — %s — %s\n' "$name" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'Server = %s\n\n' "$server"
        cat "$tmpf"
    } > "$tmpf.new"

    if running_as_root; then
        maybe_sudo install -m 0644 "$tmpf.new" "$ml" || return 1
    else
        maybe_sudo install -m 0644 "$tmpf.new" "$ml" 2>/dev/null || cp "$tmpf.new" "$ml" || return 1
    fi
    ok "pacman mirror prepended: $url"
    warn "Refresh indexes:"
    printf '    %s\n' "sudo pacman -Syyu"
}

apply_apk() {
    local name="$1" url="$2"
    hdr "Applying apk mirror: $name"
    ensure_tmpdir
    require_root apk "$name" || return 1
    if ! mirror_reachable apk "$url"; then
        err "Mirror is not serving Alpine APKINDEX — aborting."
        return 1
    fi
    ok "Mirror reachable."

    local rep=/etc/apk/repositories
    [[ -f "$rep" ]] && backup_file "$rep" apk >/dev/null && info "Backed up $rep"
    local tmpf="$AYNEH_TMPDIR/repositories"
    if ! maybe_sudo cat "$rep" > "$tmpf" 2>/dev/null; then
        cat "$rep" > "$tmpf" 2>/dev/null || return 1
    fi
    local before after
    before="$(cksum < "$tmpf")"
    sed -E -i "s|https?://dl-cdn\.alpinelinux\.org/alpine|${url%/}|g" "$tmpf"
    after="$(cksum < "$tmpf")"
    if [[ "$before" == "$after" ]]; then
        warn "No dl-cdn.alpinelinux.org entries found in $rep — nothing changed."
        return 1
    fi
    if running_as_root; then
        maybe_sudo install -m 0644 "$tmpf" "$rep" || return 1
    else
        maybe_sudo install -m 0644 "$tmpf" "$rep" 2>/dev/null || cp "$tmpf" "$rep" || return 1
    fi
    ok "apk repositories rewritten to: $url"
    warn "Refresh indexes:"
    printf '    %s\n' "sudo apk update"
}

# Generic yum/dnf host-swap.
# $1=service (centos|rocky|almalinux|fedora|epel)  $2=name  $3=url
apply_yum() {
    local svc="$1" name="$2" url="$3"
    hdr "Applying dnf/yum mirror ($svc): $name"
    ensure_tmpdir
    require_root "$svc" "$name" || return 1
    if ! mirror_reachable yum "$url" "$svc"; then
        err "Mirror does not serve the ${DISTRO_ID} ${DISTRO_VERSION} repository tree — aborting."
        return 1
    fi
    ok "Mirror reachable for ${DISTRO_ID} ${DISTRO_VERSION}."

    local -A upstreams=(
        [centos]='mirror.stream.centos.org mirror.centos.org'
        [rocky]='dl.rockylinux.org'
        [almalinux]='repo.almalinux.org'
        [fedora]='download.fedoraproject.org dl.fedoraproject.org mirrors.fedoraproject.org'
        [epel]='download.fedoraproject.org dl.fedoraproject.org'
    )
    local ups="${upstreams[$svc]:-}"
    [[ -z "$ups" ]] && { err "Unknown yum service: $svc"; return 1; }

    # Build the replacement: upstream root → mirror root.
    # e.g. dl.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os
    #   →  https://mirror.arvancloud.ir/rocky/9/BaseOS/x86_64/os
    local changed=0 f
    local tmpf before after u
    for f in /etc/yum.repos.d/*.repo; do
        [[ -e "$f" ]] || continue
        tmpf="$AYNEH_TMPDIR/$(basename "$f")"
        if ! maybe_sudo cat "$f" > "$tmpf" 2>/dev/null; then
            cat "$f" > "$tmpf" 2>/dev/null || continue
        fi
        before="$(cksum < "$tmpf")"
        # Uncomment a commented baseurl only when it points at a known upstream,
        # so a user's own commented-out private mirror is left alone.
        for u in $ups; do
            sed -E -i "s|^([[:space:]]*)#+[[:space:]]*(baseurl=https?://${u})|\1\2|" "$tmpf"
        done
        for u in $ups; do
            case "$svc:$u" in
                centos:*)    sed -E -i "s|https?://${u}/centos|${url}|g; s|https?://${u}|${url}|g" "$tmpf" ;;
                rocky:*)     sed -E -i "s|https?://${u}/pub/rocky|${url}|g" "$tmpf" ;;
                almalinux:*) sed -E -i "s|https?://${u}/pub/almalinux|${url}|g; s|https?://${u}/almalinux|${url}|g" "$tmpf" ;;
                fedora:*)    sed -E -i "s#https?://${u}/pub/fedora/linux#${url%/}#g; s#https?://${u}/pub/fedora#${url%/}#g" "$tmpf" ;;
                epel:*)      sed -E -i "s#https?://${u}/pub/epel#${url%/}#g" "$tmpf" ;;
            esac
        done
        # Count sections and sections that have an ACTIVE baseurl. Metalink /
        # mirrorlist may only be commented out when every section has a baseurl,
        # otherwise dnf would be left with no URL at all.
        local counts sec_total sec_base
        counts="$(awk '
            /^\[/ { if (in_sec) { total++; if (has_base) with_base++ } in_sec=1; has_base=0; next }
            /^[[:space:]]*baseurl[[:space:]]*=/ { has_base=1 }
            END { if (in_sec) { total++; if (has_base) with_base++ } ; print total+0, with_base+0 }
        ' "$tmpf")"
        sec_total="${counts%% *}"; sec_base="${counts##* }"
        if [[ "$sec_total" -gt 0 && "$sec_total" == "$sec_base" ]]; then
            # Comment out metalink/mirrorlist so baseurl takes effect.
            sed -E -i 's|^([[:space:]]*)(metalink=)|\1#\2|g; s|^([[:space:]]*)(mirrorlist=)|\1#\2|g' "$tmpf"
        else
            warn "Some sections in $(basename "$f") use mirrorlist without a baseurl; left them enabled."
        fi
        after="$(cksum < "$tmpf")"
        [[ "$before" == "$after" ]] && continue
        backup_file "$f" yum >/dev/null && info "Backed up $f"
        if running_as_root; then
            maybe_sudo install -m 0644 "$tmpf" "$f" || return 1
        else
            maybe_sudo install -m 0644 "$tmpf" "$f" 2>/dev/null || cp "$tmpf" "$f" || return 1
        fi
        changed=$((changed+1))
    done
    if [[ "$changed" -eq 0 ]]; then
        warn "No repo files matched this upstream — nothing changed."
        return 1
    fi
    ok "Repo files rewritten (host-swap to: $url)."
    warn "Refresh indexes:"
    printf '    %s\n' "sudo $PKGMGR makecache   # or: sudo $PKGMGR check-update"
}

# Dispatcher: apply a mirror for any service.
apply_mirror() {
    require_curl
    local svc="$1" name="$2" url="$3"
    case "$svc" in
        npm)    apply_npm    "$name" "$url" ;;
        pypi)   apply_pypi   "$name" "$url" ;;
        docker) apply_docker "$name" "$url" ;;
        ubuntu|debian) apply_apt "$svc" "$name" "$url" ;;
        centos|rocky|almalinux|alma|fedora|epel) apply_yum "$svc" "$name" "$url" ;;
        pacman) apply_pacman "$name" "$url" ;;
        apk)    apply_apk    "$name" "$url" ;;
        *) err "Unknown service: $svc"; return 1 ;;
    esac
}
