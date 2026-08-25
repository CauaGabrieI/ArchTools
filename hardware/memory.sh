#!/usr/bin/env bash
detect_memory() {
  local meminfo=${MEMINFO_FILE:-/proc/meminfo}
  HARDWARE[ram_total]=$(LC_ALL=C awk '$1=="MemTotal:" {printf "%.1fGi", $2/1048576}' "$meminfo" 2>/dev/null || true)
  HARDWARE[ram_available]=$(LC_ALL=C awk '$1=="MemAvailable:" {printf "%.1fGi", $2/1048576}' "$meminfo" 2>/dev/null || true)
}
