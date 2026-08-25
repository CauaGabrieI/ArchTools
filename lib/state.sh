#!/usr/bin/env bash

STATE_LOCK_HELD=0
STATE_LOCK_OWNER_PID=""

state_secure_layout() {
  umask 077
  mkdir -p "$STATE_DIR/backups" "$STATE_DIR/transactions"
  chmod 700 "$STATE_DIR" "$STATE_DIR/backups" "$STATE_DIR/transactions"
}

init_state() {
  local file
  state_secure_layout
  for file in installed-packages.txt existing-packages.txt modified-files.txt services.txt runs.tsv transactions.tsv backups/manifest.tsv; do
    [[ -e $STATE_DIR/$file ]] || : > "$STATE_DIR/$file"
    chmod 600 "$STATE_DIR/$file"
  done
}

acquire_state_lock() {
  (( STATE_LOCK_HELD )) && return 0
  state_secure_layout
  local lock="$STATE_DIR/.lock" owner=""
  if ! mkdir "$lock" 2>/dev/null; then
    [[ -r $lock/pid ]] && read -r owner < "$lock/pid"
    if [[ $owner =~ ^[0-9]+$ ]] && kill -0 "$owner" 2>/dev/null; then
      printf '[STATE ERROR] Outra operação está ativa (PID %s).\n' "$owner" >&2
      return 1
    fi
    rm -f -- "$lock/pid"
    rmdir "$lock" 2>/dev/null || { printf '[STATE ERROR] Lock inválido não pôde ser recuperado.\n' >&2; return 1; }
    mkdir "$lock" || return 1
  fi
  STATE_LOCK_OWNER_PID=${BASHPID:-$$}
  printf '%s\n' "$STATE_LOCK_OWNER_PID" > "$lock/pid"
  chmod 700 "$lock"; chmod 600 "$lock/pid"
  STATE_LOCK_HELD=1
  install_state_signal_traps
}

release_state_lock() {
  (( STATE_LOCK_HELD )) || return 0
  local owner="" current=${BASHPID:-$$}
  [[ -r $STATE_DIR/.lock/pid ]] && read -r owner < "$STATE_DIR/.lock/pid"
  if [[ -n $STATE_LOCK_OWNER_PID && $owner == "$STATE_LOCK_OWNER_PID" && $owner == "$current" ]]; then
    rm -f -- "$STATE_DIR/.lock/pid"
    rmdir "$STATE_DIR/.lock" 2>/dev/null || true
  fi
  STATE_LOCK_HELD=0
  STATE_LOCK_OWNER_PID=""
  clear_state_signal_traps
}

state_signal_cleanup() {
  local code=$1
  trap - INT TERM HUP
  release_state_lock
  exit "$code"
}

install_state_signal_traps() {
  trap 'state_signal_cleanup 130' INT
  trap 'state_signal_cleanup 143' TERM
  trap 'state_signal_cleanup 129' HUP
}

clear_state_signal_traps() { trap - INT TERM HUP; }

atomic_write() {
  local target=$1 tmp mode=${2:-600}
  tmp=$(mktemp "$STATE_DIR/.atomic.XXXXXX") || return 1
  if ! cat > "$tmp"; then rm -f -- "$tmp"; return 1; fi
  chmod "$mode" "$tmp" || { rm -f -- "$tmp"; return 1; }
  mv -f -- "$tmp" "$target"
}

save_run_status() {
  local status=$1 now=${2:-$(date -Is)} tmp run_key=${TRANSACTION_ID:-}
  [[ -n $run_key && -n ${RUN_ID:-} && -n ${TRANSACTION_MODULE:-} ]] || return 1
  (( STATE_LOCK_HELD )) || return 1
  tmp=$(mktemp "$STATE_DIR/.runs.XXXXXX") || return 1
  awk -F '\t' -v key="$run_key" '$1 != key' "$STATE_DIR/runs.tsv" > "$tmp"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$run_key" "$TRANSACTION_ID" "$RUN_ID" "$TRANSACTION_MODULE" "$status" "$now" \
    "${LOG_FILE:-}" "${DESKTOP:-}" "${PROFILE:-}" >> "$tmp"
  chmod 600 "$tmp"; mv -f -- "$tmp" "$STATE_DIR/runs.tsv"
}

save_tool_run() { save_run_result committed; }

state_add_unique() {
  local file=$1 value=$2 tmp
  grep -Fqx -- "$value" "$file" 2>/dev/null && return 0
  tmp=$(mktemp "$STATE_DIR/.state.XXXXXX") || return 1
  { cat "$file" 2>/dev/null; printf '%s\n' "$value"; } > "$tmp"
  chmod 600 "$tmp"; mv -f -- "$tmp" "$file"
}

state_remove_value() {
  local file=$1 value=$2 tmp
  tmp=$(mktemp "$STATE_DIR/.state.XXXXXX") || return 1
  grep -Fvx -- "$value" "$file" > "$tmp" || [[ $? == 1 ]]
  chmod 600 "$tmp"; mv -f -- "$tmp" "$file"
}

save_last_run() {
  local desktop=$1 profile=$2 status=${3:-committed} now=${4:-$(date -Is)}
  printf 'date=%s\ndesktop=%s\nprofile=%s\nstatus=%s\ntransaction=%s\nlog=%s\n' \
    "$now" "$desktop" "$profile" "$status" "${TRANSACTION_ID:-}" "${LOG_FILE:-}" | atomic_write "$STATE_DIR/last-run"
  printf '{\n  "application": "%s",\n  "last_run": "%s",\n  "status": "%s",\n  "transaction": "%s"\n}\n' \
    "${APP_ID:-arch-smart-postinstall}" "$now" "$status" "${TRANSACTION_ID:-}" | atomic_write "$STATE_DIR/state.json"
}

save_run_result() {
  local status=$1 now
  now=$(date -Is)
  save_run_status "$status" "$now" || return 1
  save_last_run "${DESKTOP:-}" "${PROFILE:-}" "$status" "$now"
}

clear_last_run() { :; }

list_changes() {
  printf 'Current changes\n'
  printf 'Packages installed by this project:\n'; sed 's/^/  + /' "$STATE_DIR/installed-packages.txt"
  printf '\nPre-existing packages:\n'; sed 's/^/  = /' "$STATE_DIR/existing-packages.txt"
  printf '\nFiles modified:\n'; sed 's/^/  ~ /' "$STATE_DIR/modified-files.txt"
  printf '\nServices changed:\n'; sed 's/^/  * /' "$STATE_DIR/services.txt"
  printf '\nBackups:\n'; sed 's/^/  ~ /' "$STATE_DIR/backups/manifest.tsv"
  printf '\nHistory\n'
  awk -F '\t' '{printf "  run=%s transaction=%s module=%s status=%s date=%s\n", $3, $2, $4, $5, $6}' "$STATE_DIR/runs.tsv"
  printf 'Transaction outcomes:\n'
  awk -F '\t' '{status[$1]=$3; module[$1]=$4} END {for (id in status) printf "  transaction=%s module=%s status=%s\n", id, module[id], status[id]}' "$STATE_DIR/transactions.tsv"
}
