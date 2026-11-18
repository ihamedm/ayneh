# shellcheck shell=bash
# =============================================================================
# MIRROR REGISTRY
# -----------------------------------------------------------------------------
# This is the single place to add mirrors. Each entry is "Name|URL".
# For APT mirrors the URL MUST include the distro path (e.g. .../ubuntu).
# For pacman mirrors the URL is the repo root ($repo/os/$arch is appended).
# For apk mirrors the URL is the alpine root (<branch>/$repo/$arch appended).
# The script always tests a mirror live before applying it, so unreachable or
# wrong-path mirrors simply show up as "unreachable" and are never applied.
# =============================================================================

# Canonical service order, used by menus and --list.
AYNEH_SERVICES=(npm pypi docker ubuntu debian centos rocky almalinux fedora epel pacman apk)

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

# --- apk: Alpine. Root (<branch>/$repo/$arch appended) ---
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
        npm)            printf '%s\n' "${NPM_MIRRORS[@]}" ;;
        pypi)           printf '%s\n' "${PYPI_MIRRORS[@]}" ;;
        docker)         printf '%s\n' "${DOCKER_MIRRORS[@]}" ;;
        ubuntu)         printf '%s\n' "${APT_UBUNTU_MIRRORS[@]}" ;;
        debian)         printf '%s\n' "${APT_DEBIAN_MIRRORS[@]}" ;;
        centos)         printf '%s\n' "${YUM_CENTOS_MIRRORS[@]}" ;;
        rocky)          printf '%s\n' "${YUM_ROCKY_MIRRORS[@]}" ;;
        almalinux|alma) printf '%s\n' "${YUM_ALMA_MIRRORS[@]}" ;;
        fedora)         printf '%s\n' "${YUM_FEDORA_MIRRORS[@]}" ;;
        epel)           printf '%s\n' "${YUM_EPEL_MIRRORS[@]}" ;;
        pacman)         printf '%s\n' "${PACMAN_MIRRORS[@]}" ;;
        apk)            printf '%s\n' "${APK_MIRRORS[@]}" ;;
        *) return 1 ;;
    esac
}

# Normalize friendly aliases to canonical registry keys.
#   apt  -> ubuntu/debian, depending on the running distro
#   yum  -> centos/rocky/almalinux/fedora, depending on the running distro
#   alma -> almalinux
# Prints an empty string when the alias cannot be resolved on this system.
resolve_service_key() {
    case "$1" in
        apt)
            if [[ "$DISTRO_ID" == "ubuntu" ]]; then echo "ubuntu"
            elif [[ "$DISTRO_FAMILY" == "debian" ]]; then echo "debian"
            else echo ""
            fi ;;
        yum|rhel) rhel_service_for_distro ;;
        alma) echo "almalinux" ;;
        *) echo "$1" ;;
    esac
}

# True when a service key (or alias) is known.
is_service() {
    local key s
    key="$(resolve_service_key "$1")"
    [[ -z "$key" ]] && return 1
    for s in "${AYNEH_SERVICES[@]}"; do
        [[ "$s" == "$key" ]] && return 0
    done
    return 1
}

# Map a service key to a human label.
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

# Map a service key to the reachability probe kind.
service_kind() {
    case "$1" in
        ubuntu|debian) echo "apt" ;;
        centos|rocky|almalinux|alma|fedora|epel) echo "yum" ;;
        *) echo "$1" ;;
    esac
}

# Pick the yum flavor that matches the running distro.
rhel_service_for_distro() {
    case "$DISTRO_ID" in
        rocky|rockylinux) echo "rocky" ;;
        almalinux|alma)   echo "almalinux" ;;
        fedora)           echo "fedora" ;;
        *)                echo "centos" ;;
    esac
}

# Resolve a mirror name to URL within a service (case-insensitive).
resolve_mirror() {
    local svc="$1" name="$2" line n u
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        n="${line%%|*}"; u="${line#*|}"
        if [[ "${n,,}" == "${name,,}" ]]; then printf '%s\n' "$u"; return 0; fi
    done < <(get_mirrors "$svc")
    return 1
}
