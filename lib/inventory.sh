#!/usr/bin/env bash

INVENTORY_VERSION=1

inventory_sanitize() {
  local value=${1:-}
  value=${value//$'\t'/ }; value=${value//$'\n'/ }; value=${value//$'\r'/ }
  printf '%s' "$value"
}

inventory_hardware_rows() {
  local detected_at=${1:-$(date -Is)}
  printf 'inventory_version\t%s\n' "$INVENTORY_VERSION"
  printf 'detected_at\t%s\n' "$(inventory_sanitize "$detected_at")"
  printf 'architecture\t%s\n' "$(inventory_sanitize "${HARDWARE[arch]:-unknown}")"
  printf 'machine\t%s\n' "$(inventory_sanitize "${HARDWARE[machine]:-UNKNOWN}")"
  printf 'hardware_profile_detected\t%s\n' "$(inventory_sanitize "${HARDWARE_PROFILE_DETECTED:-unknown}")"
  printf 'cpu_vendor\t%s\n' "$(inventory_sanitize "${HARDWARE[cpu_vendor]:-OTHER}")"
  printf 'cpu_model\t%s\n' "$(inventory_sanitize "${HARDWARE[cpu_model]:-unknown}")"
  printf 'cpu_cores\t%s\n' "$(inventory_sanitize "${HARDWARE[cpu_cores]:-unknown}")"
  printf 'cpu_threads\t%s\n' "$(inventory_sanitize "${HARDWARE[cpu_threads]:-unknown}")"
  printf 'gpus\t%s\n' "$(inventory_sanitize "${HARDWARE[gpus]:-unknown}")"
  printf 'gpu_amd\t%s\n' "$(inventory_sanitize "${HARDWARE[gpu_amd]:-0}")"
  printf 'gpu_intel\t%s\n' "$(inventory_sanitize "${HARDWARE[gpu_intel]:-0}")"
  printf 'gpu_nvidia\t%s\n' "$(inventory_sanitize "${HARDWARE[gpu_nvidia]:-0}")"
  printf 'virtualization\t%s\n' "$(inventory_sanitize "${HARDWARE[virtualization]:-none}")"
  printf 'memory_total\t%s\n' "$(inventory_sanitize "${HARDWARE[ram_total]:-unknown}")"
  printf 'storage_summary\t%s\n' "$(inventory_sanitize "${HARDWARE[storage_summary]:-unknown}")"
  printf 'root_device\t%s\n' "$(inventory_sanitize "${HARDWARE[root_device]:-unknown}")"
  printf 'root_filesystem\t%s\n' "$(inventory_sanitize "${HARDWARE[root_fs]:-unknown}")"
  printf 'trim_supported\t%s\n' "$(inventory_sanitize "${HARDWARE[trim]:-0}")"
  printf 'network_summary\t%s\n' "$(inventory_sanitize "${HARDWARE[network]:-none}")"
  printf 'bluetooth_detected\t%s\n' "$(inventory_sanitize "${HARDWARE[bluetooth_hardware]:-false}")"
  printf 'audio_stack\t%s\n' "$(inventory_sanitize "${HARDWARE[audio]:-unknown}")"
  printf 'desktop_detected\t%s\n' "$(inventory_sanitize "${HARDWARE[desktop]:-none}")"
  printf 'display_manager\t%s\n' "$(inventory_sanitize "${HARDWARE[display_manager]:-none}")"
}

inventory_fingerprint_input() {
  printf 'inventory_version=%s\n' "$INVENTORY_VERSION"
  printf 'architecture=%s\n' "${HARDWARE[arch]:-unknown}"
  printf 'machine=%s\n' "${HARDWARE[machine]:-UNKNOWN}"
  printf 'hardware_profile=%s\n' "${HARDWARE_PROFILE_DETECTED:-unknown}"
  printf 'cpu_vendor=%s\n' "${HARDWARE[cpu_vendor]:-OTHER}"
  printf 'cpu_model=%s\n' "${HARDWARE[cpu_model]:-unknown}"
  printf 'gpus=%s\n' "${HARDWARE[gpus]:-unknown}"
  printf 'gpu_amd=%s\n' "${HARDWARE[gpu_amd]:-0}"
  printf 'gpu_intel=%s\n' "${HARDWARE[gpu_intel]:-0}"
  printf 'gpu_nvidia=%s\n' "${HARDWARE[gpu_nvidia]:-0}"
  printf 'virtualization=%s\n' "${HARDWARE[virtualization]:-none}"
}

inventory_fingerprint() { inventory_fingerprint_input | sha256sum | awk '{print $1}'; }

inventory_save() {
  local inventory_dir="$STATE_DIR/inventory" detected_at fingerprint
  (( ${DRY_RUN:-0} == 0 )) || return 0
  [[ ${ACTION:-install} == install ]] || return 0
  init_state
  mkdir -p "$inventory_dir"; chmod 700 "$inventory_dir"
  detected_at=$(date -Is)
  inventory_hardware_rows "$detected_at" | atomic_write "$inventory_dir/hardware.tsv"
  fingerprint=$(inventory_fingerprint)
  printf '%s\n' "$fingerprint" | atomic_write "$inventory_dir/fingerprint"
}
