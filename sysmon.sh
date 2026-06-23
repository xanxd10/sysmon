#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════╗
# ║           SlayerNodes System Monitor v1.0            ║
# ║     Full VPS stats: CPU · RAM · Disk · Network       ║
# ╚══════════════════════════════════════════════════════╝
# Usage: bash sysmon.sh [--watch] [--interval N] [--no-color]

# ─── config ────────────────────────────────────────────
WATCH=false
INTERVAL=5
COLOR=true
TOP_PROC_COUNT=8

# ─── arg parsing ───────────────────────────────────────
while [[ ${1:-} != "" ]]; do
  case "${1:-}" in
    --watch)     WATCH=true ;;
    --interval)  INTERVAL="${2:-5}"; shift ;;
    --no-color)  COLOR=false ;;
    -h|--help)
      echo "Usage: bash sysmon.sh [--watch] [--interval N] [--no-color]"
      exit 0 ;;
    *) ;;
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
  local pct="${1:-0}"
  if   (( pct >= 85 )); then printf "${CRIT}${pct}%%${RST}\n"
  elif (( pct >= 60 )); then printf "${WARN}${pct}%%${RST}\n"
  else                       printf "${OK}${pct}%%${RST}\n"
  fi
}

bar() {
  local pct="${1:-0}" width=30 filled empty color f_str e_str
  filled=$(( pct * width / 100 ))
  empty=$(( width - filled ))
  if   (( pct >= 85 )); then color=$R
  elif (( pct >= 60 )); then color=$Y
  else                       color=$G
  fi
  f_str=""; e_str=""
  [[ $filled -gt 0 ]] && f_str=$(printf '█%.0s' $(seq 1 $filled))
  [[ $empty  -gt 0 ]] && e_str=$(printf '░%.0s' $(seq 1 $empty))
  printf "${DIM}[${RST}${color}%s${RST}${DIM}%s${RST}${DIM}]${RST}" "$f_str" "$e_str"
}

kv() {
  local label="${1:-}" val="${2:-}" indent="${3:-  }"
  printf "${indent}${DIM}%-22s${RST}${W}%s${RST}\n" "${label}:" "${val}"
}

check_cmd() { command -v "$1" &>/dev/null; }

human_kb() {
  local k="${1:-0}"
  awk -v k="$k" 'BEGIN{
    if(k>=1048576) printf "%.1f GB", k/1048576
    else if(k>=1024) printf "%.1f MB", k/1024
    else printf "%d KB", k
  }'
}

# ─── data collectors ───────────────────────────────────

collect_system() {
  SYS_HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
  SYS_OS="Unknown"
  if [[ -f /etc/os-release ]]; then
    SYS_OS=$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
  fi
  SYS_KERNEL=$(uname -r 2>/dev/null || echo "N/A")
  SYS_ARCH=$(uname -m 2>/dev/null || echo "N/A")
  SYS_UPTIME=$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo "N/A")
  SYS_USERS=$(who 2>/dev/null | wc -l || echo "0")
  SYS_PROCS=$(ps aux --no-header 2>/dev/null | wc -l || echo "N/A")
  SYS_TIMEZONE=$(cat /etc/timezone 2>/dev/null || timedatectl 2>/dev/null | awk '/Time zone/{print $3}' || echo "N/A")
  SYS_LAST_BOOT=$(who -b 2>/dev/null | awk '{print $3, $4}' || echo "N/A")
}

collect_cpu() {
  CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ *//' || echo "N/A")
  CPU_ARCH=$(uname -m)
  CPU_CORES=$(nproc 2>/dev/null || echo "N/A")
  CPU_THREADS=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo "N/A")
  CPU_MHZ=$(awk -F: '/cpu MHz/{sum+=$2; n++} END{if(n>0) printf "%.0f", sum/n; else print "N/A"}' /proc/cpuinfo 2>/dev/null)
  CPU_CACHE=$(grep -m1 'cache size' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ *//' || echo "N/A")
  [[ -z "$CPU_CACHE" ]] && CPU_CACHE="N/A"

  read -r LOAD1 LOAD5 LOAD15 _ < /proc/loadavg 2>/dev/null || { LOAD1="N/A"; LOAD5="N/A"; LOAD15="N/A"; }

  # CPU usage sample
  local cpu1 cpu2 total1 idle1 total2 idle2 diff
  cpu1=$(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat 2>/dev/null || echo "0 0")
  sleep 0.5
  cpu2=$(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat 2>/dev/null || echo "0 0")
  total1=$(awk '{print $1}' <<< "$cpu1")
  idle1=$(awk '{print $2}'  <<< "$cpu1")
  total2=$(awk '{print $1}' <<< "$cpu2")
  idle2=$(awk '{print $2}'  <<< "$cpu2")
  diff=$(( total2 - total1 ))
  [[ $diff -le 0 ]] && diff=1
  CPU_PCT=$(( (1000 * (diff - (idle2 - idle1)) / diff + 5) / 10 ))
  [[ $CPU_PCT -lt 0 ]]   && CPU_PCT=0
  [[ $CPU_PCT -gt 100 ]] && CPU_PCT=100

  # temperature
  CPU_TEMP="N/A"
  for f in /sys/class/thermal/thermal_zone*/temp; do
    [[ -f "$f" ]] || continue
    local t
    t=$(cat "$f" 2>/dev/null || echo "0")
    t=$(( t / 1000 ))
    [[ $t -gt 0 ]] && { CPU_TEMP="${t}°C"; break; }
  done
  if [[ "$CPU_TEMP" == "N/A" ]] && check_cmd sensors; then
    local st
    st=$(sensors 2>/dev/null | awk '/Package id 0:|Tdie:|CPU Temp:/{match($0,/[0-9]+\.[0-9]+/); printf "%s", substr($0,RSTART,RLENGTH); exit}')
    [[ -n "$st" ]] && CPU_TEMP="${st}°C"
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
      pct=(total>0) ? int(used*100/total) : 0
      spct=(stotal>0) ? int((stotal-sfree)*100/stotal) : 0
      printf "%d %d %d %d %d %d %d %d %d %d",
        total,used,free,avail,buf+cache,pct,stotal,stotal-sfree,sfree,spct
    }' /proc/meminfo 2>/dev/null)

  read -r MEM_TOTAL_KB MEM_USED_KB MEM_FREE_KB MEM_AVAIL_KB MEM_CACHE_KB MEM_PCT \
           SWAP_TOTAL_KB SWAP_USED_KB SWAP_FREE_KB SWAP_PCT <<< "$mem"

  MEM_TOTAL=$(human_kb "$MEM_TOTAL_KB")
  MEM_USED=$(human_kb  "$MEM_USED_KB")
  MEM_FREE=$(human_kb  "$MEM_FREE_KB")
  MEM_AVAIL=$(human_kb "$MEM_AVAIL_KB")
  MEM_CACHE=$(human_kb "$MEM_CACHE_KB")
  SWAP_TOTAL=$(human_kb "$SWAP_TOTAL_KB")
  SWAP_USED=$(human_kb  "$SWAP_USED_KB")
  SWAP_FREE=$(human_kb  "$SWAP_FREE_KB")

  RAM_TYPE="N/A (run as root)"
  RAM_SPEED="N/A"
  RAM_SLOTS_USED="N/A"
  RAM_SLOTS_TOTAL="N/A"
  if [[ $EUID -eq 0 ]] && check_cmd dmidecode; then
    RAM_TYPE=$(dmidecode -t memory 2>/dev/null | awk '/^\s*Type:/{if($2!="Unknown") {print $2; exit}}')
    RAM_SPEED=$(dmidecode -t memory 2>/dev/null | awk '/^\s*Speed:.*MT/{print $2" "$3; exit}')
    RAM_SLOTS_USED=$(dmidecode -t memory 2>/dev/null | grep -c 'Size:.*[0-9]' 2>/dev/null || echo "N/A")
    RAM_SLOTS_TOTAL=$(dmidecode -t memory 2>/dev/null | grep -c 'Memory Device$' 2>/dev/null || echo "N/A")
    [[ -z "$RAM_TYPE"  ]] && RAM_TYPE="N/A"
    [[ -z "$RAM_SPEED" ]] && RAM_SPEED="N/A"
  fi
}

collect_disk() {
  DISK_INFO=$(df -h --output=target,fstype,size,used,avail,pcent,source 2>/dev/null \
    | grep -v 'tmpfs\|devtmpfs\|squashfs\|overlay\|udev\|none' \
    | grep -v '^/sys\|^/proc\|^/dev/loop\|^/run\|Filesystem' \
    | grep -v '^$' || true)

  DISK_TYPE="N/A"
  if check_cmd lsblk; then
    local src rota
    src=$(findmnt -n -o SOURCE / 2>/dev/null | head -1 || echo "")
    if [[ -n "$src" ]]; then
      rota=$(lsblk -dno ROTA "$src" 2>/dev/null || echo "")
      case "$rota" in
        0) DISK_TYPE="SSD / NVMe" ;;
        1) DISK_TYPE="HDD (spinning)" ;;
      esac
    fi
  fi

  DISK_IO_READ="N/A"
  DISK_IO_WRITE="N/A"
  local dev
  dev=$(findmnt -n -o SOURCE / 2>/dev/null | sed 's|/dev/||' | head -1 || echo "")
  if [[ -n "$dev" ]] && grep -q "$dev" /proc/diskstats 2>/dev/null; then
    local s1 s2 r1 w1 r2 w2
    s1=$(awk -v d="$dev" '$3==d{print $6,$10}' /proc/diskstats 2>/dev/null || echo "0 0")
    sleep 0.5
    s2=$(awk -v d="$dev" '$3==d{print $6,$10}' /proc/diskstats 2>/dev/null || echo "0 0")
    r1=$(awk '{print $1}' <<< "$s1"); w1=$(awk '{print $2}' <<< "$s1")
    r2=$(awk '{print $1}' <<< "$s2"); w2=$(awk '{print $2}' <<< "$s2")
    DISK_IO_READ=$(awk  "BEGIN{printf \"%.1f MB/s\", ($r2-$r1)*512/0.5/1048576}")
    DISK_IO_WRITE=$(awk "BEGIN{printf \"%.1f MB/s\", ($w2-$w1)*512/0.5/1048576}")
  fi
}

collect_net() {
  NET_IFACE=$(ip -o link show 2>/dev/null | awk -F': ' '!/lo/{print $2; exit}' || echo "eth0")
  NET_IP4=$(ip -4 addr show "$NET_IFACE" 2>/dev/null | awk '/inet /{print $2}' | head -1 || echo "")
  NET_IP6=$(ip -6 addr show "$NET_IFACE" 2>/dev/null | awk '/inet6 .* scope global/{print $2}' | head -1 || echo "")
  [[ -z "$NET_IP4" ]] && NET_IP4="N/A (IPv6-only)"
  [[ -z "$NET_IP6" ]] && NET_IP6="N/A"

  local rx1 tx1 rx2 tx2
  rx1=$(awk -v i="${NET_IFACE}:" '$1==i{print $2}' /proc/net/dev 2>/dev/null || echo "0")
  tx1=$(awk -v i="${NET_IFACE}:" '$1==i{print $10}' /proc/net/dev 2>/dev/null || echo "0")
  sleep 1
  rx2=$(awk -v i="${NET_IFACE}:" '$1==i{print $2}' /proc/net/dev 2>/dev/null || echo "0")
  tx2=$(awk -v i="${NET_IFACE}:" '$1==i{print $10}' /proc/net/dev 2>/dev/null || echo "0")
  [[ -z "$rx1" ]] && rx1=0; [[ -z "$rx2" ]] && rx2=0
  [[ -z "$tx1" ]] && tx1=0; [[ -z "$tx2" ]] && tx2=0
  NET_RX_SPEED=$(awk "BEGIN{printf \"%.2f MB/s\", ($rx2-$rx1)/1048576}")
  NET_TX_SPEED=$(awk "BEGIN{printf \"%.2f MB/s\", ($tx2-$tx1)/1048576}")

  NET_RX_TOTAL=$(awk -v i="${NET_IFACE}:" '$1==i{
    b=$2; if(b>=1073741824) printf "%.2f GB",b/1073741824
    else if(b>=1048576) printf "%.2f MB",b/1048576
    else printf "%d KB",b/1024}' /proc/net/dev 2>/dev/null || echo "N/A")
  NET_TX_TOTAL=$(awk -v i="${NET_IFACE}:" '$1==i{
    b=$10; if(b>=1073741824) printf "%.2f GB",b/1073741824
    else if(b>=1048576) printf "%.2f MB",b/1048576
    else printf "%d KB",b/1024}' /proc/net/dev 2>/dev/null || echo "N/A")

  NET_PACKETS_RX=$(awk -v i="${NET_IFACE}:" '$1==i{print $3}' /proc/net/dev 2>/dev/null || echo "N/A")
  NET_PACKETS_TX=$(awk -v i="${NET_IFACE}:" '$1==i{print $11}' /proc/net/dev 2>/dev/null || echo "N/A")
  NET_ERRORS=$(awk -v i="${NET_IFACE}:" '$1==i{print $4+$12}' /proc/net/dev 2>/dev/null || echo "0")
  NET_MTU=$(ip link show "$NET_IFACE" 2>/dev/null | awk '/mtu/{for(i=1;i<=NF;i++) if($i=="mtu") print $(i+1)}' || echo "N/A")
}

collect_procs() {
  TOP_PROCS=$(ps aux --no-header --sort=-%cpu 2>/dev/null \
    | head -"$TOP_PROC_COUNT" \
    | awk '{printf "  %-22s %-10s %6s%% %6s%%\n", $11, $1, $3, $4}' || true)
}

# ─── render ────────────────────────────────────────────

render() {
  local NOW
  NOW=$(date '+%Y-%m-%d %H:%M:%S')

  $WATCH && clear

  echo
  printf "${BOLD}${C}╔══════════════════════════════════════════════════════════╗${RST}\n"
  printf "${BOLD}${C}║${RST}  ${BOLD}${W}System Monitor${RST}  ${DIM}%-42s${RST}${BOLD}${C}║${RST}\n" "$NOW"
  printf "${BOLD}${C}╚══════════════════════════════════════════════════════════╝${RST}\n"

  section "System"
  kv "Hostname"        "$SYS_HOSTNAME"
  kv "OS"              "$SYS_OS"
  kv "Kernel"          "$SYS_KERNEL ($SYS_ARCH)"
  kv "Uptime"          "$SYS_UPTIME"
  kv "Last boot"       "$SYS_LAST_BOOT"
  kv "Timezone"        "$SYS_TIMEZONE"
  kv "Users logged in" "$SYS_USERS"
  kv "Total processes" "$SYS_PROCS"

  section "CPU"
  kv "Model"              "$CPU_MODEL"
  kv "Architecture"       "$CPU_ARCH"
  kv "Cores / threads"    "$CPU_CORES / $CPU_THREADS"
  kv "Frequency"          "${CPU_MHZ} MHz"
  kv "Cache (L3)"         "$CPU_CACHE"
  kv "Temperature"        "$CPU_TEMP"
  kv "Load avg (1/5/15)"  "$LOAD1 / $LOAD5 / $LOAD15"
  printf "  ${DIM}%-22s${RST}" "Usage:"
  bar "$CPU_PCT"
  printf "  %s\n" "$(color_pct $CPU_PCT)"

  section "Memory"
  kv "Total RAM"     "$MEM_TOTAL"
  kv "Used"          "$MEM_USED"
  kv "Available"     "$MEM_AVAIL"
  kv "Buffers/cache" "$MEM_CACHE"
  kv "RAM type"      "$RAM_TYPE"
  kv "RAM speed"     "$RAM_SPEED"
  kv "DIMM slots"    "${RAM_SLOTS_USED} / ${RAM_SLOTS_TOTAL} used"
  printf "  ${DIM}%-22s${RST}" "RAM usage:"
  bar "$MEM_PCT"
  printf "  %s\n" "$(color_pct $MEM_PCT)"
  if [[ "${SWAP_TOTAL_KB:-0}" -gt 0 ]]; then
    kv "Swap total" "$SWAP_TOTAL"
    kv "Swap used"  "$SWAP_USED"
    printf "  ${DIM}%-22s${RST}" "Swap usage:"
    bar "$SWAP_PCT"
    printf "  %s\n" "$(color_pct $SWAP_PCT)"
  else
    kv "Swap" "Disabled"
  fi

  section "Disk"
  kv "Disk type" "$DISK_TYPE"
  kv "I/O read"  "$DISK_IO_READ"
  kv "I/O write" "$DISK_IO_WRITE"
  echo
  printf "  ${BOLD}${DIM}%-20s %-8s %8s %8s %8s${RST}\n" "Mount" "FS" "Size" "Used" "Avail"
  hr
  if [[ -n "$DISK_INFO" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local mnt fs size used avail pct_str pct_num
      mnt=$(awk '{print $1}'     <<< "$line")
      fs=$(awk '{print $2}'      <<< "$line")
      size=$(awk '{print $3}'    <<< "$line")
      used=$(awk '{print $4}'    <<< "$line")
      avail=$(awk '{print $5}'   <<< "$line")
      pct_str=$(awk '{print $6}' <<< "$line")
      pct_num="${pct_str//%/}"
      pct_num="${pct_num:-0}"
      printf "  %-20s %-8s %8s %8s %8s  " "$mnt" "$fs" "$size" "$used" "$avail"
      bar "$pct_num"
      printf "  %s\n" "$(color_pct $pct_num)"
    done <<< "$DISK_INFO"
  else
    printf "  ${DIM}No disk info available${RST}\n"
  fi

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

  section "Top processes (by CPU)"
  printf "  ${BOLD}${DIM}%-22s %-10s %7s %7s${RST}\n" "Command" "User" "CPU%" "MEM%"
  hr
  printf "%s\n" "$TOP_PROCS"

  echo
  $WATCH && printf "${DIM}  Auto-refreshing every ${INTERVAL}s · Ctrl+C to exit${RST}\n"
  echo
}

# ─── main ──────────────────────────────────────────────

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
