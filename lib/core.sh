#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR=${PROJECT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}
APP_NAME="Arch Linux Smart Post-Install"
APP_ID="arch-smart-postinstall"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/$APP_ID"
LOG_DIR="$PROJECT_DIR/logs"
RUN_ID=$(date +%F_%H-%M-%S)
LOG_FILE="$LOG_DIR/install-$RUN_ID.log"
DRY_RUN=0; VERBOSE=0; NO_REBOOT=0; ASSUME_YES=0
DESKTOP=""; PROFILE=""; ACTION="install"
declare -a PLAN_PACKAGES=() PLAN_SERVICES_ENABLE=() PLAN_SERVICES_DISABLE=() PLAN_NOTES=() PLAN_FILES=()
declare -A HARDWARE=()

on_error() {
  local code=$? line=$1 cmd=$2
  log ERROR "Module: ${BASH_SOURCE[1]#$PROJECT_DIR/}; Line: $line; Command: $cmd; exit: $code"
  printf '\n[ERROR] Falha na linha %s. Consulte: %s\n' "$line" "$LOG_FILE" >&2
  exit "$code"
}
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

load_modules() {
  local module
  for module in logger state detect packages backup rollback planner executor validator ui cli; do
    # shellcheck source=/dev/null
    source "$PROJECT_DIR/lib/$module.sh"
  done
  for module in "$PROJECT_DIR"/hardware/*.sh "$PROJECT_DIR"/drivers/*.sh "$PROJECT_DIR"/desktop/*.sh "$PROJECT_DIR"/profiles/*.sh "$PROJECT_DIR"/services/*.sh; do
    # shellcheck source=/dev/null
    source "$module"
  done
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
  init_logger
  case "$ACTION" in
    rollback) init_state; rollback_run ;;
    uninstall) init_state; uninstall_run ;;
    list-changes) init_state; list_changes ;;
    *) require_supported_system; run_install_flow ;;
  esac
}

run_install_flow() {
  banner
  detect_all
  [[ $ACTION == detect-only ]] && { show_hardware; return; }
  select_interactively_if_needed
  build_plan "$DESKTOP" "$PROFILE"
  show_plan
  if (( DRY_RUN )); then log INFO "Dry-run concluído: nenhuma alteração foi feita nem arquivo persistente criado."; return; fi
  confirm_plan || { log INFO "Cancelado pelo usuário."; return; }
  init_state
  execute_plan
  validate_plan
  save_last_run "$DESKTOP" "$PROFILE"
  show_report
}
