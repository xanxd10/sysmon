#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════╗
# ║           SlayerNodes System Monitor v1.0            ║
# ║     Full VPS stats: CPU · RAM · Disk · Network       ║
# ╚══════════════════════════════════════════════════════╝
# Usage: bash sysmon.sh [--watch] [--interval N] [--no-color]

set -euo pipefail

# ─── config ────────────────────────────────────────────
WATCH=false
INTERVAL=5
COLOR=true
TOP_PROC_COUNT=8

# ─── arg parsing ───────────────────────────────────────
while [[ ${1:-} != "" ]]; do
  case ${1:-} in
    --watch)     WATCH=true ;;
    --interval)  INTERVAL="$2"; shift ;;
    --no-color)  COLOR=false ;;
    -h|--help)
      echo "Usage: bash sysmon.sh [--watch] [--interval N] [--no-color]"
      echo "  --watch        Refresh every N seconds (default 5)"
      echo "  --interval N   Set refresh interval in seconds"
      echo "  --no-color     Disable color output"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

# ─── colors ────────────────────────────────────────────
if $COLOR; then
  R='\033[0;31m' G='\033[0;32m' Y='\033[0;33m'
  B='\033[0;34m' C='\033[0;36m' W='\033[1;37m'
  DIM='\033[2m'  BOLD='\033[1m' RST='\033[0m'
  OK='\033[0;32m' WARN='\033[0;33m' CRIT='\033[0;31m'
else
  R='' G='' Y='' B='' C='' W='' DIM='' BOLD='' RST='' OK='' WARN='' CRIT=''
fi

# ─── helpers ───────────────────────────────────────────
hr() { printf "${DIM}%s${RST}\n" "$(printf '─%.0s' $(seq 1 60))"; }

section() { echo; printf "${BOLD}${C}  ▸ %s${RST}\n" "$1"; hr; }

color_pct() {
  local pct=$1
  if   (( pct >= 85 )); then echo -e "${CRIT}${pct}%${RST}"
  elif (( pct >= 60 )); then echo -e "${WARN}${pct}%${RST}"
  else                       echo -e "${OK}${pct}%${RST}"
  fi
}

bar() {
  local pct=$1 width=30
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local color
  if   (( pct >= 85 )); then color=$R
  elif (( pct >= 60 )); then color=$Y
  else                       color=$G
  fi
  printf "${DIM}[${RST}${color}%s${RST}${DIM}%s${RST}${DIM}]${RST}" \
    "$(printf '█%.0s' $(seq 1 $filled))" \
    "$(printf '░%.0s' $(seq 1 $empty))"
}

kv() {
  # kv "Label" "value" [indent]
  local label=$1 val=$2 indent="${3:-  }"
  printf "${indent}${DIM}%-22s${RST}${W}%s${RST}\n" "${label}:" "${val}"
}

check_cmd() { command -v "$1" &>/dev/null; }

# ─── data collectors ───────────────────────────────────

collect_cpu() {
  # CPU model
  CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')
  CPU_ARCH=$(uname -m)
  CPU_CORES=$(nproc)
  CPU_THREADS=$(grep -c '^processor' /proc/cpuinfo)
  CPU_MHZ=$(awk -F: '/cpu MHz/{sum+=$2; n++} END{printf "%.0f", sum/n}' /proc/cpuinfo)
  CPU_CACHE=$(grep -m1 'cache size' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')

  # load averages
  read -r LOAD1 LOAD5 LOAD15 _ < /proc/loadavg

  # CPU usage (sample over 0.5s)
  local cpu1 cpu2
  cpu1=$(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat)
  sleep 0.5
  cpu2=$(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat)
  local total1 idle1 total2 idle2
  total1=$(echo "$cpu1" | awk '{print $1}')
  idle1=$(echo "$cpu1"  | awk '{print $2}')
  total2=$(echo "$cpu2" | awk '{print $1}')
  idle2=$(echo "$cpu2"  | awk '{print $2}')
  CPU_PCT=$(( (1000 * (total2-total1-(idle2-idle1)) / (total2-total1) + 5) / 10 ))

  # temperature (try multiple paths)
  CPU_TEMP="N/A"
  for f in /sys/class/thermal/thermal_zone*/temp; do
    [[ -f "$f" ]] || continue
    local t
    t=$(cat "$f")
    t=$(( t / 1000 ))
    CPU_TEMP="${t}°C"
    break
  done
  if [[ "$CPU_TEMP" == "N/A" ]] && check_cmd sensors; then
    CPU_TEMP=$(sensors 2>/dev/null | awk '/Package id 0:|Tdie:|CPU Temp:/{gsub(/[^0-9.]/,"",$2); printf "%.0f°C", $2; exit}')
    [[ -z "$CPU_TEMP" ]] && CPU_TEMP="N/A"
  fi
}

collect_mem() {
  local mem
  mem=$(awk '
    /^MemTotal:/     {total=$2}
    /^MemFree:/      {free=$2}
    /^MemAvailable:/ {avail=$2}
    /^Buffers:/      {buf=$2}
    /^Cached:/       {cache=$2}
    /^SwapTotal:/    {stotal=$2}
    /^SwapFree:/     {sfree=$2}
    END {
      used=total-avail
      pct=int(used*100/total)
      spct=stotal>0 ? int((stotal-sfree)*100/stotal) : 0
      printf "%d %d %d %d %d %d %d %d %d %d",
        total,used,free,avail,buf+cache,pct,stotal,stotal-sfree,sfree,spct
    }' /proc/meminfo)
  read -r MEM_TOTAL_KB MEM_USED_KB MEM_FREE_KB MEM_AVAIL_KB MEM_CACHE_KB MEM_PCT \
           SWAP_TOTAL_KB SWAP_USED_KB SWAP_FREE_KB SWAP_PCT <<< "$mem"

  human_kb() { awk -v k="$1" 'BEGIN{
    if(k>=1048576) printf "%.1f GB", k/1048576
    else if(k>=1024) printf "%.1f MB", k/1024
    else printf "%d KB", k
  }'; }

  MEM_TOTAL=$(human_kb <<< "$MEM_TOTAL_KB")
  MEM_USED=$(human_kb  <<< "$MEM_USED_KB")
  MEM_FREE=$(human_kb  <<< "$MEM_FREE_KB")
  MEM_AVAIL=$(human_kb <<< "$MEM_AVAIL_KB")
  MEM_CACHE=$(human_kb <<< "$MEM_CACHE_KB")
  SWAP_TOTAL=$(human_kb <<< "$SWAP_TOTAL_KB")
  SWAP_USED=$(human_kb  <<< "$SWAP_USED_KB")
  SWAP_FREE=$(human_kb  <<< "$SWAP_FREE_KB")

  # RAM type & speed via dmidecode (needs root)
  RAM_TYPE="N/A (run as root)"
  RAM_SPEED="N/A"
  RAM_SLOTS_USED="N/A"
  RAM_SLOTS_TOTAL="N/A"
  if [[ $EUID -eq 0 ]] && check_cmd dmidecode; then
    RAM_TYPE=$(dmidecode -t memory 2>/dev/null | awk '/^\s*Type:/{print $2; exit}')
    RAM_SPEED=$(dmidecode -t memory 2>/dev/null | awk '/^\s*Speed:.*MT/{print $2" "$3; exit}')
    RAM_SLOTS_USED=$(dmidecode -t memory 2>/dev/null | grep -c 'Size:.*MB\|Size:.*GB' || echo "N/A")
    RAM_SLOTS_TOTAL=$(dmidecode -t memory 2>/dev/null | grep -c 'Memory Device$' || echo "N/A")
    [[ -z "$RAM_TYPE"  ]] && RAM_TYPE="N/A"
    [[ -z "$RAM_SPEED" ]] && RAM_SPEED="N/A"
  fi
}

collect_disk() {
  # mount points (skip tmpfs, devtmpfs, etc.)
  DISK_INFO=$(df -h --output=target,fstype,size,used,avail,pcent,source 2>/dev/null \
    | grep -v '^Filesystem\|tmpfs\|devtmpfs\|squashfs\|overlay\|udev' \
    | grep -v '^/sys\|^/proc\|^/dev/loop\|^/run' \
    | tail -n +2)

  # disk type per mount
  DISK_TYPE="N/A"
  if check_cmd lsblk; then
    local rota
    rota=$(lsblk -dno ROTA "$(findmnt -n -o SOURCE / 2>/dev/null | head -1)" 2>/dev/null || echo "")
    case "$rota" in
      0) DISK_TYPE="SSD / NVMe" ;;
      1) DISK_TYPE="HDD (spinning)" ;;
    esac
  fi

  # disk I/O stats (read/write since boot, sample delta)
  local stats1 stats2
  local dev
  dev=$(findmnt -n -o SOURCE / 2>/dev/null | sed 's|/dev/||' | head -1 || echo "")
  DISK_IO_READ="N/A"
  DISK_IO_WRITE="N/A"
  if [[ -n "$dev" ]] && grep -q "^[[:space:]]*${dev}" /proc/diskstats 2>/dev/null; then
    stats1=$(awk -v d="$dev" '$3==d{print $6,$10}' /proc/diskstats)
    sleep 0.5
    stats2=$(awk -v d="$dev" '$3==d{print $6,$10}' /proc/diskstats)
    local r1 w1 r2 w2
    r1=$(echo "$stats1" | awk '{print $1}'); w1=$(echo "$stats1" | awk '{print $2}')
    r2=$(echo "$stats2" | awk '{print $1}'); w2=$(echo "$stats2" | awk '{print $2}')
    DISK_IO_READ=$(awk "BEGIN{printf \"%.1f MB/s\", ($r2-$r1)*512/0.5/1048576}")
    DISK_IO_WRITE=$(awk "BEGIN{printf \"%.1f MB/s\", ($w2-$w1)*512/0.5/1048576}")
  fi
}

collect_net() {
  # primary interface (first non-lo)
  NET_IFACE=$(ip -o link show | awk -F': ' '!/lo/{print $2; exit}')
  NET_IP4=$(ip -4 addr show "$NET_IFACE" 2>/dev/null | awk '/inet /{print $2}' | head -1)
  NET_IP6=$(ip -6 addr show "$NET_IFACE" 2>/dev/null | awk '/inet6 .* scope global/{print $2}' | head -1)
  [[ -z "$NET_IP4" ]] && NET_IP4="N/A (IPv6-only)"
  [[ -z "$NET_IP6" ]] && NET_IP6="N/A"

  local rx1 tx1 rx2 tx2
  rx1=$(awk -v i="$NET_IFACE" '$1==i":"{print $2}' /proc/net/dev)
  tx1=$(awk -v i="$NET_IFACE" '$1==i":"{print $10}' /proc/net/dev)
  sleep 1
  rx2=$(awk -v i="$NET_IFACE" '$1==i":"{print $2}' /proc/net/dev)
  tx2=$(awk -v i="$NET_IFACE" '$1==i":"{print $10}' /proc/net/dev)
  NET_RX_SPEED=$(awk "BEGIN{printf \"%.2f MB/s\", ($rx2-$rx1)/1048576}")
  NET_TX_SPEED=$(awk "BEGIN{printf \"%.2f MB/s\", ($tx2-$tx1)/1048576}")

  # total bytes since boot
  NET_RX_TOTAL=$(awk -v i="$NET_IFACE" '$1==i":"{
    b=$2; if(b>=1073741824) printf "%.2f GB",b/1073741824
    else if(b>=1048576) printf "%.2f MB",b/1048576
    else printf "%d KB",b/1024}' /proc/net/dev)
  NET_TX_TOTAL=$(awk -v i="$NET_IFACE" '$1==i":"{
    b=$10; if(b>=1073741824) printf "%.2f GB",b/1073741824
    else if(b>=1048576) printf "%.2f MB",b/1048576
    else printf "%d KB",b/1024}' /proc/net/dev)

  NET_PACKETS_RX=$(awk -v i="$NET_IFACE" '$1==i":"{print $3}' /proc/net/dev)
  NET_PACKETS_TX=$(awk -v i="$NET_IFACE" '$1==i":"{print $11}' /proc/net/dev)
  NET_ERRORS=$(awk -v i="$NET_IFACE" '$1==i":"{print $4+$12}' /proc/net/dev)
  NET_MTU=$(ip link show "$NET_IFACE" 2>/dev/null | awk '/mtu/{for(i=1;i<=NF;i++) if($i=="mtu") print $(i+1)}')
}

collect_system() {
  SYS_HOSTNAME=$(hostname -f 2>/dev/null || hostname)
  SYS_OS=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo "Unknown")
  SYS_KERNEL=$(uname -r)
  SYS_ARCH=$(uname -m)
  SYS_UPTIME=$(uptime -p 2>/dev/null || uptime)
  SYS_USERS=$(who | wc -l)
  SYS_PROCS=$(ps aux --no-header | wc -l)
  SYS_TIMEZONE=$(timedatectl 2>/dev/null | awk '/Time zone/{print $3}' || cat /etc/timezone 2>/dev/null || echo "N/A")
  SYS_LAST_BOOT=$(who -b 2>/dev/null | awk '{print $3, $4}' || echo "N/A")
}

collect_procs() {
  # top N processes by CPU
  TOP_PROCS=$(ps aux --no-header --sort=-%cpu 2>/dev/null \
    | head -"$TOP_PROC_COUNT" \
    | awk '{printf "  %-22s %-8s %6s%% %6s%%\n", $11, $1, $3, $4}')
}

# ─── render ────────────────────────────────────────────

render() {
  local NOW
  NOW=$(date '+%Y-%m-%d %H:%M:%S')

  if $WATCH; then clear; fi

  echo
  printf "${BOLD}${C}╔══════════════════════════════════════════════════════════╗${RST}\n"
  printf "${BOLD}${C}║${RST}  ${BOLD}${W}System Monitor${RST}  ${DIM}%-42s${RST}${BOLD}${C}║${RST}\n" "$NOW"
  printf "${BOLD}${C}╚══════════════════════════════════════════════════════════╝${RST}\n"

  # ── system overview ──────────────────────────────────
  section "System"
  kv "Hostname"    "$SYS_HOSTNAME"
  kv "OS"          "$SYS_OS"
  kv "Kernel"      "$SYS_KERNEL ($SYS_ARCH)"
  kv "Uptime"      "$SYS_UPTIME"
  kv "Last boot"   "$SYS_LAST_BOOT"
  kv "Timezone"    "$SYS_TIMEZONE"
  kv "Users logged in" "$SYS_USERS"
  kv "Total processes" "$SYS_PROCS"

  # ── CPU ──────────────────────────────────────────────
  section "CPU"
  kv "Model"       "$CPU_MODEL"
  kv "Architecture" "$CPU_ARCH"
  kv "Cores / threads" "$CPU_CORES / $CPU_THREADS"
  kv "Frequency"   "${CPU_MHZ} MHz"
  kv "Cache (L3)"  "$CPU_CACHE"
  kv "Temperature" "$CPU_TEMP"
  kv "Load avg (1/5/15)" "$LOAD1 / $LOAD5 / $LOAD15"
  printf "  ${DIM}%-22s${RST}" "Usage:"
  bar $CPU_PCT
  printf "  %s\n" "$(color_pct $CPU_PCT)"

  # ── memory ───────────────────────────────────────────
  section "Memory"
  kv "Total RAM"   "$MEM_TOTAL"
  kv "Used"        "$MEM_USED"
  kv "Available"   "$MEM_AVAIL"
  kv "Buffers/cache" "$MEM_CACHE"
  kv "RAM type"    "$RAM_TYPE"
  kv "RAM speed"   "$RAM_SPEED"
  kv "DIMM slots"  "$RAM_SLOTS_USED / $RAM_SLOTS_TOTAL used"
  printf "  ${DIM}%-22s${RST}" "RAM usage:"
  bar $MEM_PCT
  printf "  %s\n" "$(color_pct $MEM_PCT)"

  if [[ "$SWAP_TOTAL_KB" -gt 0 ]]; then
    kv "Swap total"  "$SWAP_TOTAL"
    kv "Swap used"   "$SWAP_USED"
    printf "  ${DIM}%-22s${RST}" "Swap usage:"
    bar $SWAP_PCT
    printf "  %s\n" "$(color_pct $SWAP_PCT)"
  else
    kv "Swap" "Disabled"
  fi

  # ── disk ─────────────────────────────────────────────
  section "Disk"
  kv "Disk type"   "$DISK_TYPE"
  kv "I/O read"    "$DISK_IO_READ"
  kv "I/O write"   "$DISK_IO_WRITE"
  echo
  printf "  ${BOLD}${DIM}%-18s %-8s %8s %8s %8s${RST}\n" "Mount" "FS" "Size" "Used" "Avail"
  hr
  while IFS= read -r line; do
    local mnt fs size used avail pct_str src
    mnt=$(echo "$line" | awk '{print $1}')
    fs=$(echo "$line"  | awk '{print $2}')
    size=$(echo "$line"| awk '{print $3}')
    used=$(echo "$line"| awk '{print $4}')
    avail=$(echo "$line"| awk '{print $5}')
    pct_str=$(echo "$line"| awk '{print $6}')
    src=$(echo "$line" | awk '{print $7}')
    local pct_num=${pct_str//%/}
    printf "  %-18s %-8s %8s %8s %8s  " "$mnt" "$fs" "$size" "$used" "$avail"
    bar "${pct_num:-0}"
    printf "  %s\n" "$(color_pct ${pct_num:-0})"
  done <<< "$DISK_INFO"

  # ── network ──────────────────────────────────────────
  section "Network"
  kv "Interface"   "$NET_IFACE"
  kv "IPv4"        "$NET_IP4"
  kv "IPv6"        "$NET_IP6"
  kv "MTU"         "$NET_MTU"
  kv "↓ Speed"     "$NET_RX_SPEED"
  kv "↑ Speed"     "$NET_TX_SPEED"
  kv "↓ Total in"  "$NET_RX_TOTAL"
  kv "↑ Total out" "$NET_TX_TOTAL"
  kv "Packets in"  "$NET_PACKETS_RX"
  kv "Packets out" "$NET_PACKETS_TX"
  kv "Errors"      "$NET_ERRORS"

  # ── top processes ─────────────────────────────────────
  section "Top processes (by CPU)"
  printf "  ${BOLD}${DIM}%-22s %-8s %7s %7s${RST}\n" "Command" "User" "CPU%" "MEM%"
  hr
  echo -e "$TOP_PROCS"

  echo
  if $WATCH; then
    printf "${DIM}  Auto-refreshing every ${INTERVAL}s · Ctrl+C to exit${RST}\n"
  fi
  echo
}

# ─── main loop ─────────────────────────────────────────

run_once() {
  collect_system
  collect_cpu
  collect_mem
  collect_disk
  collect_net
  collect_procs
  render
}

if $WATCH; then
  while true; do
    run_once
    sleep "$INTERVAL"
  done
else
  run_once
fi