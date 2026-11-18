# Contributing

Thanks for helping improve ayneh! The most useful contribution is **adding or
fixing mirrors** — providers come and go, and the more working mirrors we list,
the more reliable the tool is for everyone in Iran.

## Project layout

```
ayneh              dev entry point (sources lib/*.sh)
lib/00-core.sh     logging, prompts, sudo, temp dirs
lib/10-os.sh       distro / package-manager detection
lib/20-http.sh     curl probes, mirror reachability
lib/30-registry.sh THE MIRROR REGISTRY (edit this to add mirrors)
lib/40-scan.sh     upstream scanners + config display
lib/50-backup.sh   timestamped backups and restore
lib/60-apply.sh    per-service mirror appliers
lib/70-menu.sh     interactive menus
lib/90-main.sh     CLI parsing and entry point
build.sh           concatenates lib/*.sh into dist/ayneh.sh
install.sh         one-line installer
```

`dist/ayneh.sh` is generated and **committed** because it is what the
`curl ... | bash` one-liner downloads. Never edit it by hand.

## Adding a mirror

Add one line to the right array in [`lib/30-registry.sh`](lib/30-registry.sh):

| Array | For | URL must end with |
| --- | --- | --- |
| `NPM_MIRRORS` | npm registry | the registry root, e.g. `…/npm/` |
| `PYPI_MIRRORS` | Python PyPI | `…/simple` (the simple index root) |
| `DOCKER_MIRRORS` | Docker registry | the registry host only, e.g. `https://docker.example.ir` |
| `APT_UBUNTU_MIRRORS` | Ubuntu apt | `…/ubuntu` (the distro path) |
| `APT_DEBIAN_MIRRORS` | Debian apt | `…/debian` |
| `YUM_CENTOS_MIRRORS` / `YUM_ROCKY_MIRRORS` / `YUM_ALMA_MIRRORS` / `YUM_FEDORA_MIRRORS` / `YUM_EPEL_MIRRORS` | dnf/yum | the distro root on the mirror |
| `PACMAN_MIRRORS` | Arch pacman | the repo root (`$repo/os/$arch` is appended) |
| `APK_MIRRORS` | Alpine apk | the alpine root (`$branch/$repo/$arch` is appended) |

Example — adding a new npm mirror:

```bash
NPM_MIRRORS=(
    "Liara|https://package-mirror.liara.ir/repository/npm/"
    ...
    "MyProvider|https://npm.myprovider.ir/"      # ← new line
)
```

### Path conventions (important)

The tool derives the probe URL from the registry URL, so the URL you add must
follow the convention or the live test will fail and the mirror will show as
`down`:

- **npm**: probe = `<URL>/npm` → so `URL` is the registry root (`…/npm/`).
- **PyPI**: probe = `<URL>/pip/` → so `URL` already ends with `/simple`.
- **Docker**: probe = `<URL>/v2/` → so `URL` is just the host.
- **apt**: probe = `<URL>/dists/<suite>/Release` → so `URL` ends with
  `/ubuntu` or `/debian`.
- **yum**: probe = `<URL>/<release>/BaseOS/<arch>/os/repodata/repomd.xml`
  (per flavor) → so `URL` is the distro root on the mirror.
- **pacman**: probe = `<URL>/core/os/<arch>/` → so `URL` is the repo root
  (e.g. `https://mirror.example.ir/arch`).
- **apk**: probe = `<URL>/<branch>/main/<arch>/APKINDEX.tar.gz` → so `URL` is
  the alpine root that the existing `/etc/apk/repositories` line would prepend.

### Verify before submitting

The tool always tests a mirror live before applying it, so a wrong URL is
safe — but please confirm your entry actually works:

```bash
# 1. syntax check + regenerate the single-file build
./build.sh
bash -n dist/ayneh.sh

# 2. list mirrors for the service and confirm yours appears
./ayneh --list npm

# 3. test the mirror URL directly
./ayneh --test "https://npm.myprovider.ir/npm"

# 4. run the picker for that service and confirm it shows OK (not down)
./ayneh        # → 3) Apply / switch a mirror → pick the service → see the table

# 5. run the offline test suite
make test
```

For changes touching the Docker applier, run the opt-in nested-Docker test
(needs a privileged Docker daemon and network):

```bash
make integration-docker
```

For npm/PyPI/apt you can also verify the concrete probe path returns 200:

```bash
curl -sI "https://npm.myprovider.ir/npm"          # npm: expect 200
curl -sI "https://pypi.myprovider.ir/simple/pip/"  # pypi: expect 200
curl -sI "https://mirror.myprovider.ir/ubuntu/dists/jammy/Release"  # apt: expect 200
```

## Coding style

- Bash 4+ is fine (we use `${var,,}` lowercasing, associative arrays). Keep it
  POSIX-friendly where it costs nothing.
- `set -uo pipefail` is on; never leave a variable unset, and never rely on
  `set -e` (we handle errors explicitly).
- Keep modules small and put functions in the file that matches their purpose.
- No `cat | grep` where a single tool fits; prefer `awk`/`sed`/`grep` with
  clear intent. Comment non-obvious regex.
- Any change to `lib/` must be followed by `./build.sh`; CI rejects a stale
  `dist/ayneh.sh`.
- Run `make lint` (shellcheck) and `make test` before opening a PR.

## Reporting a broken mirror

If a listed mirror is permanently down or has moved, please open an issue with
the mirror name, service, and (if known) the new URL. Remove it from the array
rather than leaving a dead entry.

## Sources for new mirrors

The [Mirava](https://github.com/MiravaOrg/Mirava) registry is the best
starting point — it tracks Iranian mirror providers and what each one mirrors.
Always confirm the exact endpoint path against the provider's own docs before
adding.
