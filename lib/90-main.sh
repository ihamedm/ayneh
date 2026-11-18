# shellcheck shell=bash
# =============================================================================
# CLI (non-interactive) interface and program entry point
# =============================================================================
usage() {
    cat <<EOF
${C_BOLD}ayneh${C_OFF} v${AYNEH_VERSION} — Iranian repository mirror scanner & configurator

${C_BOLD}Usage:${C_OFF}
  ayneh                        Interactive menu
  ayneh --scan [service]       Scan all repositories (or one service) and report
  ayneh --show                 Show current configuration
  ayneh --list [service]       List mirrors (all, or one service)
  ayneh --test <url>           Test reachability of any URL
  ayneh --apply <svc> <name>   Apply a mirror by service + name
                               (e.g. --apply npm Liara)
  ayneh --apply <svc> --url <u>  Apply a mirror by raw URL
  ayneh --restore [path]       List backups, or restore one
  ayneh --version              Print version
  ayneh --help                 This help

${C_BOLD}Services:${C_OFF} npm, pypi, docker, ubuntu, debian, centos, rocky,
            almalinux, fedora, epel, pacman, apk
            (aliases: apt = ubuntu/debian, yum = rhel flavor, alma = almalinux)

${C_BOLD}One-line run (no install):${C_OFF}
  curl -fsSL https://raw.githubusercontent.com/${AYNEH_REPO}/${AYNEH_BRANCH}/dist/ayneh.sh | bash
  curl -fsSL https://raw.githubusercontent.com/${AYNEH_REPO}/${AYNEH_BRANCH}/dist/ayneh.sh | bash -s -- --scan

${C_BOLD}Install as a command:${C_OFF}
  curl -fsSL https://raw.githubusercontent.com/${AYNEH_REPO}/${AYNEH_BRANCH}/install.sh | sudo bash
  ayneh

${C_BOLD}Environment:${C_OFF}
  NO_COLOR=1              Disable colors
  AYNEH_CONNECT_TIMEOUT   curl connect timeout in seconds (default ${AYNEH_CONNECT_TIMEOUT})
  AYNEH_MAX_TIME          curl total timeout in seconds (default ${AYNEH_MAX_TIME})
EOF
}

# Print the URL for a mirror name, or fail.
# Resolve a known service + custom URL / name into MIRROR_NAME/MIRROR_URL.
_parse_apply_target() {
    local svc="$1"; shift
    local name="${1:-}" url=""
    if [[ "$name" == "--url" || "$name" == "-u" ]]; then
        shift
        url="${1:-}"
        name="custom"
    elif [[ -n "$name" ]]; then
        url="$(resolve_mirror "$svc" "$name" || true)"
    fi
    if [[ -z "$url" ]]; then
        err "Mirror not found for service '$svc'."
        err "Use: ayneh --apply <service> <name>   or   ayneh --apply <service> --url <url>"
        err "Known names for '$svc':"
        get_mirrors "$svc" 2>/dev/null | awk -F'|' '{printf "    %-22s %s\n",$1,$2}' >&2
        return 1
    fi
    if [[ ! "$url" =~ ^https?:// ]]; then
        err "Not an http(s) URL: $url"
        return 1
    fi
    printf '%s\n%s\n' "$name" "$url"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)    usage; exit 0 ;;
            -v|--version) printf '%s v%s\n' "$PROG" "$AYNEH_VERSION"; exit 0 ;;
            --scan|-s)
                shift
                local scan_svc=""
                if [[ $# -gt 0 && "$1" != -* ]]; then
                    if ! is_service "$1"; then
                        err "Unknown service: $1"
                        err "Valid services: ${AYNEH_SERVICES[*]}"
                        exit 1
                    fi
                    scan_svc="$1"; shift
                fi
                if [[ -n "$scan_svc" ]]; then scan_service "$scan_svc"; else scan_all; fi
                exit 0 ;;
            --show)       show_config; exit 0 ;;
            --list|-l)
                shift
                if [[ $# -gt 0 && "$1" != -* ]]; then
                    if ! is_service "$1"; then
                        err "Unknown service: $1"
                        err "Valid services: ${AYNEH_SERVICES[*]}"
                        exit 1
                    fi
                    get_mirrors "$(resolve_service_key "$1")" | awk -F'|' '{printf "%-22s %s\n",$1,$2}'
                    shift
                else
                    menu_list_mirrors
                fi
                exit 0 ;;
            --test|-t)
                shift
                if [[ -z "${1:-}" ]]; then err "URL required. See --help."; exit 1; fi
                code="$(http_code "$1")"
                printf '%s  %s\n' "$code" "$1"
                exit 0 ;;
            --apply|-a)
                shift
                local svc="${1:-}"
                if [[ -z "$svc" ]]; then err "Service required. See --help."; exit 1; fi
                if ! is_service "$svc"; then err "Unknown service: $svc"; exit 1; fi
                svc="$(resolve_service_key "$svc")"
                shift
                local parsed name url
                if ! parsed="$(_parse_apply_target "$svc" "$@")"; then exit 1; fi
                name="$(printf '%s\n' "$parsed" | sed -n '1p')"
                url="$(printf '%s\n' "$parsed" | sed -n '2p')"
                apply_mirror "$svc" "$name" "$url"
                exit $? ;;
            --restore)
                shift
                if [[ -n "${1:-}" ]]; then
                    restore_backup "$1"; exit $?
                else
                    list_backups || true
                    echo
                    info "To restore one: ayneh --restore <path>   (or use the menu)"
                    exit 0
                fi ;;
            --interactive) return 0 ;;
            *) err "Unknown option: $1"; usage; exit 1 ;;
        esac
    done
}

main() {
    detect_os
    if [[ $# -gt 0 ]]; then
        parse_args "$@"
    fi
    require_curl
    ensure_tmpdir
    banner
    menu_main
}
