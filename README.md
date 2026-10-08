# server-healthcheck

[![CI](https://github.com/int3erlud3/server-healthcheck/actions/workflows/ci.yml/badge.svg)](https://github.com/int3erlud3/server-healthcheck/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

```text
   ___ ___ _ ___ _____ _ _
  (_-</ -_) '_\ V / -_) '_|
  /__/\___|_|  \_/\___|_|
   _             _ _   _       _           _
  | |_  ___ __ _| | |_| |_  __| |_  ___ __| |__
  | ' \/ -_) _` | |  _| ' \/ _| ' \/ -_) _| / /
  |_||_\___\__,_|_|\__|_||_\__|_||_\___\__|_\_\

+====================================================================+
|  SERVER HEALTHCHECK  ::  System Health & Service Monitor           |
+--------------------------------------------------------------------+
|  CPU, memory, disk, services & ports with Nagios-ready exit codes  |
|  v1.0.0  -  Bastion Ops Toolkit  -  by int3erlud3                  |
+====================================================================+
```

A dependency-free Bash health check for Linux servers. It checks CPU load, memory,
disk usage, systemd services and listening TCP ports, prints a human-readable table
or JSON, and returns **Nagios/Icinga-compatible exit codes** so it can be used from
cron, monitoring agents or CI.

## Features

- **CPU**: 1-minute load average per core (percent)
- **Memory**: used memory based on `MemAvailable` (percent)
- **Disk**: usage of every real filesystem (`tmpfs`, `devtmpfs`, `squashfs` and
  Docker overlay mounts are ignored)
- **systemd services**: verifies that the listed units are `active`
- **Listening ports**: verifies that TCP ports are listening (IPv4 and IPv6, via `ss`)
- Output as **text** or **JSON**
- Configurable thresholds (CLI flags or config file)
- Exit codes: `0` OK, `1` WARNING, `2` CRITICAL, `3` UNKNOWN / usage error

## Requirements

Bash ≥ 4.4, coreutils, `awk`, `df`, `ss` (iproute2) and `systemctl` for the service check.
No root privileges are required.

## Installation

```bash
git clone https://github.com/int3erlud3/server-healthcheck.git
sudo install -m 0755 server-healthcheck/bin/server-healthcheck /usr/local/bin/
sudo install -m 0644 server-healthcheck/examples/healthcheck.conf /etc/server-healthcheck.conf
```

## Usage

```bash
# Default checks (CPU, memory, disk)
server-healthcheck

# Also require sshd + nginx to be active and ports 22/443 to be listening
server-healthcheck --services sshd,nginx --ports 22,443

# JSON output for scripts / log shipping
server-healthcheck --format json | jq .

# Only disk, with custom thresholds
server-healthcheck --checks disk --disk-warn 70 --disk-crit 85

# Use a config file (CLI flags always win)
server-healthcheck --config /etc/server-healthcheck.conf
```

Example text output:

```text
[OK]       cpu                             12  load1=0.48 cores=4
[OK]       mem                             41  used=3280MiB total=7962MiB
[WARNING]  disk:/                          83  fs=/dev/sda1 avail_kb=6912432
[OK]       service:sshd                     -  active
[CRITICAL] port:443                         -  not listening
OVERALL: CRITICAL
```

Example JSON output:

```json
{"host":"web01","timestamp":"2026-10-08T08:00:00Z","status":"OK","exit_code":0,
 "checks":[{"name":"cpu","status":"OK","value":12,"message":"load1=0.48 cores=4"}]}
```

Cron example (mail only when something is wrong):

```cron
*/15 * * * * nobody /usr/local/bin/server-healthcheck -c /etc/server-healthcheck.conf >/dev/null || /usr/local/bin/server-healthcheck -c /etc/server-healthcheck.conf
```

## Configuration

| Setting / flag                 | Default                        | Description                              |
|--------------------------------|--------------------------------|------------------------------------------|
| `CPU_WARN` / `--cpu-warn`      | `80`                           | Load per core (%) for WARNING            |
| `CPU_CRIT` / `--cpu-crit`      | `95`                           | Load per core (%) for CRITICAL           |
| `MEM_WARN` / `--mem-warn`      | `80`                           | Memory used (%) for WARNING              |
| `MEM_CRIT` / `--mem-crit`      | `95`                           | Memory used (%) for CRITICAL             |
| `DISK_WARN` / `--disk-warn`    | `80`                           | Disk used (%) for WARNING                |
| `DISK_CRIT` / `--disk-crit`    | `90`                           | Disk used (%) for CRITICAL               |
| `SERVICES` / `--services`      | *(empty)*                      | Comma-separated systemd units            |
| `PORTS` / `--ports`            | *(empty)*                      | Comma-separated TCP ports                |
| `CHECKS` / `--checks`          | `cpu,mem,disk,services,ports`  | Checks to run                            |
| `FORMAT` / `--format`          | `text`                         | `text` or `json`                         |

See [`examples/healthcheck.conf`](examples/healthcheck.conf).

## Startup banner

Part of the **Bastion Ops Toolkit**. When run interactively, `server-healthcheck` prints the
banner shown above to **stderr** – only if stderr is a terminal and never together with `--format json`. Pipes,
cron jobs, systemd units and monitoring agents see exactly the same output and exit
codes as before. Disable it with `--no-banner` or `NO_BANNER=1`; `--help` and
`--version` show it on a terminal too.

## Development

```bash
make lint   # shellcheck
make test   # bats-core test suite (external commands are mocked)
make scan   # gitleaks secret scan (needs Docker)
```

## Security notes

- The config file is **parsed, never `source`d**: only whitelisted `KEY=VALUE`
  settings are accepted, so a config file cannot execute code.
- All inputs (thresholds, unit names, ports, format) are validated against strict
  patterns before use; unit names are passed to `systemctl` after `--` as a single
  argument (no `eval`, no shell string building).
- Runs fine as an unprivileged user (e.g. `nobody`); no root needed.
- JSON output is escaped to prevent log/JSON injection via mount point names.

See [SECURITY.md](SECURITY.md) for how to report vulnerabilities.

## License

[MIT](LICENSE)
