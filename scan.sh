#!/usr/bin/env bash
# =============================================================================
#  mirrors — Iranian repository mirror scanner & configurator
# -----------------------------------------------------------------------------
#  Scans npm / PyPI / Docker / Linux package repos (apt, dnf/yum, pacman, apk)
#  for HTTP reachability, and when an upstream is unreachable lets you switch
#  to an Iranian mirror (ArvanCloud, Liara, and more) from a terminal menu.
#
#  Works under:  bash scan.sh
#                curl -fsSL https://raw.githubusercontent.com/ihamedm/mirrors/main/scan.sh | bash
#
#  License: MIT
# =============================================================================

set -uo pipefail

# We use bash 4 features (${var,,} lowercasing, `local -A` associative
# arrays). Every mainstream Linux ships bash >= 4; give a clear message
# instead of a cryptic parse error on an ancient bash.
if (( BASH_VERSINFO[0] < 4 )); then
    echo "mirrors: requires bash 4 or newer (you have ${BASH_VERSION})." >&2
    exit 1
fi

MIRRORS_VERSION="1.0.0"
PROG="mirrors"

# Where backups are stored. User-scope backups under HOME, system-scope under /var/backups.
USER_BACKUP_DIR="${HOME}/.mirrors-backup"
SYS_BACKUP_DIR="/var/backups/mirrors"

# -----------------------------------------------------------------------------
# Terminal colors (auto-disabled when not a tty, when NO_COLOR is set, or on a
# dumb terminal). Checked once.
# -----------------------------------------------------------------------------
if [[ -t 1 && "${TERM:-}" != "dumb" && -z "${NO_COLOR:-}" ]]; then
    C_RED=$'\033[31m';    C_GREEN=$'\033[32m';  C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m';   C_MAGENTA=$'\033[35m'; C_CYAN=$'\033[36m'
    C_BOLD=$'\033[1m';    C_DIM=$'\033[2m';      C_OFF=$'\033[0m'
else
    C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_MAGENTA=""; C_CYAN=""
    C_BOLD=""; C_DIM=""; C_OFF=""
fi

# -----------------------------------------------------------------------------
# Logging helpers
# -----------------------------------------------------------------------------
info()  { printf '%s\n' "${C_CYAN}[i]${C_OFF} $*"; }
ok()    { printf '%s\n' "${C_GREEN}[+]${C_OFF} $*"; }
warn()  { printf '%s\n' "${C_YELLOW}[!]${C_OFF} $*"; }
err()   { printf '%s\n' "${C_RED}[x]${C_OFF} $*" >&2; }
die()   { err "$*"; exit 1; }
hdr()   { printf '\n%s\n' "${C_BOLD}${C_BLUE}=== $* ===${C_OFF}"; }

# Read one line from the controlling terminal. This is what makes the menu
# work even when the script was piped in via `curl ... | bash` (where stdin
# is the script body, not the keyboard).
ask() {
    local _var="$1"; shift
    printf '%s' "$*"
    local _rc
    if [[ -r /dev/tty ]]; then
        IFS= read -r "$_var" </dev/tty 2>/dev/null; _rc=$?
    else
        IFS= read -r "$_var" 2>/dev/null; _rc=$?
    fi
    # EOF (read returns non-zero): default to empty so callers never see an
    # unset value under `set -u`, and propagate the non-zero status so menu
    # loops can break instead of spinning forever on a closed stdin.
    [[ $_rc -ne 0 ]] && eval "$_var=''"
    return $_rc
}

confirm() {
    local prompt="$1" default="${2:-y}" yn
    if [[ "$default" =~ ^[Yy] ]]; then
        ask yn "${prompt} [Y/n] "
    else
        ask yn "${prompt} [y/N] "
    fi
    yn="${yn:-$default}"
    [[ "$yn" =~ ^[Yy] ]]
}

pause() {
    local _d
    ask _d "${C_DIM}— press Enter to continue —${C_OFF}"
}

running_as_root() { [[ "${EUID:-$(id -u)}" -eq 0 ]]; }

# Run a command with sudo if we are not root, otherwise directly.
# Uses non-interactive sudo only (cached creds / NOPASSWD) so it never hangs
# or spews password errors in non-tty contexts. Callers that MUST have root
# should check can_sudo() first and give a clear message.
maybe_sudo() {
    if running_as_root; then "$@"; return $?; fi
    sudo -n "$@" 2>/dev/null; return $?
}

# True if we are root OR can sudo non-interactively (cached/NOPASSWD).
can_sudo() {
    running_as_root && return 0
    sudo -n true 2>/dev/null
}

# Guard for system-scope applies: fail fast with a clear message instead of
# leaking sudo password errors mid-operation.
require_root() {
    local svc="$1" name="$2"
    if can_sudo; then return 0; fi
    err "This modifies system files and requires root (or passwordless sudo)."
    err "Re-run as:  sudo bash scan.sh --apply ${svc} \"${name}\""
    return 1
}

# Real invoking user's HOME (when running under sudo).
real_home() {
    if [[ -n "${SUDO_USER:-}" ]]; then
        getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6 || echo "$HOME"
    else
        echo "$HOME"
    fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# =============================================================================
# OS / package-manager detection  (supports all common Linux distros)
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
            *rhel*|*fedora*|*centos*|*rocky*|*almalinux*|*alma*|*ol*|*oraclelinux*|*amazon*|*amzn*|*scientific*|*clearos*|*kylin*|*anolis*|*eurolinux*) DISTRO_FAMILY="rhel" ;;
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
            alpine) DISTRO_CODENAME="v${DISTRO_VERSION}" ;;
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

# =============================================================================
# HTTP probe helpers
# =============================================================================
# Print HTTP status code for a URL ("000" on failure). Fast and reliable.
# --max-filesize aborts the body download the instant it starts (we only need
# the status line), so probes stay quick even for multi-MB responses. We do NOT
# add a "|| echo 000" fallback: %{http_code} already prints "000" when curl
# never reached the server, and appending "000" after a real code on curl's
# non-zero exit (63=max-filesize, 28=timeout) would corrupt the value.
http_code() {
    local url="$1"
    curl -s -o /dev/null -w '%{http_code}' \
         --max-filesize 512 --connect-timeout 6 --max-time 12 -L "$url" 2>/dev/null
}

# Probe a URL and print a human-readable status line.
# $1=label  $2=url  $3=comma-separated "good" codes (default 200)  $4=probe type
# probe type is informational only (used to hint why a non-200 may still be OK).
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
}

# Test whether a mirror actually serves packages (not just a landing page).
# Returns 0 (reachable & serving) or 1, and prints the code.
mirror_reachable() {
    local kind="$1" url="$2" code
    local test_url="$url"
    case "$kind" in
        npm)    test_url="${url%/}/npm" ;;                         # known package
        pypi)   test_url="${url%/}/pip/" ;;                        # url already ends with /simple
        docker) test_url="${url%/}/v2/" ;;                         # 401 is OK
        apt)    test_url="${url%/}/dists/${DISTRO_CODENAME}/Release" ;;
        pacman) test_url="${url%/}/core/os/${DISTRO_ARCH}/" ;;
        apk)    test_url="${url%/}/${DISTRO_ARCH}/APKINDEX.tar.gz" ;;
        *)      test_url="$url" ;;
    esac
    code="$(http_code "$test_url")"
    # Docker registry answers 401 on /v2/ — that means it is alive.
    if [[ "$kind" == "docker" ]]; then
        [[ "$code" == "200" || "$code" == "401" ]]
    else
        [[ "$code" == "200" || "$code" == "301" || "$code" == "302" ]]
    fi
}

# =============================================================================
# MIRROR REGISTRY
# -----------------------------------------------------------------------------
# This is the single place to add mirrors (phase 2). Each entry is "Name|URL".
# For APT mirrors the URL MUST include the distro path (e.g. .../ubuntu).
# For pacman mirrors the URL is the repo root ($repo/os/$arch is appended).
# For apk mirrors the URL is the alpine root ($ver/$repo/$arch appended).
# The script always tests a mirror live before applying it, so unreachable or
# wrong-path mirrors simply show up as "unreachable" and are never applied.
# =============================================================================

# --- npm (Node package registry) ---
NPM_MIRRORS=(
    "Liara|https://package-mirror.liara.ir/repository/npm/"
    "Pardisco|https://mirrors.pardisco.co/npm/"
    "AtlantisCloud|https://mirror.atlantiscloud.ir/npm/"
    "Chabokan|https://iran.chabokan.net/npm/"
    "Kargadan|https://mirror.kargadan.ir/npm/"
    "Parmin|https://parmin.cloud/npm/"
    "Runflare|https://runflare.com/mirrors/npm/"
)

# --- PyPI (Python package index) ---
PYPI_MIRRORS=(
    "Liara|https://package-mirror.liara.ir/repository/pypi/simple"
    "Pardisco|https://mirrors.pardisco.co/pypi/simple"
    "Chabokan|https://iran.chabokan.net/pypi/simple"
    "Kargadan|https://mirror.kargadan.ir/pypi/simple"
    "Hyperclouds|https://mirrors.hyperclouds.ir/pypi/simple"
    "Parmin|https://parmin.cloud/pypi/simple"
    "Runflare|https://runflare.com/mirrors/pypi/simple"
)

# --- Docker registry mirror (host only; /v2/ is probed) ---
DOCKER_MIRRORS=(
    "ArvanCloud|https://docker.arvancloud.ir"
    "Liara|https://docker-mirror.liara.ir"
    "MobinHost|https://docker.mobinhost.com"
    "HamDocker|https://hub.hamdocker.ir"
    "ParsPack|https://registry.docker.ir"
    "Kernel.ir|https://docker.kernel.ir"
    "IranServer|https://docker.iranserver.com"
    "IranRepo|https://docker.iranrepo.ir"
    "Runflare|https://mirror-docker.runflare.com"
    "Focker|https://focker.ir"
    "AtlantisCloud|https://mirror.atlantiscloud.ir"
    "Chabokan|https://iran.chabokan.net"
    "Kargadan|https://mirror.kargadan.ir"
    "Parmin|https://parmin.cloud"
    "Megan Hub|https://megan.ir"
)

# --- apt: Ubuntu mirrors (URL ends with /ubuntu) ---
APT_UBUNTU_MIRRORS=(
    "ArvanCloud|https://mirror.arvancloud.ir/ubuntu"
    "Ubuntu IR (official)|https://ir.archive.ubuntu.com/ubuntu"
    "MobinHost|https://mirror.mobinhost.com/ubuntu"
    "Isfahan UT|https://repo.iut.ac.ir/ubuntu"
    "IranServer|https://mirror.iranserver.com/ubuntu"
    "Shatel|https://mirror.shatel.ir/ubuntu"
    "Afranet|https://mirror.afranet.com/ubuntu"
    "Pishgaman|https://ubuntu.pishgaman.net/ubuntu"
    "KimiaHost|https://ubuntu-mirror.kimiahost.com/ubuntu"
    "DigitalVPS|https://mirror.digitalvps.ir/ubuntu"
    "Sindad|https://ir.ubuntu.sindad.cloud/ubuntu"
    "Pars.host|https://ubuntu.pars.host/ubuntu"
    "Dimit Cloud|https://mirrors.ubuntu.dimit.cloud/ubuntu"
    "Petiak|https://archive.ubuntu.petiak.ir/ubuntu"
    "0-1.cloud|https://mirror.0-1.cloud/ubuntu"
    "ParsDev|https://mirror.parsdev.com/ubuntu"
    "Abrha|https://repo.abrha.net/ubuntu"
    "LinuxMirrors|https://linuxmirrors.ir/ubuntu"
    "Famaserver|https://mirror.famaserver.com/ubuntu"
    "Freedif|https://mirror.freedif.org/ubuntu"
)

# --- apt: Debian mirrors (URL ends with /debian) ---
APT_DEBIAN_MIRRORS=(
    "ArvanCloud|https://mirror.arvancloud.ir/debian"
    "MobinHost|https://mirror.mobinhost.com/debian"
    "Isfahan UT|https://repo.iut.ac.ir/debian"
    "IranServer|https://mirror.iranserver.com/debian"
    "Shatel|https://mirror.shatel.ir/debian"
    "Afranet|https://mirror.afranet.com/debian"
    "0-1.cloud|https://mirror.0-1.cloud/debian"
    "ParsDev|https://mirror.parsdev.com/debian"
    "Abrha|https://repo.abrha.net/debian"
    "LinuxMirrors|https://linuxmirrors.ir/debian"
    "Petiak|https://archive.debian.petiak.ir/debian"
    "Famaserver|https://mirror.famaserver.com/debian"
    "Freedif|https://mirror.freedif.org/debian"
)

# --- dnf/yum: RHEL family mirrors. URL is the distro root on the mirror. ---
# Used as a host-swap target for baseurls in /etc/yum.repos.d/*.repo
YUM_CENTOS_MIRRORS=(
    "Sindad|https://ir.centos.sindad.cloud"
    "IranServer|https://mirror.iranserver.com/centos"
    "MobinHost|https://mirror.mobinhost.com/centos"
    "ArvanCloud|https://mirror.arvancloud.ir/centos"
    "Afranet|https://mirror.afranet.com/centos"
    "Faraso|https://mirror.faraso.org/centos"
)
YUM_ROCKY_MIRRORS=(
    "ArvanCloud|https://mirror.arvancloud.ir/rocky"
    "MobinHost|https://mirror.mobinhost.com/rocky"
    "0-1.cloud|https://mirror.0-1.cloud/rocky"
)
YUM_ALMA_MIRRORS=(
    "MobinHost|https://mirror.mobinhost.com/almalinux"
    "0-1.cloud|https://mirror.0-1.cloud/almalinux"
    "Abrha|https://repo.abrha.net/almalinux"
    "ParsDev|https://mirror.parsdev.com/almalinux"
    "Famaserver|https://mirror.famaserver.com/almalinux"
)
YUM_FEDORA_MIRRORS=(
    "0-1.cloud|https://mirror.0-1.cloud/fedora"
    "Isfahan UT|https://repo.iut.ac.ir/fedora"
    "Freedif|https://mirror.freedif.org/fedora"
)
YUM_EPEL_MIRRORS=(
    "Sindad|https://ir.epel.sindad.cloud"
    "MobinHost|https://mirror.mobinhost.com/epel"
    "0-1.cloud|https://mirror.0-1.cloud/epel"
    "Faraso|https://mirror.faraso.org/epel"
    "Rasanegar|https://mirror.rasanegaar.com/epel"
    "Abrha|https://repo.abrha.net/epel"
)

# --- pacman: Arch / Arch-derivatives. Server root ($repo/os/$arch appended) ---
PACMAN_MIRRORS=(
    "ArvanCloud|https://mirror.arvancloud.ir/arch"
    "Isfahan UT|https://repo.iut.ac.ir/arch"
    "0-1.cloud|https://mirror.0-1.cloud/archlinux"
    "Freedif|https://mirror.freedif.org/archlinux"
    "MobinHost|https://mirror.mobinhost.com/archlinux"
)

# --- apk: Alpine. Root ($ver/$repo/$arch appended) ---
APK_MIRRORS=(
    "0-1.cloud|https://mirror.0-1.cloud/alpine"
    "Freedif|https://mirror.freedif.org/alpine"
    "Isfahan UT|https://repo.iut.ac.ir/alpine"
    "Pardisco|https://mirrors.pardisco.co/alpine"
    "MobinHost|https://mirror.mobinhost.com/alpine"
    "ArvanCloud|https://mirror.arvancloud.ir/alpine"
)

# Registry accessor: print "Name|URL" lines for a service key.
get_mirrors() {
    case "$1" in
        npm)          printf '%s\n' "${NPM_MIRRORS[@]}" ;;
        pypi)         printf '%s\n' "${PYPI_MIRRORS[@]}" ;;
        docker)       printf '%s\n' "${DOCKER_MIRRORS[@]}" ;;
        ubuntu)       printf '%s\n' "${APT_UBUNTU_MIRRORS[@]}" ;;
        debian)       printf '%s\n' "${APT_DEBIAN_MIRRORS[@]}" ;;
        centos)       printf '%s\n' "${YUM_CENTOS_MIRRORS[@]}" ;;
        rocky)        printf '%s\n' "${YUM_ROCKY_MIRRORS[@]}" ;;
        almalinux|alma) printf '%s\n' "${YUM_ALMA_MIRRORS[@]}" ;;
        fedora)       printf '%s\n' "${YUM_FEDORA_MIRRORS[@]}" ;;
        epel)         printf '%s\n' "${YUM_EPEL_MIRRORS[@]}" ;;
        pacman)       printf '%s\n' "${PACMAN_MIRRORS[@]}" ;;
        apk)          printf '%s\n' "${APK_MIRRORS[@]}" ;;
        *) return 1 ;;
    esac
}

# Map a service key to a human label and a "kind" (for reachability probing).
service_label() {
    case "$1" in
        npm)    echo "npm registry" ;;
        pypi)   echo "Python PyPI / pip" ;;
        docker) echo "Docker registry" ;;
        ubuntu) echo "apt — Ubuntu" ;;
        debian) echo "apt — Debian" ;;
        centos) echo "dnf/yum — CentOS" ;;
        rocky)  echo "dnf/yum — Rocky Linux" ;;
        almalinux|alma) echo "dnf/yum — AlmaLinux" ;;
        fedora) echo "dnf/yum — Fedora" ;;
        epel)   echo "dnf/yum — EPEL" ;;
        pacman) echo "pacman — Arch" ;;
        apk)    echo "apk — Alpine" ;;
        *) echo "$1" ;;
    esac
}
service_kind() {
    case "$1" in
        ubuntu|debian) echo "apt" ;;
        centos|rocky|almalinux|alma|fedora|epel) echo "yum" ;;
        *) echo "$1" ;;
    esac
}

# =============================================================================
# Service detectors (is the toolchain present?)
# =============================================================================
has_npm()    { have npm; }
has_pip()    { have pip || have pip3; }
has_docker() { have docker || [[ -d /etc/docker ]]; }
has_apt()    { [[ "$DISTRO_FAMILY" == "debian" ]] && (have apt-get || have apt); }
has_yum()    { [[ "$DISTRO_FAMILY" == "rhel"  ]] && (have dnf || have yum); }
has_pacman() { [[ "$DISTRO_FAMILY" == "arch"  ]] && have pacman; }
has_apk()    { [[ "$DISTRO_FAMILY" == "alpine" ]] && have apk; }

pip_cmd() { have pip3 && echo pip3 || echo pip; }

# =============================================================================
# UPSTREAM SCANNERS — test the default upstream for each service
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
    cur="$($(pip_cmd) config get global.index-url 2>/dev/null || true)"
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

# Return yum baseurls / metalinks (expanded) for scanning.
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
    local count=0 line kind repoid url
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
    local first="" line
    first="$(awk '/^[[:space:]]*Server[[:space:]]*=/{print $3; exit}' /etc/pacman.d/mirrorlist 2>/dev/null)"
    if [[ -z "$first" ]]; then
        warn "No Server entries in /etc/pacman.d/mirrorlist."
        return
    fi
    info "first mirror: $first"
    # Expand $repo/$arch to test with core repo.
    local test_url="${first//\$repo/core}"
    test_url="${test_url//\$arch/$DISTRO_ARCH}"
    probe_url "pacman mirror" "$test_url" 200
}

scan_apk() {
    hdr "apk repositories"
    if ! has_apk; then warn "apk not available — skipped."; return; fi
    local count=0 line url test
    while IFS= read -r line; do
        line="${line%%#*}"; [[ -z "$line" ]] && continue
        count=$((count+1))
        url="${line%/}"
        test="${url}/${DISTRO_ARCH}/APKINDEX.tar.gz"
        probe_url "apk repo #$count" "$test" 200
    done < /etc/apk/repositories 2>/dev/null
    [[ "$count" -eq 0 ]] && warn "No apk repositories configured."
}

scan_all() {
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
    ok "Scan complete. Anything marked ${C_RED}UNREACHABLE${C_OFF} or ${C_YELLOW}HTTP 4xx/5xx${C_OFF} needs a mirror."
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
        printf '  index-url: %s\n' "$( $(pip_cmd) config get global.index-url 2>/dev/null || echo 'default (https://pypi.org/simple)')"
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

# =============================================================================
# BACKUP / RESTORE
# =============================================================================
backup_file() {
    local src="$1" tag="${2:-manual}"
    [[ ! -e "$src" ]] && return 1
    local stamp dest_dir dest
    stamp="$(date +%Y%m%d-%H%M%S)"
    if [[ "$src" == /etc/* || "$src" == /var/* ]]; then
        dest_dir="$SYS_BACKUP_DIR"
        maybe_sudo mkdir -p "$dest_dir"
        local base="${src##*/}"
        dest="${dest_dir}/${base}.${tag}.${stamp}.bak"
        maybe_sudo cp -a "$src" "$dest"
    else
        dest_dir="$USER_BACKUP_DIR"; mkdir -p "$dest_dir"
        local base="${src##*/}"
        dest="${dest_dir}/${base}.${tag}.${stamp}.bak"
        cp -a "$src" "$dest"
    fi
    echo "$dest"
}

list_backups() {
    hdr "Available backups"
    local found=0
    for d in "$USER_BACKUP_DIR" "$SYS_BACKUP_DIR"; do
        [[ -d "$d" ]] || continue
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            printf '  %s\n' "$f"; found=$((found+1))
        done < <(ls -1 "$d"/*.bak 2>/dev/null)
    done
    [[ "$found" -eq 0 ]] && warn "No backups found yet."
}

# =============================================================================
# MIRROR APPLIERS
# Each: backs up, applies, verifies, reports. Returns 0 on success.
# =============================================================================

apply_npm() {
    local name="$1" url="$2"
    hdr "Applying npm mirror: $name"
    if ! mirror_reachable npm "$url"; then
        err "Mirror is not serving npm packages — aborting (try another)."
        return 1
    fi
    ok "Mirror reachable."
    if ! has_npm; then warn "npm not installed — writing ~/.npmrc directly."; fi
    local npmrc="$(real_home)/.npmrc"
    [[ -f "$npmrc" ]] && backup_file "$npmrc" npm >/dev/null && info "Backed up ~/.npmrc"
    if running_as_root && [[ -n "${SUDO_USER:-}" ]]; then
        sudo -u "$SUDO_USER" npm config set registry "$url" 2>/dev/null \
            || { printf 'registry=%s\n' "$url" >> "$npmrc"; }
    else
        npm config set registry "$url" 2>/dev/null || { printf 'registry=%s\n' "$url" >> "$npmrc"; }
    fi
    ok "npm registry set to: $url"
}

apply_pypi() {
    local name="$1" url="$2"
    hdr "Applying PyPI mirror: $name"
    if ! mirror_reachable pypi "$url"; then
        err "Mirror is not serving PyPI packages — aborting."
        return 1
    fi
    ok "Mirror reachable."
    local host="${url#https://}"; host="${host%%/*}"
    local conf_dir conf_file
    if running_as_root; then
        conf_file="/etc/pip.conf"
    else
        conf_dir="$(real_home)/.config/pip"; mkdir -p "$conf_dir"
        conf_file="$conf_dir/pip.conf"
    fi
    [[ -f "$conf_file" ]] && backup_file "$conf_file" pip >/dev/null && info "Backed up $conf_file"
    cat > "$tmpdir/pip.conf.new" <<EOF
[global]
index-url = $url
trusted-host = $host
EOF
    if running_as_root; then maybe_sudo install -m 0644 "$tmpdir/pip.conf.new" "$conf_file"
    else cp "$tmpdir/pip.conf.new" "$conf_file"; fi
    ok "pip index-url set to: $url"
}

apply_docker() {
    local name="$1" url="$2"
    hdr "Applying Docker registry mirror: $name"
    require_root docker "$name" || return 1
    if ! mirror_reachable docker "$url"; then
        err "Mirror is not responding as a Docker registry — aborting."
        return 1
    fi
    ok "Mirror reachable."
    local dj=/etc/docker/daemon.json
    maybe_sudo mkdir -p /etc/docker
    [[ -f "$dj" ]] && backup_file "$dj" docker >/dev/null && info "Backed up $dj"
    # Safe JSON merge via python3 (preferred) or a from-scratch build.
    local tmpjson="$tmpdir/daemon.json"
    if have python3; then
        python3 - "$dj" "$url" <<'PY'
import json, sys, os
path, mirror = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path):
    try:
        with open(path) as f: data = json.load(f)
    except Exception:
        data = {}
m = data.get("registry-mirrors", [])
if mirror not in m: m.insert(0, mirror)
# de-dup preserving order
seen=set(); out=[]
for x in m:
    if x not in seen: seen.add(x); out.append(x)
data["registry-mirrors"] = out
with open("/tmp/__mirrors_daemon.json","w") as f: json.dump(data, f, indent=2)
PY
        maybe_sudo install -m 0644 /tmp/__mirrors_daemon.json "$dj"
        rm -f /tmp/__mirrors_daemon.json
    else
        # No python: build a minimal daemon.json (will overwrite — backup already saved).
        printf '{\n  "registry-mirrors": ["%s"]\n}\n' "$url" | maybe_sudo tee "$dj" >/dev/null
    fi
    ok "registry-mirrors now:"
    maybe_sudo sed 's/^/    /' "$dj"
    warn "Restart the Docker daemon to apply:"
    printf '    %s\n' "sudo systemctl restart docker   # or: sudo service docker restart"
}

# Generic apt host-swap for Ubuntu/Debian. $1=service (ubuntu|debian) $2=mirror url
apply_apt() {
    local svc="$1" name="$2" url="$3"
    hdr "Applying apt mirror ($svc): $name"
    require_root "$svc" "$name" || return 1
    if ! mirror_reachable apt "$url"; then
        err "Mirror is not serving the $DISTRO_CODENAME release — aborting."
        return 1
    fi
    ok "Mirror reachable for $DISTRO_CODENAME."
    # Single host-swap regex per distro.
    #  - Ubuntu: any *ubuntu.com/ubuntu host/path → <mirror>
    #  - Debian: any *debian.org/debian host/path → <mirror>
    #    (this also rewrites /debian-security correctly, because the matched
    #     substring ".../debian" is replaced and the trailing "-security" stays)
    local sed_expr
    if [[ "$svc" == "ubuntu" ]]; then
        sed_expr="s|https?://[a-z0-9.-]*ubuntu\\.com/ubuntu|${url}|g"
    else
        sed_expr="s|https?://[a-z0-9.-]*debian\\.org/debian|${url}|g"
    fi

    local files=()
    [[ -f /etc/apt/sources.list ]] && files+=(/etc/apt/sources.list)
    for f in /etc/apt/sources.list.d/*.list; do [[ -e "$f" ]] && files+=("$f"); done
    local sf
    for sf in /etc/apt/sources.list.d/*.sources; do [[ -e "$sf" ]] && files+=("$sf"); done

    [[ "${#files[@]}" -eq 0 ]] && { warn "No apt sources files found to edit."; return 1; }

    local f tmpf changed=0
    for f in "${files[@]}"; do
        backup_file "$f" apt >/dev/null && info "Backed up $f"
        tmpf="$tmpdir/$(basename "$f")"
        maybe_sudo cat "$f" > "$tmpf" 2>/dev/null || cat "$f" > "$tmpf"
        sed -E -i "$sed_expr" "$tmpf"
        maybe_sudo install -m 0644 "$tmpf" "$f" 2>/dev/null || cp "$tmpf" "$f"
        changed=1
    done
    [[ "$changed" -eq 0 ]] && { warn "No apt sources files were modified."; return 1; }
    ok "apt sources rewritten to: $url"
    warn "Refresh indexes:"
    printf '    %s\n' "sudo apt update"
}

apply_pacman() {
    local name="$1" url="$2"
    hdr "Applying pacman mirror: $name"
    require_root pacman "$name" || return 1
    if ! mirror_reachable pacman "$url"; then
        err "Mirror is not serving Arch packages — aborting."
        return 1
    fi
    ok "Mirror reachable."
    local ml=/etc/pacman.d/mirrorlist
    [[ -f "$ml" ]] && backup_file "$ml" pacman >/dev/null && info "Backed up $ml"
    local tmpf="$tmpdir/mirrorlist"
    maybe_sudo cat "$ml" > "$tmpf" 2>/dev/null || cat "$ml" > "$tmpf"
    {
        printf '## Added by mirrors tool — %s — %s\n' "$name" "$(date)"
        printf 'Server = %s/$repo/os/$arch\n\n' "${url%/}"
        cat "$tmpf"
    } > "$tmpf.new"
    maybe_sudo install -m 0644 "$tmpf.new" "$ml" 2>/dev/null || cp "$tmpf.new" "$ml"
    ok "pacman mirror prepended: $url"
    warn "Refresh indexes:"
    printf '    %s\n' "sudo pacman -Syyu"
}

apply_apk() {
    local name="$1" url="$2"
    hdr "Applying apk mirror: $name"
    require_root apk "$name" || return 1
    # apk mirror root is <host>/alpine ; repositories file appends /<ver>/<repo>
    if ! mirror_reachable apk "$url"; then
        err "Mirror is not serving Alpine APKINDEX — aborting."
        return 1
    fi
    ok "Mirror reachable."
    local rep=/etc/apk/repositories
    [[ -f "$rep" ]] && backup_file "$rep" apk >/dev/null && info "Backed up $rep"
    local tmpf="$tmpdir/repositories"
    maybe_sudo cat "$rep" > "$tmpf" 2>/dev/null || cat "$rep" > "$tmpf"
    sed -E -i "s|https://dl-cdn.alpinelinux.org/alpine|${url%/}|g; \
               s|http://dl-cdn.alpinelinux.org/alpine|${url%/}|g" "$tmpf"
    maybe_sudo install -m 0644 "$tmpf" "$rep" 2>/dev/null || cp "$tmpf" "$rep"
    ok "apk repositories rewritten to: $url"
    warn "Refresh indexes:"
    printf '    %s\n' "sudo apk update"
}

# Generic yum/dnf host-swap. $1=service (centos|rocky|almalinux|fedora|epel) $2=url
apply_yum() {
    local svc="$1" name="$2" url="$3"
    hdr "Applying dnf/yum mirror ($svc): $name"
    require_root "$svc" "$name" || return 1
    local -A upstreams=(
        [centos]='mirror.stream.centos.org mirror.centos.org'
        [rocky]='dl.rockylinux.org'
        [almalinux]='repo.almalinux.org'
        [fedora]='dl.fedoraproject.org download.fedoraproject.org mirrors.fedoraproject.org'
        [epel]='dl.fedoraproject.org download.fedoraproject.org'
    )
    local ups="${upstreams[$svc]:-}"
    [[ -z "$ups" ]] && { err "Unknown yum service: $svc"; return 1; }
    # Build the replacement: upstream root → mirror root.
    # e.g. dl.rockylinux.org/pub/rocky  →  https://mirror.arvancloud.ir/rocky
    local any_changed=0 f
    for f in /etc/yum.repos.d/*.repo; do
        [[ -e "$f" ]] || continue
        backup_file "$f" yum >/dev/null && info "Backed up $f"
        local tmpf="$tmpdir/$(basename "$f")"
        maybe_sudo cat "$f" > "$tmpf" 2>/dev/null || cat "$f" > "$tmpf"
        local changed=0 u
        for u in $ups; do
            case "$svc:$u" in
                centos:*) sed -E -i "s|https?://${u}/centos|${url}|g; s|https?://${u}|${url}|g" "$tmpf" ;;
                rocky:*)  sed -E -i "s|https?://${u}/pub/rocky|${url}|g" "$tmpf" ;;
                almalinux:*) sed -E -i "s|https?://${u}/pub/almalinux|${url}|g" "$tmpf" ;;
                # use '#' as delimiter so '|' can be regex alternation in (fedora|epel)
                fedora:*|epel:*) sed -E -i "s#https?://${u}/pub/(fedora|epel)#${url%/}/\1#g" "$tmpf" ;;
            esac
        done
        # Comment out metalink/mirrorlist so baseurl takes effect.
        sed -E -i 's|^([[:space:]]*)(metalink=)|\1#\2|g; s|^([[:space:]]*)(mirrorlist=)|\1#\2|g' "$tmpf"
        maybe_sudo install -m 0644 "$tmpf" "$f" 2>/dev/null || cp "$tmpf" "$f"
        any_changed=1
    done
    [[ "$any_changed" -eq 0 ]] && { warn "No repo files found."; return 1; }
    ok "Repo files rewritten (host-swap to: $url)."
    warn "Refresh indexes:"
    printf '    %s\n' "sudo $PKGMGR makecache   # or: sudo $PKGMGR check-update"
}

# Dispatcher
apply_mirror() {
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

# =============================================================================
# MENU — list mirrors for a service, test each, let the user pick.
# =============================================================================
menu_pick_mirror() {
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

    # Probe all mirrors in PARALLEL. Down mirrors can take up to 12s each, so
    # sequential probing of 15-20 mirrors would be painfully slow; running them
    # concurrently caps total time at roughly the slowest single probe.
    info "Testing ${#entries[@]} mirrors in parallel (this takes ~10s)..."
    local results="$tmpdir/picker.$$"
    : > "$results"
    local i
    for ((i=0; i<${#entries[@]}; i++)); do
        (
            if mirror_reachable "$kind" "${urls[$i]}"; then
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
    while IFS='|' read -r idx ok; do
        [[ -z "$idx" ]] && continue
        statuses[idx]="$ok"
    done < "$results"
    rm -f "$results"

    # Render the table.
    printf '  %s%-3s %-22s %-10s %s%s\n' "$C_BOLD" "#" "MIRROR" "STATUS" "URL" "$C_OFF"
    printf '  %s\n' "------------------------------------------------------------"
    for ((i=0; i<${#entries[@]}; i++)); do
        local st color
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
    local idx=$((choice-1))
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
  ${C_BOLD}1)${C_OFF} npm registry         $([ has_npm ] && echo "${C_GREEN}available${C_OFF}" || echo "${C_DIM}not installed${C_OFF}")
  ${C_BOLD}2)${C_OFF} Python PyPI / pip    $([ has_pip ] && echo "${C_GREEN}available${C_OFF}" || echo "${C_DIM}not installed${C_OFF}")
  ${C_BOLD}3)${C_OFF} Docker registry      $([ has_docker ] && echo "${C_GREEN}available${C_OFF}" || echo "${C_DIM}not installed${C_OFF}")
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
            6)
                # pick the right RHEL-family flavor
                local rhel_svc="centos"
                case "$DISTRO_ID" in
                    rocky|rockylinux) rhel_svc="rocky" ;;
                    almalinux|alma) rhel_svc="almalinux" ;;
                    fedora) rhel_svc="fedora" ;;
                    centos|rhel) rhel_svc="centos" ;;
                esac
                menu_pick_mirror "$rhel_svc" ;;
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
    for s in npm pypi docker ubuntu debian centos rocky almalinux fedora epel pacman apk; do
        printf '\n%s%s%s\n' "$C_BOLD" "$(service_label "$s")" "$C_OFF"
        get_mirrors "$s" | awk -F'|' '{printf "  %-22s %s\n", $1, $2}'
    done
}

# Restore a backup file to its inferred original location. No prompting —
# used by both the interactive menu and the `--restore <path>` CLI flag.
restore_backup() {
    local p="$1"
    [[ ! -f "$p" ]] && { err "File not found: $p"; return 1; }
    # Backups are named <basename>.<tag>.<stamp>.bak — recover the target name.
    local base; base="$(basename "$p")"
    local target
    target="$(echo "$base" | sed -E 's/\.[^.]+\.[^.]+\.bak$//')"
    # Heuristic: where does <target> live?
    local dest=""
    for cand in "/etc/$target" "/etc/docker/$target" "/etc/apt/$target" \
                "/etc/apt/sources.list.d/$target" "/etc/yum.repos.d/$target" \
                "/etc/pacman.d/$target" "$(real_home)/.$target" \
                "$(real_home)/.config/pip/$target"; do
        [[ -e "$cand" ]] && dest="$cand" && break
    done
    [[ -z "$dest" ]] && { err "Could not infer the original location for '$base'. Please restore manually from:\n  $p"; return 1; }
    if [[ "$dest" == /etc/* || "$dest" == /var/* ]]; then
        if ! can_sudo; then
            err "Restoring to $dest needs root. Re-run:  sudo bash scan.sh --restore \"$p\""
            return 1
        fi
        maybe_sudo cp -a "$p" "$dest"
    else
        cp -a "$p" "$dest"
    fi
    ok "Restored $dest from $p"
}

menu_restore() {
    list_backups
    hdr "Restore a backup"
    info "Enter the full path shown above (or blank to cancel)."
    local p
    ask p "path> " || { echo; return 0; }
    [[ -z "$p" ]] && return 0
    warn "This will overwrite the inferred original location."
    confirm "  restore" n || return 1
    restore_backup "$p"
}

banner() {
    cat <<EOF
${C_BOLD}${C_CYAN}
  __  __ _ _ __ ___  _ __ ___   ___  _ __
 | \\/ _| | '_ \` _ \\| '_ \` _ \\ / _ \\| '__|
 | |  | | | | | | | | | | | | | (_) | |
 |_| \\_|_|_| |_| |_|_| |_| |_|\\___/|_|
${C_OFF}${C_DIM}Iranian repository mirror scanner & configurator  v${MIRRORS_VERSION}${C_OFF}
EOF
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
        ask c "${C_BOLD}mirrors>${C_OFF} " || { echo "Bye."; return 0; }
        case "$c" in
            1) scan_all; pause ;;
            2)
                hdr "Scan a single service"
                cat <<EOF
  1) npm   2) PyPI   3) Docker   4) apt   5) yum/dnf   6) pacman   7) apk   0) back
EOF
                local s; ask s "> "
                case "$s" in
                    1) scan_npm ;;
                    2) scan_pypi ;;
                    3) scan_docker ;;
                    4) scan_apt ;;
                    5) scan_yum ;;
                    6) scan_pacman ;;
                    7) scan_apk ;;
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

# =============================================================================
# CLI (non-interactive) interface
# =============================================================================
usage() {
    cat <<EOF
${C_BOLD}mirrors${C_OFF} v${MIRRORS_VERSION} — Iranian repository mirror scanner & configurator

${C_BOLD}Usage:${C_OFF}
  mirrors                      Interactive menu
  mirrors --scan               Scan all repositories and print a report
  mirrors --show               Show current configuration
  mirrors --list [service]     List mirrors (all, or one of:
                                npm pypi docker ubuntu debian centos rocky
                                almalinux fedora epel pacman apk)
  mirrors --test <url>         Test reachability of any URL
  mirrors --apply <svc> <name> Apply a mirror by service + name
                                (e.g. --apply npm Liara)
  mirrors --apply <svc> --url <u>   Apply a mirror by raw URL
  mirrors --restore            List backups
  mirrors --version            Print version
  mirrors --help               This help

${C_BOLD}Run directly from GitHub:${C_OFF}
  curl -fsSL https://raw.githubusercontent.com/ihamedm/mirrors/main/scan.sh | bash
  curl -fsSL https://raw.githubusercontent.com/ihamedm/mirrors/main/scan.sh | bash -s -- --scan

${C_BOLD}Services:${C_OFF} npm, pypi, docker, ubuntu, debian, centos, rocky, almalinux,
            fedora, epel, pacman, apk
EOF
}

# Resolve a mirror name to URL within a service.
resolve_mirror() {
    local svc="$1" name="$2" line n u
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        n="${line%%|*}"; u="${line#*|}"
        # Case-insensitive match on name (also accept "all"/"first" shortcuts)
        if [[ "${n,,}" == "${name,,}" ]]; then echo "$u"; return 0; fi
    done < <(get_mirrors "$svc")
    return 1
}

# =============================================================================
# MAIN
# =============================================================================
tmpdir=""
cleanup() { [[ -n "$tmpdir" && -d "$tmpdir" ]] && rm -rf "$tmpdir"; }
trap cleanup EXIT
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/mirrors.XXXXXX")"

detect_os

# Parse arguments
if [[ $# -gt 0 ]]; then
    case "$1" in
        -h|--help)    usage; exit 0 ;;
        -v|--version) echo "mirrors v${MIRRORS_VERSION}"; exit 0 ;;
        --scan|-s)    scan_all; exit 0 ;;
        --show)       show_config; exit 0 ;;
        --list|-l)
            if [[ -n "${2:-}" ]]; then
                if ! get_mirrors "$2" >/dev/null 2>&1 && [[ -z "$(get_mirrors "$2" 2>/dev/null)" ]]; then
                    err "Unknown service: $2"; exit 1
                fi
                get_mirrors "$2" | awk -F'|' '{printf "%-22s %s\n",$1,$2}'
            else
                menu_list_mirrors
            fi
            exit 0 ;;
        --test|-t)
            [[ -z "${2:-}" ]] && { err "URL required."; exit 1; }
            code="$(http_code "$2")"
            echo "$code  $2"; exit 0 ;;
        --apply|-a)
            svc="${2:-}"
            [[ -z "$svc" ]] && { err "Service required. See --help."; exit 1; }
            # Find name/url: either a known name, or --url <rawurl>
            murl=""
            mname=""
            if [[ "${3:-}" == "--url" || "${3:-}" == "-u" ]]; then
                murl="${4:-}"
                mname="custom"
            else
                mname="${3:-}"
                murl="$(resolve_mirror "$svc" "$mname")" || true
            fi
            if [[ -z "$murl" ]]; then
                err "Mirror not found. Use: --apply <svc> <name>  or  --apply <svc> --url <url>"
                err "Known names for '$svc':"
                get_mirrors "$svc" 2>/dev/null | awk -F'|' '{printf "    %-22s %s\n",$1,$2}'
                exit 1
            fi
            apply_mirror "$svc" "$mname" "$murl"
            exit $? ;;
        --restore)
            if [[ -n "${2:-}" ]]; then
                restore_backup "$2"; exit $?
            else
                list_backups
                echo
                info "To restore one: bash scan.sh --restore <path>   (or use the menu)"
                exit 0
            fi ;;
        --interactive) : ;;  # fall through to menu
        *) err "Unknown option: $1"; usage; exit 1 ;;
    esac
fi

# Default: interactive menu
banner
menu_main
