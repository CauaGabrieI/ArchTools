#!/usr/bin/env bash
init_logger() {
  if (( DRY_RUN )); then LOG_FILE=""; return; fi
  mkdir -p "$LOG_DIR"; touch "$LOG_FILE"
}
log() { local level=$1; shift; if [[ -n ${LOG_FILE:-} ]]; then printf '[%s] [%s] %s\n' "$(date '+%F %T')" "$level" "$*" | tee -a "$LOG_FILE"; else printf '[%s] [%s] %s\n' "$(date '+%F %T')" "$level" "$*"; fi; }
info() { log INFO "$*"; }; warn() { log WARN "$*"; }; die() { log ERROR "$*"; exit 1; }
debug() { (( VERBOSE )) && log DEBUG "$*" || true; }
