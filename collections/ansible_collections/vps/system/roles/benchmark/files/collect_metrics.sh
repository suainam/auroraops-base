#!/bin/bash
# AuroraOps Benchmark Collector
# Purpose: Run 融合怪 (Fusion Monster/ecs.sh) and extract key metrics
# Source: https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh

set -euo pipefail

OUTPUT_JSON="/etc/ansible/facts.d/performance.fact"
REPORT_FILE="/var/log/auroraops/benchmark_report.txt"
CLEAN_REPORT="/var/log/auroraops/benchmark_report_clean.txt"
mkdir -p /etc/ansible/facts.d /var/log/auroraops

echo "=== AuroraOps: Running Benchmark Collector ==="

MODE="${AURORAOPS_BENCHMARK_MODE:-fast}"

run_fast_benchmark() {
  echo "=== AuroraOps: Running fast local Benchmark ===" > "$REPORT_FILE"

  CPU_MODEL=$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null || true)
  CPU_MODEL="${CPU_MODEL:-UNKNOWN}"
  CPU_CORES=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo "0")
  RAM_MB=$(awk '/MemTotal/ {printf "%.0f", $2 / 1024}' /proc/meminfo 2>/dev/null || echo "0")
  DISK_GB=$(df -BG / 2>/dev/null | awk 'NR==2 {gsub("G", "", $2); print $2}' || echo "0")
  VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || echo "UNKNOWN")

  if grep -qi '\baes\b' /proc/cpuinfo 2>/dev/null; then
    AES_NI=true
  else
    AES_NI=false
  fi

  if [ -s /proc/net/if_inet6 ]; then
    IPV6_SUPPORT=true
  else
    IPV6_SUPPORT=false
  fi

  IO_TMP="/tmp/auroraops_benchmark_io.$$"
  IO_LINE=$(dd if=/dev/zero of="$IO_TMP" bs=64M count=4 conv=fdatasync 2>&1 || true)
  rm -f "$IO_TMP"
  IO_AVG=$(printf '%s\n' "$IO_LINE" | awk -F',' '/copied/ {print $(NF)}' | awk '{if ($2 == "GB/s") printf "%.0f", $1 * 1024; else if ($2 == "MB/s") printf "%.0f", $1; else print 0}' | tail -1)
  IO_INT="${IO_AVG:-0}"

  LATENCY_MS="0"
  for target in 223.5.5.5 119.29.29.29 1.1.1.1; do
    LATENCY_MS=$(ping -c 3 -W 1 "$target" 2>/dev/null | awk -F'/' '/rtt|round-trip/ {printf "%.1f", $5}')
    if [ -n "$LATENCY_MS" ]; then
      break
    fi
  done
  LATENCY_MS="${LATENCY_MS:-0}"

  if [ "$IO_INT" -ge 500 ]; then
    SCORE="diamond"
  elif [ "$IO_INT" -ge 200 ]; then
    SCORE="gold"
  elif [ "$IO_INT" -ge 100 ]; then
    SCORE="silver"
  else
    SCORE="stone"
  fi

  cat >> "$REPORT_FILE" <<EOF
CPU Model: $CPU_MODEL
CPU Cores: $CPU_CORES
RAM MB: $RAM_MB
Disk GB: $DISK_GB
Virt Type: $VIRT_TYPE
AES-NI: $AES_NI
IPv6 Support: $IPV6_SUPPORT
IO: ${IO_INT}MB/s
Latency: ${LATENCY_MS}ms
Score: $SCORE
EOF
  cp "$REPORT_FILE" "$CLEAN_REPORT"

  cat <<EOF > "$OUTPUT_JSON"
{
  "geo": {
    "country": "UNKNOWN",
    "city": "UNKNOWN"
  },
  "network": {
    "latency_ms": $LATENCY_MS,
    "ipv6_support": $IPV6_SUPPORT
  },
  "hardware": {
    "cpu_model": "$CPU_MODEL",
    "cpu_cores": $CPU_CORES,
    "aes_ni": $AES_NI,
    "virt_type": "$VIRT_TYPE",
    "ram_mb": ${RAM_MB:-0},
    "disk_gb": ${DISK_GB:-0},
    "io_speed_mbps": $IO_INT,
    "score": "$SCORE"
  },
  "report_path": "$REPORT_FILE",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

  echo ""
  echo "AuroraOps Benchmark Complete (fast local):"
  echo "  CPU=$CPU_MODEL ($CPU_CORES cores) | RAM=${RAM_MB}MB | Disk=${DISK_GB}GB"
  echo "  IO=${IO_INT}MB/s (Score: $SCORE) | Latency=${LATENCY_MS}ms"
}

if [ "$MODE" = "fast" ]; then
  run_fast_benchmark
  exit 0
fi

# ── 1. Run ecs.sh ────────────────────────────────────
wget -qO /tmp/ecs.sh --no-check-certificate https://cdn.jsdelivr.net/gh/spiritLHLS/ecs@main/ecs.sh 2>/dev/null || \
  curl -sL -o /tmp/ecs.sh https://cdn.jsdelivr.net/gh/spiritLHLS/ecs@main/ecs.sh || \
  wget -qO /tmp/ecs.sh --no-check-certificate https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh 2>/dev/null || \
  curl -sL -o /tmp/ecs.sh https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh
chmod +x /tmp/ecs.sh

# Redirect all raw.githubusercontent.com downloads to jsDelivr CDN
sed -Ei 's|raw.githubusercontent.com/([^/]+)/([^/]+)/([^/]+)|cdn.jsdelivr.net/gh/\1/\2@\3|g' /tmp/ecs.sh

# Run only hardware/IO tests (-m 4 3) and routing/latency tests (-m 4 6) to save time
bash /tmp/ecs.sh -m 4 3 > "$REPORT_FILE" 2>&1 || true
bash /tmp/ecs.sh -m 4 6 >> "$REPORT_FILE" 2>&1 || true

rm -f /tmp/ecs.sh
# Strip ANSI color codes
sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g" "$REPORT_FILE" > "$CLEAN_REPORT"

# ── 2. Parse Key Metrics from Clean Report ───────────

# CPU Model (" CPU 型号          : Intel(R) Xeon(R) ...")
CPU_MODEL=$(grep -iE "^ CPU 型号|^ CPU Model" "$CLEAN_REPORT" | head -1 | awk -F':' '{print $2}' | xargs || echo "UNKNOWN")

# CPU Cores (" CPU 核心数        : 2")
CPU_CORES=$(grep -iE "^ CPU 核心数|^ CPU Cores" "$CLEAN_REPORT" | head -1 | grep -oE '[0-9]+' | head -1 || echo "0")

# Total RAM (" 内存              : 472.39 MiB / 1.92 GiB") -> Get the second part (total) and convert to MB
RAM_RAW=$(grep -iE "^ 内存|^ RAM" "$CLEAN_REPORT" | head -1 | awk -F'/' '{print $2}' | xargs || echo "0 MB")
RAM_VAL=$(echo "$RAM_RAW" | grep -oE '^[0-9.]+')
if echo "$RAM_RAW" | grep -qi "GiB\|GB"; then
  RAM_MB=$(awk "BEGIN {printf \"%.0f\", $RAM_VAL * 1024}")
else
  RAM_MB=$(awk "BEGIN {printf \"%.0f\", $RAM_VAL}")
fi

# Total Disk (" 硬盘空间          : 14.08 GiB / 118.00 GiB")
DISK_RAW=$(grep -iE "^ 硬盘空间|^ Disk" "$CLEAN_REPORT" | head -1 | awk -F'/' '{print $2}' | xargs || echo "0 GB")
DISK_GB=$(echo "$DISK_RAW" | grep -oE '^[0-9.]+')

# I/O Speed (" 1GB-1M Block           197 MB/s ...") 
# Get the read speed of 1GB-1M block, fallback to 100MB-4K block
IO_AVG=$(grep -i "1GB-1M Block" "$CLEAN_REPORT" | grep -oE '[0-9.]+ MB/s' | head -1 | grep -oE '[0-9.]+' || echo "0")
if [ "$IO_AVG" = "0" ] || [ -z "$IO_AVG" ]; then
  IO_AVG=$(grep -i "100MB-4K Block" "$CLEAN_REPORT" | grep -oE '[0-9.]+ MB/s' | head -1 | grep -oE '[0-9.]+' || echo "0")
fi

# Geo-IP / Location (" IPV4 位置         : Los Angeles / California / US")
COUNTRY=$(grep -iE "^ IPV4 位置|^ IPV4 Location|^ Location" "$CLEAN_REPORT" | head -1 | awk -F'/' '{print $NF}' | xargs || echo "UNKNOWN")
CITY=$(grep -iE "^ IPV4 位置|^ IPV4 Location|^ Location" "$CLEAN_REPORT" | head -1 | awk -F':' '{print $2}' | awk -F'/' '{print $1}' | xargs || echo "UNKNOWN")
# ── 3. Extract Advanced Hardware/Network Traits ───────
# AES-NI (" AES-NI指令集      : ✔ Enabled")
AES_NI=$(grep -iE "^ AES-NI" "$CLEAN_REPORT" | grep -iE "Enabled|✔|Yes" >/dev/null && echo "true" || echo "false")

# VM Architecture (" 虚拟化架构        : KVM")
VIRT_TYPE=$(grep -iE "^ 虚拟化架构|^ Virtualization Type|^ VM Type" "$CLEAN_REPORT" | head -1 | awk -F':' '{print $2}' | xargs || echo "UNKNOWN")

# IPv6 Support check via ASN line (" IPV6 ASN          : AS35916 MULTACOM CORPORATION")
IPV6_SUPPORT=$(grep -iE "^ IPV6 ASN" "$CLEAN_REPORT" >/dev/null && echo "true" || echo "false")

# ── 4. Calculate Global/Cross-border Latency ───────────
# Extract latency lines tested against regions of interest (e.g., China) to estimate cross-border BDP
LATENCY_RAW=$(grep -iE '联通|电信|移动|China|中国|Telecom|Unicom|Mobile' "$CLEAN_REPORT" | grep -oE '[0-9.]+\s*ms' | grep -oE '[0-9.]+' | head -n 50 || true)
if [ -n "$LATENCY_RAW" ]; then
  LATENCY_MS=$(echo "$LATENCY_RAW" | awk '{sum+=$1; cnt++} END {if(cnt>0) printf "%.1f", sum/cnt; else print "0"}')
else
  LATENCY_MS="0"
fi

# ── 4. Classify Hardware ─────────────────────────────
IO_INT="${IO_AVG%%.*}"
IO_INT="${IO_INT:-0}"
if [ "$IO_INT" -ge 500 ]; then
  SCORE="diamond"
elif [ "$IO_INT" -ge 200 ]; then
  SCORE="gold"
elif [ "$IO_INT" -ge 100 ]; then
  SCORE="silver"
else
  SCORE="stone"
fi

# ── 4. Generate Fact JSON ────────────────────────────
cat <<EOF > "$OUTPUT_JSON"
{
  "geo": {
    "country": "$COUNTRY",
    "city": "$CITY"
  },
  "network": {
    "latency_ms": $LATENCY_MS,
    "ipv6_support": $IPV6_SUPPORT
  },
  "hardware": {
    "cpu_model": "$CPU_MODEL",
    "cpu_cores": $CPU_CORES,
    "aes_ni": $AES_NI,
    "virt_type": "$VIRT_TYPE",
    "ram_mb": ${RAM_MB:-0},
    "disk_gb": ${DISK_GB:-0},
    "io_speed_mbps": $IO_INT,
    "score": "$SCORE"
  },
  "report_path": "$REPORT_FILE",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

echo ""
echo "AuroraOps Benchmark Complete (via 融合怪):"
echo "  CPU=$CPU_MODEL ($CPU_CORES cores) | RAM=${RAM_MB}MB | Disk=${DISK_GB}GB"
echo "  IO=${IO_INT}MB/s (Score: $SCORE) | Latency=${LATENCY_MS}ms | Country=$COUNTRY"
