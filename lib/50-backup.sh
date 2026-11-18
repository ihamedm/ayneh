# shellcheck shell=bash
# =============================================================================
# BACKUP / RESTORE
# -----------------------------------------------------------------------------
# Every file we are about to modify is copied to a timestamped .bak file, with
# a small .meta sidecar recording the original path. The sidecar makes restore
# reliable even when the original file has been moved or renamed.
# =============================================================================

# Print the directory that backs up a given source path.
_backup_dir_for() {
    local src="$1"
    if [[ "$src" == /etc/* || "$src" == /var/* ]]; then
        printf '%s\n' "$SYS_BACKUP_DIR"
    else
        printf '%s\n' "$USER_BACKUP_DIR"
    fi
}

# Write the .meta sidecar next to a backup (best effort).
_write_backup_meta() {
    local dest="$1" src="$2" tag="$3"
    local body
    body="$(printf 'source=%s\ntag=%s\ncreated=%s\n' "$src" "$tag" "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
    if [[ "$dest" == /var/* ]]; then
        printf '%s\n' "$body" | maybe_sudo tee "${dest}.meta" >/dev/null 2>&1 || true
    else
        printf '%s\n' "$body" > "${dest}.meta" 2>/dev/null || true
    fi
}

# Back up a file, print the backup path on success. $1=source $2=tag
backup_file() {
    local src="$1" tag="${2:-manual}"
    [[ ! -e "$src" ]] && return 1
    local stamp dest_dir dest base
    stamp="$(date +%Y%m%d-%H%M%S)"
    dest_dir="$(_backup_dir_for "$src")"
    base="${src##*/}"
    dest="${dest_dir}/${base}.${tag}.${stamp}.bak"

    if [[ "$dest_dir" == /var/* ]]; then
        maybe_sudo mkdir -p "$dest_dir" || return 1
        maybe_sudo cp -a "$src" "$dest" || return 1
    else
        mkdir -p "$dest_dir" || return 1
        cp -a "$src" "$dest" || return 1
    fi
    _write_backup_meta "$dest" "$src" "$tag"
    printf '%s\n' "$dest"
}

# Print all backup files, newest last, including legacy 1.x locations.
list_backups() {
    hdr "Available backups"
    local found=0 d f src
    for d in "$USER_BACKUP_DIR" "$LEGACY_USER_BACKUP_DIR" "$SYS_BACKUP_DIR" "$LEGACY_SYS_BACKUP_DIR"; do
        [[ -d "$d" ]] || continue
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            src=""
            [[ -f "${f}.meta" ]] && src="$(sed -n 's/^source=//p' "${f}.meta" 2>/dev/null | head -1)"
            printf '  %s\n' "$f"
            [[ -n "$src" ]] && printf '      %s→ %s%s\n' "$C_DIM" "$src" "$C_OFF"
            found=$((found+1))
        done < <(find "$d" -maxdepth 1 -type f -name '*.bak' 2>/dev/null | sort)
    done
    if [[ "$found" -eq 0 ]]; then
        warn "No backups found yet."
        return 1
    fi
    return 0
}

# Restore a backup file to its original location. Reads the .meta sidecar when
# present and falls back to guessing from the filename for 1.x backups.
restore_backup() {
    local p="$1"
    [[ ! -f "$p" ]] && { err "File not found: $p"; return 1; }

    local target=""
    [[ -f "${p}.meta" ]] && target="$(sed -n 's/^source=//p' "${p}.meta" 2>/dev/null | head -1)"

    if [[ -z "$target" ]]; then
        local base; base="$(basename "$p")"
        local name
        name="$(printf '%s\n' "$base" | sed -E 's/\.[^.]+\.[^.]+\.bak$//')"
        local cand
        for cand in "/etc/$name" "/etc/docker/$name" "/etc/apt/$name" \
                    "/etc/apt/sources.list.d/$name" "/etc/yum.repos.d/$name" \
                    "/etc/pacman.d/$name" "$(real_home)/.$name" \
                    "$(real_home)/.config/pip/$name"; do
            if [[ -e "$cand" ]]; then target="$cand"; break; fi
        done
    fi

    if [[ -z "$target" ]]; then
        err "Could not infer the original location for '$(basename "$p")'."
        err "Please restore it manually from: $p"
        return 1
    fi
    if [[ ! -d "$(dirname "$target")" ]]; then
        err "Target directory does not exist: $(dirname "$target")"
        return 1
    fi

    if [[ "$target" == /etc/* || "$target" == /var/* ]]; then
        if ! ensure_sudo; then
            err "Restoring to $target needs root. Re-run:  sudo ayneh --restore \"$p\""
            return 1
        fi
        maybe_sudo cp -a "$p" "$target" || { err "Restore failed."; return 1; }
    else
        cp -a "$p" "$target" || { err "Restore failed."; return 1; }
    fi
    ok "Restored $target from $p"
}
