#!/usr/bin/env bash
cmd() { command -v "$1" >/dev/null 2>&1; }
first_line() { head -n1; }
detect_all() {
  debug "Detectando hardware (somente leitura)..."
  detect_cpu; detect_gpu; detect_memory; detect_storage; detect_network; detect_wifi; detect_bluetooth
  detect_machine; detect_monitors; detect_virtualization; detect_boot; detect_audio; detect_display_manager; detect_system
}
detect_display_manager() {
  local dm
  HARDWARE[display_manager]=none
  for dm in gdm.service sddm.service lightdm.service; do
    if systemctl is-enabled "$dm" >/dev/null 2>&1; then HARDWARE[display_manager]=$dm; return; fi
  done
}
detect_system() { HARDWARE[kernel]=$(uname -r); HARDWARE[arch]=$(uname -m); HARDWARE[desktop]="${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-none}}"; HARDWARE[network_manager]=$(systemctl is-active NetworkManager 2>/dev/null || true); }
show_hardware() { cat <<EOF

Hardware detectado
  CPU:      ${HARDWARE[cpu_model]:-desconhecida} (${HARDWARE[cpu_vendor]:-OTHER})
  GPU(s):   ${HARDWARE[gpus]:-não detectada}
  RAM:      ${HARDWARE[ram_total]:-desconhecida}
  Storage:  ${HARDWARE[storage_summary]:-desconhecido}
  Rede:     ${HARDWARE[network]:-nenhuma}
  Bluetooth:${HARDWARE[bluetooth]:-não detectado}
  Sistema:  ${HARDWARE[machine]:-UNKNOWN}; Boot: ${HARDWARE[boot]:-desconhecido}
  Kernel:   ${HARDWARE[kernel]:-desconhecido}; Arquitetura: ${HARDWARE[arch]:-desconhecida}
EOF
}

summarize_gpus() {
  local raw=${1:-} item summary=''
  local -a gpu_lines=()
  [[ -n $raw ]] || { printf 'não detectada'; return; }
  IFS=';' read -ra gpu_lines <<< "$raw"
  for item in "${gpu_lines[@]}"; do
    item=$(sed -E \
      -e 's/^[[:space:]]*([[:xdigit:]]{4}:)?[[:xdigit:]]{2}:[[:xdigit:]]{2}\.[[:xdigit:]][[:space:]]+//' \
      -e 's/^(VGA compatible controller|3D controller|Display controller)( \[[[:xdigit:]]{4}\])?:[[:space:]]*//' \
      -e 's/[[:space:]]+\[[[:xdigit:]]{4}:[[:xdigit:]]{4}\]//g' \
      -e 's/[[:space:]]+\(rev [[:xdigit:]]+\)$//' \
      -e 's/^Advanced Micro Devices, Inc\. \[AMD\/ATI\][[:space:]]+/AMD /' \
      -e 's/^Intel Corporation[[:space:]]+/Intel /' \
      -e 's/^NVIDIA Corporation[[:space:]]+/NVIDIA /' \
      -e 's/^InnoTek Systemberatung GmbH[[:space:]]+//' \
      -e 's/^AMD [^[]+[[:space:]]+\[([^]]+)\]$/AMD \1/' <<< "$item")
    [[ -n $summary ]] && summary+='; '
    summary+=$item
  done
  printf '%s' "${summary:-não detectada}"
}

show_hardware_summary() {
  ui_section 'Hardware'
  ui_key_value 'CPU' "${HARDWARE[cpu_model]:-desconhecida}"
  ui_key_value 'GPU' "$(summarize_gpus "${HARDWARE[gpus]:-}")"
  ui_key_value 'RAM' "${HARDWARE[ram_total]:-desconhecida}"
}
