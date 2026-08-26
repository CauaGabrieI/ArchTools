#!/usr/bin/env bash

archtools_reset_plan() {
  PLAN_PACKAGES=(); PLAN_OPTIONAL_PACKAGES=(); PLAN_SERVICES_ENABLE=(); PLAN_SERVICES_CONFIGURED=(); PLAN_SERVICES_DISABLE=(); PLAN_NOTES=(); PLAN_FILES=()
}

archtools_detect_module() {
  case "$1" in
    hardware) detect_all ;;
    drivers) detect_cpu; detect_gpu; detect_virtualization ;;
    diagnostics) detect_all ;;
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
    drivers) printf '\nDrivers\n  CPU: %s (%s)\n  GPU(s): %s\n' "${HARDWARE[cpu_vendor]:-desconhecido}" "${HARDWARE[cpu_microcode]:-nenhum}" "${HARDWARE[gpus]:-não detectada}" ;;
    diagnostics) printf '\nDiagnóstico\n'; for command_name in bash pacman sudo systemctl lspci lsblk findmnt; do if command -v "$command_name" >/dev/null 2>&1; then printf '  %s: disponível\n' "$command_name"; else printf '  %s: ausente\n' "$command_name"; fi; done ;;
  esac
}

archtools_build_module_plan() {
  local module=$1 choice=${2:-}
  archtools_reset_plan
  case "$module" in
    cpu) plan_firmware; [[ ${HARDWARE[cpu_microcode]:-} != none ]] && plan_package "${HARDWARE[cpu_microcode]}" ;;
    gpu) [[ ${HARDWARE[gpu_amd]:-0} == 1 ]] && plan_amd_driver; [[ ${HARDWARE[gpu_intel]:-0} == 1 ]] && plan_intel_driver; [[ ${HARDWARE[gpu_nvidia]:-0} == 1 ]] && plan_nvidia_driver ;;
    drivers) driver_packages ;;
    storage) [[ ${HARDWARE[trim]:-0} == 1 ]] && add_service fstrim.timer ;;
    network) network_plan ;;
    bluetooth) bluetooth_plan ;;
    audio) audio_plan ;;
    desktop) [[ $choice =~ ^(gnome|kde|xfce|cinnamon|hyprland|minimal)$ ]] || die "Desktop inválido: $choice"; "desktop_$choice" ;;
    gaming) PROFILE=gaming; profile_gaming; driver_packages ;;
    hardware) return 0 ;;
    diagnostics) return 0 ;;
    *) die "Ferramenta desconhecida: $module" ;;
  esac
  PLAN_NOTES+=("Somente alterações deste módulo serão executadas.")
}

archtools_show_module_plan() {
  printf '\nPlano da ferramenta: %s\n' "$1"
  ((${#PLAN_PACKAGES_INSTALLED[@]})) && printf '  Já instalados: %s\n' "${PLAN_PACKAGES_INSTALLED[*]}"
  ((${#PLAN_PACKAGES_AVAILABLE[@]})) && printf '  Disponíveis: %s\n' "${PLAN_PACKAGES_AVAILABLE[*]}"
  ((${#PLAN_PACKAGES_UNAVAILABLE[@]})) && printf '  Indisponíveis: %s\n' "${PLAN_PACKAGES_UNAVAILABLE[*]}"
  ((${#PLAN_PACKAGES_OPTIONAL_SKIPPED[@]})) && printf '  Opcionais ignorados: %s\n' "${PLAN_PACKAGES_OPTIONAL_SKIPPED[*]}"
  ((${#PLAN_PACKAGES[@]})) || printf '  Pacotes: nenhum\n'
  ((${#PLAN_SERVICES_ENABLE[@]})) && printf '  Serviços: %s\n' "${PLAN_SERVICES_ENABLE[*]}" || printf '  Serviços: nenhum\n'
  printf '  Garantias: nenhum disco, bootloader, AUR, reboot ou ajuste agressivo será alterado.\n'
}

archtools_tool_usage() {
  printf 'Uso: ./tools/%s.sh [opções]\n  --dry-run  --yes  --verbose  --help\n' "$1"
}

archtools_usage() {
  cat <<'EOF'
Uso: ./archtools <comando> [subcomando] [opções]

Comandos:
  install [opções]                 Executa o fluxo completo existente
  preflight [--verbose]            Verifica pré-requisitos sem alterar o sistema
  doctor [--verbose]               Audita sistema e estado sem fazer alterações
  module list                      Lista módulos registrados
  module info <nome>               Mostra metadados de um módulo
  hardware detect [opções]         Detecta e mostra hardware
  diagnostics run [opções]         Verifica ambiente e mostra diagnóstico
  drivers detect                   Detecta CPU/GPU para drivers
  drivers install [opções]         Planeja e instala drivers após confirmação
  profile <nome> [opções]          Executa um perfil existente
  desktop-apps suggest [opções]    Sugere componentes sem alterar o sistema
  desktop-apps install <lista>     Planeja/instala componentes selecionados

Opções: --dry-run  --yes  --verbose  --help
EOF
}

archtools_cli_main() {
  local command_name=${1:-help} subcommand profile_name
  shift || true
  case "$command_name" in
    install) main "$@" ;;
    preflight) preflight_run "$@" ;;
    doctor) doctor_run "$@" ;;
    hardware|diagnostics|drivers)
      subcommand=${1:-}
      [[ -n $subcommand ]] && shift
      case "$command_name:$subcommand" in
        hardware:detect) archtools_tool_main hardware "$@" ;;
        diagnostics:run) archtools_tool_main diagnostics "$@" ;;
        drivers:detect) DETECT_ONLY=1 archtools_tool_main drivers "$@" ;;
        drivers:install) archtools_tool_main drivers "$@" ;;
        *) die "Uso inválido para '$command_name'. Use ./archtools --help." ;;
      esac
      ;;
    profile)
      profile_name=${1:-}; [[ -n $profile_name ]] || die "Perfil ausente. Use minimal, desktop ou gaming."
      shift; main --profile "$profile_name" "$@" ;;
    module)
      subcommand=${1:-}; [[ -n $subcommand ]] || die "Subcomando module ausente. Use list ou info."
      shift
      case "$subcommand" in
        list) (($# == 0)) || die "module list não aceita argumentos."; module_list ;;
        info) [[ $# == 1 ]] || die "Uso: ./archtools module info <nome>"; module_info "$1" ;;
        *) die "Subcomando module inválido: $subcommand" ;;
      esac
      ;;
    desktop-apps) desktop_apps_cli_main "$@" ;;
    help|-h|--help) archtools_usage ;;
    *) die "Comando inválido: $command_name. Use ./archtools --help." ;;
  esac
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
  if [[ $module == hardware || $module == diagnostics || ${DETECT_ONLY:-0} == 1 ]]; then READ_ONLY_ACTION=1; fi
  init_logger
  require_supported_system
  archtools_detect_module "$module"
  archtools_show_module "$module"
  [[ $module == hardware || $module == diagnostics || ${DETECT_ONLY:-0} == 1 ]] && return 0
  archtools_build_module_plan "$module" "$choice"
  local plan_status=0
  validate_plan_pre_execution || plan_status=$?
  archtools_show_module_plan "$module"
  (( plan_status == 0 )) || { log ERROR "Plano inválido; nenhuma alteração foi executada."; trap - ERR; return "$plan_status"; }
  (( DRY_RUN )) && { log INFO "Dry-run concluído: nenhuma alteração foi feita nem estado persistente criado."; return 0; }
  confirm_plan || { log INFO "Cancelado pelo usuário."; return 0; }
  begin_transaction "$module"
  if ! execute_plan; then transaction_abort_and_rollback "falha durante a execução do módulo"; return 1; fi
  if ! validate_plan; then transaction_abort_and_rollback "falha na validação final do módulo"; return 1; fi
  commit_transaction
}
