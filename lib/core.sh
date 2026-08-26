#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR=${PROJECT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}
APP_NAME="Arch Linux Smart Post-Install"
APP_ID="arch-smart-postinstall"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/$APP_ID"
LOG_DIR="$PROJECT_DIR/logs"
RUN_ID=$(date +%F_%H-%M-%S-%N)
LOG_FILE=""
DRY_RUN=0; VERBOSE=0; NO_REBOOT=0; ASSUME_YES=0; READ_ONLY_ACTION=0
DESKTOP=""; PROFILE=""; USAGE_PROFILE=""; HARDWARE_PROFILE="auto"; HARDWARE_PROFILE_EXPLICIT=0; DESKTOP_COMPONENTS_SPEC=""; ACTION="install"
declare -a PLAN_PACKAGES=() PLAN_OPTIONAL_PACKAGES=() PLAN_SERVICES_ENABLE=() PLAN_SERVICES_CONFIGURED=() PLAN_SERVICES_DISABLE=() PLAN_NOTES=() PLAN_FILES=()
declare -A HARDWARE=()

on_error() {
  local code=$? line=$1 cmd=$2
  trap - ERR
  if [[ ${TRANSACTION_STATUS:-} == active ]]; then
    abort_transaction "erro inesperado na linha $line" || true
    rollback_transaction || true
  fi
  release_state_lock || true
  log ERROR "Module: ${BASH_SOURCE[1]#$PROJECT_DIR/}; Line: $line; Command: $cmd; exit: $code"
  printf '\n[ERROR] Falha na linha %s%s\n' "$line" "${LOG_FILE:+. Consulte: $LOG_FILE}" >&2
  exit "$code"
}
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

load_modules() {
  local module
  for module in logger state transaction detect packages backup rollback desktop-components doctor inventory profiles planner executor validator ui cli modules preflight api; do
    # shellcheck source=/dev/null
    source "$PROJECT_DIR/lib/$module.sh"
  done
  for module in "$PROJECT_DIR"/hardware/*.sh "$PROJECT_DIR"/drivers/*.sh "$PROJECT_DIR"/desktop/*.sh "$PROJECT_DIR"/services/*.sh; do
    # shellcheck source=/dev/null
    source "$module"
  done
  for module in desktop notebook server vm; do source "$PROJECT_DIR/profiles/hardware/$module.sh"; done
  for module in minimal desktop gaming development server; do source "$PROJECT_DIR/profiles/usage/$module.sh"; done
  module_registry_init
}

require_supported_system() {
  if ! command -v pacman >/dev/null 2>&1; then
    die "Distribuição não suportada: pacman não encontrado. Este projeto suporta Arch Linux e compatíveis."
  fi
  local os_release=${OS_RELEASE_FILE:-/etc/os-release} os_id os_like
  [[ -r $os_release ]] || die "Unsupported distribution: /etc/os-release não está disponível."
  os_id=$(awk -F= '$1=="ID" {gsub(/"/,"",$2); print tolower($2)}' "$os_release")
  os_like=$(awk -F= '$1=="ID_LIKE" {gsub(/"/,"",$2); print tolower($2)}' "$os_release")
  [[ $os_id == arch || " $os_like " == *' arch '* ]] || die "Unsupported distribution. This project supports Arch Linux and explicit Arch-compatible distributions."
}

main() {
  parse_cli "$@"
  [[ $ACTION == help ]] && { usage; return; }
  if [[ $ACTION == list-changes ]]; then
    LOG_FILE=""
    [[ -d $STATE_DIR ]] && list_changes || printf 'Nenhum estado persistente encontrado.\n'
    return
  fi
  case "$ACTION" in
    rollback) init_logger; init_state; rollback_run ;;
    uninstall) init_logger; init_state; uninstall_run ;;
    *)
      if [[ $ACTION == detect-only ]]; then init_logger; require_supported_system; fi
      run_install_flow
      ;;
  esac
}

startup_health_check() {
  printf 'ArchTools startup\n'
  if doctor_run >/dev/null; then
    if (( DOCTOR_WARN )); then printf '[WARN] Doctor: %d aviso(s); continuando.\n' "$DOCTOR_WARN"
    else printf '[OK] Doctor\n'; fi
    return 0
  fi
  printf '[FAIL] ArchTools health check\nExecute:\n  ./archtools doctor --verbose\n' >&2
  return 1
}

startup_prepare() {
  startup_health_check || return 1
  archtools_detect_module hardware
  printf '[OK] Hardware detected\n'
  detect_hardware_profile
  printf '[OK] Machine profile: %s\n' "$HARDWARE_PROFILE_DETECTED"
  (( DRY_RUN )) || inventory_save
}

run_install_flow() {
  banner
  if [[ $ACTION == detect-only ]]; then archtools_detect_module hardware; show_hardware; return; fi
  startup_prepare || return 1
  show_hardware
  select_interactively_if_needed
  init_logger
  if [[ $USAGE_PROFILE != minimal && $USAGE_PROFILE != server ]]; then desktop_components_interactive_select "$DESKTOP"; fi
  build_plan "$DESKTOP" "$USAGE_PROFILE"
  desktop_components_plan "$DESKTOP" "${DESKTOP_COMPONENTS_SPEC:-none}"
  local plan_status=0
  validate_plan_pre_execution || plan_status=$?
  show_plan
  (( plan_status == 0 )) || { log ERROR "Plano inválido; nenhuma alteração foi executada."; trap - ERR; return "$plan_status"; }
  if (( DRY_RUN )); then log INFO "Dry-run concluído: nenhuma alteração foi feita nem arquivo persistente criado."; return; fi
  confirm_plan || { log INFO "Cancelado pelo usuário."; return; }
  begin_transaction install
  if ! execute_plan; then transaction_abort_and_rollback "falha durante a execução"; return 1; fi
  if ! validate_plan; then transaction_abort_and_rollback "falha na validação final"; return 1; fi
  commit_transaction
  show_report
}
