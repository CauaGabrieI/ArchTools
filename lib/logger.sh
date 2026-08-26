#!/usr/bin/env bash
init_logger() {
  if (( DRY_RUN || READ_ONLY_ACTION )) || [[ ${ACTION:-} == detect-only ]]; then LOG_FILE=""; return; fi
  LOG_FILE="$LOG_DIR/install-$RUN_ID.log"
  mkdir -p "$LOG_DIR"; touch "$LOG_FILE"
}
log() {
  local level=$1; shift
  [[ -z ${LOG_FILE:-} ]] || printf '[%s] [%s] %s\n' "$(date '+%F %T')" "$level" "$*" >> "$LOG_FILE"
  case "$level" in
    ERROR) if declare -F ui_error >/dev/null; then ui_error "$*"; else printf '[ERROR] %s\n' "$*" >&2; fi ;;
    WARN) if declare -F ui_warn >/dev/null; then ui_warn "$*"; else printf '[WARN] %s\n' "$*"; fi ;;
    DEBUG) (( ${VERBOSE:-0} )) && { if declare -F ui_info >/dev/null; then ui_info "$*"; else printf '[DEBUG] %s\n' "$*"; fi; } || true ;;
    *) if declare -F ui_info >/dev/null; then ui_info "$*"; else printf '[INFO] %s\n' "$*"; fi ;;
  esac
}
info() { log INFO "$*"; }; warn() { log WARN "$*"; }; die() { log ERROR "$*"; exit 1; }
debug() { (( VERBOSE )) && log DEBUG "$*" || true; }
