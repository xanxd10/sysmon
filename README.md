# sysmon.sh — VPS System Monitor

A single-file bash script that gives you a full, colour-coded system snapshot — CPU model, RAM type, disk type, I/O, network speed, top processes, and more. No dependencies beyond standard Linux tools.

![sysmon preview](https://raw.githubusercontent.com/YOUR_USERNAME/sysmon/main/preview.png)

## Features

- **CPU** — model, architecture, cores/threads, frequency, temperature, load average, live usage bar
- **Memory** — total/used/available, buffers, RAM type (DDR4/DDR5), speed, DIMM slots (requires root + dmidecode)
- **Disk** — per-mount usage bars, filesystem type, disk type (SSD/HDD/NVMe), live I/O read/write speeds
- **Network** — interface, IPv4/IPv6, MTU, live download/upload speed, total traffic, packet counts, errors
- **System** — hostname, OS, kernel, uptime, timezone, logged-in users, total processes
- **Top processes** — top N by CPU with user, CPU%, and MEM%
- **Watch mode** — auto-refreshes every N seconds like `htop`
- Colour-coded bars: green → yellow → red by threshold

## Requirements

| Tool | Purpose | Notes |
|------|---------|-------|
| `bash` | Shell | ≥ 4.0 |
| `awk`, `grep`, `ps`, `df`, `ip` | Core stats | Pre-installed on all Linux distros |
| `dmidecode` | RAM type/speed/slots | Optional · needs root |
| `lsblk` | Disk type detection | Optional · pre-installed on most distros |
| `sensors` | CPU temp fallback | Optional · `apt install lm-sensors` |

## Installation

```bash
# clone
git clone https://github.com/YOUR_USERNAME/sysmon.git
cd sysmon

# make executable
chmod +x sysmon.sh

# run once
bash sysmon.sh

# watch mode (refresh every 5s)
bash sysmon.sh --watch

# custom interval
bash sysmon.sh --watch --interval 10

# no colour (for logging)
bash sysmon.sh --no-color >> /var/log/sysmon.log
```

## One-liner install (no clone)

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/sysmon/main/sysmon.sh | bash
```

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--watch` | off | Refresh continuously |
| `--interval N` | `5` | Seconds between refreshes (use with `--watch`) |
| `--no-color` | off | Plain output for logging/piping |
| `-h`, `--help` | — | Show help |

## RAM type detection

RAM type, speed, and slot info require `dmidecode` and root:

```bash
apt install dmidecode   # Debian/Ubuntu
yum install dmidecode   # RHEL/CentOS
sudo bash sysmon.sh
```

Without root, these fields show `N/A (run as root)`.

## Run on a schedule (cron)

```bash
# Log a snapshot every hour
0 * * * * /path/to/sysmon.sh --no-color >> /var/log/sysmon.log 2>&1
```

## License

MIT — do whatever you want with it.
