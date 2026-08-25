#!/usr/bin/env bash
detect_cpu() {
  local data vendor
  data=$(lscpu 2>/dev/null || true); vendor=$(awk -F: '/Vendor ID:/ {gsub(/^[[:space:]]+/,"",$2);print $2;exit}' <<<"$data")
  case "$vendor" in AuthenticAMD) HARDWARE[cpu_vendor]=AMD;; GenuineIntel) HARDWARE[cpu_vendor]=INTEL;; *) HARDWARE[cpu_vendor]=OTHER;; esac
  HARDWARE[cpu_model]=$(awk -F: '/Model name:/ {gsub(/^[[:space:]]+/,"",$2);print $2;exit}' <<<"$data")
  HARDWARE[cpu_cores]=$(awk -F: '/^CPU\(s\):/ {gsub(/^[[:space:]]+/,"",$2);print $2;exit}' <<<"$data")
  HARDWARE[cpu_virtualization]=$(awk -F: '/Virtualization:/ {gsub(/^[[:space:]]+/,"",$2);print $2;exit}' <<<"$data")
}
