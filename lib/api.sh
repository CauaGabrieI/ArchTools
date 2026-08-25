#!/usr/bin/env bash

archtools_reset_plan() {
  PLAN_PACKAGES=(); PLAN_SERVICES_ENABLE=(); PLAN_SERVICES_DISABLE=(); PLAN_NOTES=(); PLAN_FILES=()
}

archtools_detect_module() {
  case "$1" in
    hardware) detect_all ;;
    cpu) detect_cpu; detect_virtualization; HARDWARE[arch]=$(uname -m);;
    gpu) detect_gpu ;;
    storage) detect_storage ;;
    network) detect_network; detect_system ;;
    bluetooth) detect_bluetooth ;;
    audio) detect_audio ;;
    desktop|gaming) detect_system; detect_display_manager ;;
    *) die "Ferramenta desconhecida: $1" ;;
  esac
}

archtools_show_module() {
  case "$1" in
    hardware) show_hardware ;;
    cpu) printf '\nCPU\n  Fabricante: %s\n  Modelo: %s\n  Arquitetura: %s\n  Cores: %s\n  Threads: %s\n  Virtualização: %s\n  Microcode recomendado: %s\n' \
      "${HARDWARE[cpu_vendor]:-desconhecido}" "${HARDWARE[cpu_model]:-desconhecido}" \
      "${HARDWARE[arch]:-desconhecida}" "${HARDWARE[cpu_cores]:-desconhecido}" \
      "${HARDWARE[cpu_threads]:-desconhecido}" "${HARDWARE[cpu_virtualization]:-não detectada}" \
      "${HARDWARE[cpu_microcode]:-nenhum}" ;;
    gpu) printf '\nGPU\n  Detectadas: %s\n  Fabricante(s): AMD=%s Intel=%s NVIDIA=%s\n  Driver/renderizador em uso: %s\n  Vulkan: %s\n' \
      "${HARDWARE[gpus]:-nenhuma}" "${HARDWARE[gpu_amd]:-0}" "${HARDWARE[gpu_intel]:-0}" \
      "${HARDWARE[gpu_nvidia]:-0}" "${HARDWARE[opengl]:-não disponível}" "${HARDWARE[vulkan]:-não disponível}" ;;
    storage) printf '\nStorage\n  Dispositivos: %s\n  Root device: %s\n  Filesystem: %s\n  TRIM elegível: %s\n' \
      "${HARDWARE[storage_summary]:-nenhum}" "${HARDWARE[root_device]:-desconhecido}" \
      "${HARDWARE[root_fs]:-desconhecido}" "${HARDWARE[trim]:-0}" ;;
    network) printf '\nRede\n  Interfaces: %s\n  NetworkManager: %s\n' "${HARDWARE[network]:-nenhuma}" "${HARDWARE[network_manager]:-desconhecido}" ;;
    bluetooth) printf '\nBluetooth\n  Hardware: %s\n  Ferramentas: %s\n' "${HARDWARE[bluetooth]:-não detectado}" "${HARDWARE[bluetooth_software]:-false}" ;;
    audio) printf '\nÁudio\n  Pilha atual: %s\n' "${HARDWARE[audio]:-desconhecida}" ;;
    desktop) printf '\nDesktop\n  Atual: %s\n' "${HARDWARE[desktop]:-desconhecido}" ;;
    gaming) printf '\nGaming\n  GPU: %s\n' "${HARDWARE[gpus]:-não detectada}" ;;
  esac
}

archtools_build_module_plan() {
  local module=$1 choice=${2:-}
  archtools_reset_plan
  case "$module" in
    cpu) plan_firmware; [[ ${HARDWARE[cpu_microcode]:-} != none ]] && plan_package "${HARDWARE[cpu_microcode]}" ;;
    gpu) [[ ${HARDWARE[gpu_amd]:-0} == 1 ]] && plan_amd_driver; [[ ${HARDWARE[gpu_intel]:-0} == 1 ]] && plan_intel_driver; [[ ${HARDWARE[gpu_nvidia]:-0} == 1 ]] && plan_nvidia_driver ;;
    storage) [[ ${HARDWARE[trim]:-0} == 1 ]] && add_service fstrim.timer ;;
    network) network_plan ;;
    bluetooth) bluetooth_plan ;;
    audio) audio_plan ;;
    desktop) [[ $choice =~ ^(gnome|kde|xfce|cinnamon|hyprland|minimal)$ ]] || die "Desktop inválido: $choice"; "desktop_$choice" ;;
    gaming) PROFILE=gaming; profile_gaming; driver_packages ;;
    hardware) return 0 ;;
    *) die "Ferramenta desconhecida: $module" ;;
  esac
  PLAN_NOTES+=("Somente alterações deste módulo serão executadas.")
}

archtools_show_module_plan() {
  printf '\nPlano da ferramenta: %s\n' "$1"
  ((${#PLAN_PACKAGES[@]})) && printf '  Pacotes: %s\n' "${PLAN_PACKAGES[*]}" || printf '  Pacotes: nenhum\n'
  ((${#PLAN_SERVICES_ENABLE[@]})) && printf '  Serviços: %s\n' "${PLAN_SERVICES_ENABLE[*]}" || printf '  Serviços: nenhum\n'
  printf '  Garantias: nenhum disco, bootloader, AUR, reboot ou ajuste agressivo será alterado.\n'
}

archtools_tool_usage() {
  printf 'Uso: ./tools/%s.sh [opções]\n  --dry-run  --yes  --verbose  --help\n' "$1"
}

archtools_tool_main() {
  local module=$1 choice=""; shift
  if [[ $module == desktop ]]; then choice=${1:-}; shift || true; fi
  while (($#)); do
    case "$1" in
      --dry-run) DRY_RUN=1; shift;; --yes) ASSUME_YES=1; shift;; --verbose) VERBOSE=1; shift;;
      --help|-h) archtools_tool_usage "$module"; return 0;;
      *) die "Opção inválida: $1. Use --help.";;
    esac
  done
  init_logger
  require_supported_system
  archtools_detect_module "$module"
  archtools_show_module "$module"
  [[ $module == hardware ]] && return 0
  archtools_build_module_plan "$module" "$choice"
  archtools_show_module_plan "$module"
  (( DRY_RUN )) && { log INFO "Dry-run concluído: nenhuma alteração foi feita nem estado persistente criado."; return 0; }
  confirm_plan || { log INFO "Cancelado pelo usuário."; return 0; }
  init_state; execute_plan; validate_plan; save_tool_run "$module"
}