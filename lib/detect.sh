#!/usr/bin/env bash
cmd() { command -v "$1" >/dev/null 2>&1; }
first_line() { head -n1; }
detect_all() {
  info "Detectando hardware (somente leitura)..."
  detect_cpu; detect_gpu; detect_memory; detect_storage; detect_network; detect_wifi; detect_bluetooth
  detect_machine; detect_monitors; detect_virtualization; detect_boot; detect_audio; detect_display_manager; detect_system
  show_hardware
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
