# Ayneh (آینه)

**Iranian repository mirror scanner & configurator.**

Ayneh probes your package-manager upstreams, and when one is unreachable it
helps you switch to a working Iranian mirror — from an interactive menu or a
single CLI command. It supports npm, PyPI, Docker, apt (Ubuntu/Debian),
dnf/yum (CentOS/Rocky/AlmaLinux/Fedora/EPEL), pacman and apk.

## One-line usage

Run without installing:

```bash
curl -fsSL https://raw.githubusercontent.com/ihamedm/ayneh/main/dist/ayneh.sh | bash
```

Non-interactive (servers/scripts):

```bash
curl -fsSL https://raw.githubusercontent.com/ihamedm/ayneh/main/dist/ayneh.sh | bash -s -- --scan
```

Install as a command:

```bash
curl -fsSL https://raw.githubusercontent.com/ihamedm/ayneh/main/install.sh | sudo bash
ayneh
```

## CLI

```text
ayneh                        Interactive menu
ayneh --scan [service]       Scan all repositories (or one service)
ayneh --show                 Show current configuration
ayneh --list [service]       List registered mirrors
ayneh --test <url>           Probe any URL
ayneh --apply <svc> <name>   Apply a mirror by name
ayneh --apply <svc> --url <u>  Apply a mirror by URL
ayneh --restore [path]       List or restore backups
ayneh --version | --help
```

Services: `npm pypi docker ubuntu debian centos rocky almalinux fedora epel
pacman apk`; aliases `apt`, `yum`, `alma`.

## How it works

Every mirror is tested against a real package path (not just its landing page)
before it is applied. Changed files are backed up to `~/.ayneh-backup/` or
`/var/backups/ayneh/`, with a `.meta` sidecar, and can be restored with
`ayneh --restore`.

Requires bash 4+ and curl. system-wide changes need root (sudo is requested when
needed). No telemetry.

## Development

```bash
git clone https://github.com/ihamedm/ayneh.git
cd ayneh
./build.sh          # regenerate dist/ayneh.sh from lib/
make test           # offline smoke tests
make lint           # shellcheck
```

`dist/ayneh.sh` is generated and committed. Add mirrors in
[`lib/30-registry.sh`](lib/30-registry.sh); see [`CONTRIBUTING.md`](CONTRIBUTING.md).

Persian documentation: [`README.md`](README.md)

## License

[MIT](LICENSE) © 2026 ihamedm and contributors
