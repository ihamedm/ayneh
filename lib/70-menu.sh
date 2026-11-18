# shellcheck shell=bash
# =============================================================================
# INTERACTIVE MENU — list mirrors for a service, test each, let the user pick.
# =============================================================================
menu_pick_mirror() {
    require_curl
    local svc="$1"
    hdr "Iranian mirrors — $(service_label "$svc")"
    local kind; kind="$(service_kind "$svc")"
    local entries=() names=() urls=() line name url i=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        name="${line%%|*}"; url="${line#*|}"
        entries+=("$line"); names+=("$name"); urls+=("$url")
    done < <(get_mirrors "$svc")
    if [[ "${#entries[@]}" -eq 0 ]]; then warn "No mirrors registered for '$svc'."; return 1; fi

    # Probe all mirrors in PARALLEL. Down mirrors can take up to AYNEH_MAX_TIME
    # each, so sequential probing of 15-20 mirrors would be painfully slow;
    # running them concurrently caps total time at roughly the slowest probe.
    ensure_tmpdir
    info "Testing ${#entries[@]} mirrors in parallel (this takes ~${AYNEH_MAX_TIME}s)..."
    local results="$AYNEH_TMPDIR/picker.$$"
    : > "$results"
    for ((i=0; i<${#entries[@]}; i++)); do
        (
            if mirror_reachable "$kind" "${urls[$i]}" "$svc"; then
                printf '%s|1\n' "$i" >> "$results"
            else
                printf '%s|0\n' "$i" >> "$results"
            fi
        ) &
    done
    wait

    # Collect statuses (default "0" for any that failed to write).
    local -a statuses=()
    for ((i=0; i<${#entries[@]}; i++)); do statuses[i]="0"; done
    local idx st
    while IFS='|' read -r idx st; do
        [[ -z "$idx" ]] && continue
        statuses[idx]="$st"
    done < "$results"
    rm -f "$results"

    # Render the table.
    printf '  %s%-3s %-22s %-10s %s%s\n' "$C_BOLD" "#" "MIRROR" "STATUS" "URL" "$C_OFF"
    printf '  %s\n' "------------------------------------------------------------"
    local color
    for ((i=0; i<${#entries[@]}; i++)); do
        if [[ "${statuses[$i]}" == "1" ]]; then st="OK"; color="$C_GREEN"
        else st="down"; color="$C_RED"; fi
        printf '  %s%-3s%s %-22s %s%-8s%s %s\n' \
            "$C_BOLD" "$((i+1))" "$C_OFF" "${names[$i]}" "$color" "$st" "$C_OFF" "${urls[$i]}"
    done
    echo
    info "Type a number to apply that mirror, or 0 to go back."
    local choice
    ask choice "Apply mirror #> " || { echo; return 0; }
    [[ "$choice" == "0" || -z "$choice" ]] && return 0
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#entries[@]} )); then
        err "Invalid choice."; return 1
    fi
    idx=$((choice-1))
    if [[ "${statuses[$idx]}" != "1" ]]; then
        warn "That mirror was unreachable in the test. Apply anyway?"
        confirm "  proceed" n || return 1
    fi
    apply_mirror "$svc" "${names[$idx]}" "${urls[$idx]}"
}

# Top-level services menu
menu_services() {
    while true; do
        hdr "Choose a service"
        cat <<EOF
  ${C_BOLD}1)${C_OFF} npm registry         $(has_npm && echo "${C_GREEN}available${C_OFF}" || echo "${C_DIM}not installed${C_OFF}")
  ${C_BOLD}2)${C_OFF} Python PyPI / pip    $(has_pip && echo "${C_GREEN}available${C_OFF}" || echo "${C_DIM}not installed${C_OFF}")
  ${C_BOLD}3)${C_OFF} Docker registry      $(has_docker && echo "${C_GREEN}available${C_OFF}" || echo "${C_DIM}not installed${C_OFF}")
  ${C_BOLD}4)${C_OFF} apt — Ubuntu         $([ "$DISTRO_ID" == ubuntu ] && echo "${C_GREEN}$DISTRO_CODENAME${C_OFF}" || echo "${C_DIM}n/a${C_OFF}")
  ${C_BOLD}5)${C_OFF} apt — Debian         $([ "$DISTRO_FAMILY" == debian ] && [ "$DISTRO_ID" != ubuntu ] && echo "${C_GREEN}$DISTRO_CODENAME${C_OFF}" || echo "${C_DIM}n/a${C_OFF}")
  ${C_BOLD}6)${C_OFF} dnf/yum — CentOS/Rocky/Alma/Fedora
  ${C_BOLD}7)${C_OFF} dnf/yum — EPEL
  ${C_BOLD}8)${C_OFF} pacman — Arch
  ${C_BOLD}9)${C_OFF} apk — Alpine
  ${C_BOLD}0)${C_OFF} back
EOF
        local c
        ask c "> " || { echo; return 0; }
        case "$c" in
            1) menu_pick_mirror npm ;;
            2) menu_pick_mirror pypi ;;
            3) menu_pick_mirror docker ;;
            4) menu_pick_mirror ubuntu ;;
            5) menu_pick_mirror debian ;;
            6) menu_pick_mirror "$(rhel_service_for_distro)" ;;
            7) menu_pick_mirror epel ;;
            8) menu_pick_mirror pacman ;;
            9) menu_pick_mirror apk ;;
            0|"") return 0 ;;
            *) warn "Invalid choice." ;;
        esac
    done
}

# Test an arbitrary mirror URL
menu_test_mirror() {
    require_curl
    hdr "Test any mirror URL"
    local u
    ask u "URL> " || { echo; return 0; }
    [[ -z "$u" ]] && return 0
    local code; code="$(http_code "$u")"
    local status color
    if [[ "$code" == "200" ]]; then status="OK"; color="$C_GREEN"
    elif [[ "$code" == "000" ]]; then status="UNREACHABLE"; color="$C_RED"
    else status="HTTP $code"; color="$C_YELLOW"; fi
    printf '  %s%s%s  %s\n' "$color" "$status" "$C_OFF" "$u"
}

menu_list_mirrors() {
    hdr "All registered Iranian mirrors"
    local s
    for s in "${AYNEH_SERVICES[@]}"; do
        printf '\n%s%s%s\n' "$C_BOLD" "$(service_label "$s")" "$C_OFF"
        get_mirrors "$s" | awk -F'|' '{printf "  %-22s %s\n", $1, $2}'
    done
}

menu_restore() {
    list_backups || { pause; return 0; }
    hdr "Restore a backup"
    info "Enter the full path shown above (or blank to cancel)."
    local p
    ask p "path> " || { echo; return 0; }
    [[ -z "$p" ]] && return 0
    warn "This will overwrite the original location recorded for that backup."
    confirm "  restore" n || return 1
    restore_backup "$p"
}

banner() {
    printf '\n%s' "$C_BOLD$C_CYAN"
    cat <<'EOF'
    _
   / \  _   _ _ __   ___| |__
  / _ \| | | | '_ \ / _ \ '_ \
 / ___ \ |_| | | | |  __/ | | |
/_/   \_\__, |_| |_|\___|_| |_|
        |___/
EOF
    printf '%s\n' "$C_OFF"
    printf '%s\n' "${C_DIM}Iranian repository mirror scanner & configurator  v${AYNEH_VERSION}${C_OFF}"
    printf '%s\n' "${C_DIM}------------------------------------------------------------${C_OFF}"
    os_summary
    printf '%s\n' "${C_DIM}------------------------------------------------------------${C_OFF}"
}

menu_main() {
    while true; do
        cat <<EOF

  ${C_BOLD}1)${C_OFF} Scan all repositories now
  ${C_BOLD}2)${C_OFF} Scan a single service
  ${C_BOLD}3)${C_OFF} Apply / switch a mirror  ${C_YELLOW}(interactive)${C_OFF}
  ${C_BOLD}4)${C_OFF} Show current configuration
  ${C_BOLD}5)${C_OFF} List all known Iranian mirrors
  ${C_BOLD}6)${C_OFF} Test any mirror URL
  ${C_BOLD}7)${C_OFF} Restore from backup
  ${C_BOLD}0)${C_OFF} Exit

EOF
        local c
        ask c "${C_BOLD}ayneh>${C_OFF} " || { echo "Bye."; return 0; }
        case "$c" in
            1) scan_all; pause ;;
            2)
                hdr "Scan a single service"
                cat <<EOF
  1) npm   2) PyPI   3) Docker   4) apt   5) yum/dnf   6) pacman   7) apk   0) back
EOF
                local s; ask s "> "
                case "$s" in
                    1) scan_service npm ;;
                    2) scan_service pypi ;;
                    3) scan_service docker ;;
                    4) scan_service apt ;;
                    5) scan_service yum ;;
                    6) scan_service pacman ;;
                    7) scan_service apk ;;
                    0|"") ;;
                    *) warn "Invalid." ;;
                esac
                pause ;;
            3) menu_services; pause ;;
            4) show_config; pause ;;
            5) menu_list_mirrors; pause ;;
            6) menu_test_mirror; pause ;;
            7) menu_restore; pause ;;
            0|q|exit) echo "Bye."; return 0 ;;
            "") ;;
            *) warn "Invalid choice." ;;
        esac
    done
}
