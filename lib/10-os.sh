# shellcheck shell=bash
# =============================================================================
# OS / package-manager detection and service detectors
# =============================================================================
DISTRO_ID="unknown"; DISTRO_FAMILY="unknown"; DISTRO_CODENAME=""
DISTRO_VERSION=""; DISTRO_ARCH=""; PKGMGR="none"

detect_os() {
    DISTRO_ARCH="$(uname -m 2>/dev/null || echo x86_64)"
    [[ -z "$DISTRO_ARCH" ]] && DISTRO_ARCH="x86_64"

    local osr=""
    [[ -f /etc/os-release ]] && osr=/etc/os-release
    [[ -z "$osr" && -f /usr/lib/os-release ]] && osr=/usr/lib/os-release

    if [[ -n "$osr" ]]; then
        # shellcheck disable=SC1090
        . "$osr" 2>/dev/null || true
        DISTRO_ID="${ID:-unknown}"
        DISTRO_ID="${DISTRO_ID,,}"                # lowercase
        DISTRO_VERSION="${VERSION_ID:-}"
        DISTRO_CODENAME="${VERSION_CODENAME:-}"
        # ID_LIKE gives the family for derivatives (e.g. Ubuntu's ID_LIKE=debian)
        local like="${ID_LIKE:-}"
        like="${like,,}"
        case "$DISTRO_ID|$like" in
            *debian*|*ubuntu*|*linuxmint*|*kali*|*raspbian*|*mx*|*devuan*) DISTRO_FAMILY="debian" ;;
            *rhel*|*fedora*|*centos*|*rocky*|*almalinux*|*oraclelinux*|*amazon*|*amzn*|*scientific*|*clearos*|*kylin*|*anolis*|*eurolinux*) DISTRO_FAMILY="rhel" ;;
            *arch*|*manjaro*|*garuda*|*endeavouros*|*cachyos*|*arcolinux*|*artix*) DISTRO_FAMILY="arch" ;;
            *alpine*) DISTRO_FAMILY="alpine" ;;
            *opensuse*|*suse*|*sles*|*tumbleweed*|*leap*) DISTRO_FAMILY="suse" ;;
            *void*) DISTRO_FAMILY="void" ;;
            *gentoo*) DISTRO_FAMILY="gentoo" ;;
            *nixos*) DISTRO_FAMILY="nixos" ;;
            *slackware*) DISTRO_FAMILY="slackware" ;;
            *) DISTRO_FAMILY="${DISTRO_ID}";;
        esac
    fi

    # Codename fallbacks for distros that don't set VERSION_CODENAME
    if [[ -z "$DISTRO_CODENAME" ]]; then
        case "$DISTRO_FAMILY" in
            debian)
                if have lsb_release; then DISTRO_CODENAME="$(lsb_release -cs 2>/dev/null)"
                elif [[ -f /etc/debian_version ]]; then DISTRO_CODENAME="$(cut -d/ -f1 /etc/debian_version 2>/dev/null)"
                fi ;;
            arch) DISTRO_CODENAME="rolling" ;;
            alpine) DISTRO_CODENAME="$(alpine_branch)" ;;
        esac
    fi

    # Detect available package manager(s)
    PKGMGR="none"
    if have apt-get || have apt;        then PKGMGR="apt"
    elif have dnf;                      then PKGMGR="dnf"
    elif have yum;                      then PKGMGR="yum"
    elif have pacman;                   then PKGMGR="pacman"
    elif have apk;                      then PKGMGR="apk"
    elif have zypper;                   then PKGMGR="zypper"
    elif have xbps-install;             then PKGMGR="xbps"
    elif have emerge;                   then PKGMGR="portage"
    fi
}

os_summary() {
    printf '%s: %s %s (%s)\n' "OS" "${DISTRO_ID}" "${DISTRO_VERSION}" "${DISTRO_ARCH}"
    printf '%s: %s\n' "Family" "$DISTRO_FAMILY"
    printf '%s: %s\n' "Codename" "${DISTRO_CODENAME:-n/a}"
    printf '%s: %s\n' "Package manager" "$PKGMGR"
}

# Alpine release branch ("v3.20") from VERSION_ID ("3.20.3"). "edge" when the
# version is unknown (edge images, custom builds).
alpine_branch() {
    local v="${DISTRO_VERSION:-}"
    if [[ -z "$v" || "$v" == "edge" ]]; then
        printf '%s\n' "edge"
        return 0
    fi
    printf 'v%s\n' "$(printf '%s' "$v" | awk -F. '{print $1"."$2}')"
}

# -----------------------------------------------------------------------------
# Service detectors (is the toolchain present?)
# -----------------------------------------------------------------------------
has_npm()    { have npm; }
has_pip()    { have pip || have pip3; }
has_docker() { have docker || [[ -d /etc/docker ]]; }
has_apt()    { [[ "$DISTRO_FAMILY" == "debian" ]] && (have apt-get || have apt); }
has_yum()    { [[ "$DISTRO_FAMILY" == "rhel"  ]] && (have dnf || have yum); }
has_pacman() { [[ "$DISTRO_FAMILY" == "arch"  ]] && have pacman; }
has_apk()    { [[ "$DISTRO_FAMILY" == "alpine" ]] && have apk; }

pip_cmd() { have pip3 && echo pip3 || echo pip; }
