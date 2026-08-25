#!/usr/bin/env bash
detect_cpu() {
  local data vendor
  data=$(lscpu 2>/dev/null || true); vendor=$(awk -F: '/Vendor ID:/ {gsub(/^[[:space:]]+/,"",$2);print $2;exit}' <<<"$data")
  case "$vendor" in AuthenticAMD) HARDWARE[cpu_vendor]=AMD;; GenuineIntel) HARDWARE[cpu_vendor]=INTEL;; *) HARDWARE[cpu_vendor]=OTHER;; esac
  HARDWARE[cpu_model]=$(awk -F: '/Model name:/ {gsub(/^[[:space:]]+/,"",$2);print $2;exit}' <<<"$data")
  local cores_per_socket sockets
  HARDWARE[cpu_threads]=$(awk -F: '/^CPU\(s\):/ {gsub(/^[[:space:]]+/,"",$2);print $2;exit}' <<<"$data")
  cores_per_socket=$(awk -F: '/Core\(s\) per socket:/ {gsub(/^[[:space:]]+/,"",$2);print $2;exit}' <<<"$data")
  sockets=$(awk -F: '/Socket\(s\):/ {gsub(/^[[:space:]]+/,"",$2);print $2;exit}' <<<"$data")
  if [[ $cores_per_socket =~ ^[0-9]+$ && $sockets =~ ^[0-9]+$ ]]; then
    HARDWARE[cpu_cores]=$((cores_per_socket * sockets))
  else
    HARDWARE[cpu_cores]=unknown
  fi
  HARDWARE[cpu_virtualization]=$(awk -F: '/Virtualization:/ {gsub(/^[[:space:]]+/,"",$2);print $2;exit}' <<<"$data")
  case "${HARDWARE[cpu_vendor]}" in AMD) HARDWARE[cpu_microcode]=amd-ucode;; INTEL) HARDWARE[cpu_microcode]=intel-ucode;; *) HARDWARE[cpu_microcode]=none;; esac
}
