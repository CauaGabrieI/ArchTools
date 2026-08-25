#!/usr/bin/env bash

TRANSACTION_ID=""
TRANSACTION_STATUS=""

transaction_fail() {
  printf '[TRANSACTION ERROR] %s\n' "$1" >&2
  return 1
}

transaction_require_active() {
  [[ ${TRANSACTION_STATUS:-} == active && -n ${TRANSACTION_ID:-} ]] || transaction_fail "Nenhuma transação active está aberta."
}

transaction_validate_field() {
  local field=$1 value=$2
  [[ -n $value ]] || { transaction_fail "Campo vazio: $field"; return 1; }
  [[ $value != *$'\t'* && $value != *$'\n'* && $value != *$'\r'* ]] || {
    transaction_fail "Campo contém separador inválido: $field"
    return 1
  }
}

transaction_event_file() {
  printf '%s/transactions/%s.tsv' "$STATE_DIR" "$TRANSACTION_ID"
}

transaction_write_event() {
  local event=$1 type=$2 resource=$3 before=$4 after=$5 reversible=$6
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$TRANSACTION_ID" "$RUN_ID" "${TRANSACTION_STATUS:-unknown}" "${TRANSACTION_MODULE:-unknown}" \
    "$(date -Is)" "$event" "$type" "$resource" "$before" "$after" "$reversible" >> "$(transaction_event_file)"
}

transaction_set_status() {
  local new_status=$1 file="$STATE_DIR/transactions.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' "$TRANSACTION_ID" "$RUN_ID" "$new_status" "$TRANSACTION_MODULE" "$(date -Is)" >> "$file"
  TRANSACTION_STATUS=$new_status
}

transaction_find_active() {
  awk -F '\t' '
    { status[$1] = $3 }
    END { for (id in status) if (status[id] == "active") { print id; exit } }
  ' "$STATE_DIR/transactions.tsv"
}

transaction_generate_id() {
  local candidate suffix=0
  while :; do
    candidate="txn-${RUN_ID}-$$-$(date +%s%N)-$suffix"
    if ! awk -F '\t' -v id="$candidate" '$1 == id { found=1 } END { exit !found }' "$STATE_DIR/transactions.tsv"; then
      TRANSACTION_ID=$candidate
      return 0
    fi
    suffix=$((suffix + 1))
  done
}

begin_transaction() {
  local module=${1:-unknown} file active
  [[ -n ${STATE_DIR:-} && -n ${RUN_ID:-} ]] || transaction_fail "STATE_DIR e RUN_ID devem estar definidos."
  transaction_validate_field RUN_ID "$RUN_ID" || return
  [[ $module =~ ^[a-zA-Z0-9_.:-]+$ ]] || transaction_fail "Módulo de transação inválido: $module"
  if (( ! ${DRY_RUN:-0} )) && [[ ${TRANSACTION_ID:-} == dryrun-* ]]; then
    TRANSACTION_ID=""; TRANSACTION_STATUS=""; TRANSACTION_MODULE=""
  fi
  if [[ ${TRANSACTION_STATUS:-} == active ]]; then
    transaction_fail "Já existe uma transação ativa: $TRANSACTION_ID"
    return
  fi
  if (( ${DRY_RUN:-0} )); then
    TRANSACTION_ID="dryrun-${RUN_ID}-$$-$(date +%N)"
    TRANSACTION_STATUS=active
    TRANSACTION_MODULE=$module
    return 0
  fi
  file="$STATE_DIR/transactions.tsv"
  mkdir -p "$STATE_DIR/transactions" || return 1
  touch "$file" || return 1
  active=$(transaction_find_active)
  if [[ -n $active ]]; then
    transaction_fail "Já existe uma transação ativa: $active"
    return
  fi
  transaction_generate_id
  TRANSACTION_STATUS=active
  TRANSACTION_MODULE=$module
  printf '%s\t%s\tactive\t%s\t%s\n' "$TRANSACTION_ID" "$RUN_ID" "$module" "$(date -Is)" >> "$file"
  : > "$(transaction_event_file)"
}

record_change() {
  [[ $# == 6 ]] || transaction_fail "Uso: record_change <módulo> <tipo> <recurso> <estado-anterior> <estado-posterior> <reversível>"
  transaction_require_active || return
  local module=$1 type=$2 resource=$3 before=$4 after=$5 reversible=$6
  transaction_validate_field module "$module" || return
  transaction_validate_field type "$type" || return
  transaction_validate_field resource "$resource" || return
  transaction_validate_field estado-anterior "$before" || return
  transaction_validate_field estado-posterior "$after" || return
  [[ $module =~ ^[a-zA-Z0-9_.:-]+$ ]] || transaction_fail "Módulo de mudança inválido: $module"
  [[ $reversible == yes || $reversible == no ]] || transaction_fail "Reversível deve ser yes ou no."
  (( ${DRY_RUN:-0} )) && return 0
  transaction_write_event change "$type" "$resource" "$before" "$after" "$reversible"
}

commit_transaction() {
  transaction_require_active || return
  (( ${DRY_RUN:-0} )) && { TRANSACTION_STATUS=committed; return 0; }
  transaction_set_status committed || return 1
  transaction_write_event status transaction status active committed yes
}

abort_transaction() {
  local reason=${1:-sem motivo informado}
  transaction_require_active || return
  transaction_validate_field motivo "$reason" || return
  (( ${DRY_RUN:-0} )) && { TRANSACTION_STATUS=aborted; return 0; }
  transaction_set_status aborted || return 1
  transaction_write_event status transaction status active "$reason" yes
}

rollback_transaction() {
  local non_reversible
  [[ ${TRANSACTION_STATUS:-} == active || ${TRANSACTION_STATUS:-} == committed || ${TRANSACTION_STATUS:-} == aborted ]] || {
    transaction_fail "Transação não pode sofrer rollback: ${TRANSACTION_STATUS:-inexistente}"
    return 1
  }
  (( ${DRY_RUN:-0} )) && { TRANSACTION_STATUS=rolled_back; return 0; }
  non_reversible=$(awk -F '\t' '$6 == "change" && $11 != "yes" {print $8; exit}' "$(transaction_event_file)" 2>/dev/null || true)
  if [[ -n $non_reversible ]]; then
    transaction_write_event rollback rejection "$non_reversible" active rejected no
    transaction_fail "Rollback rejeitado: alteração não reversível registrada em $non_reversible"
    return
  fi
  transaction_set_status rolled_back || return 1
  transaction_write_event rollback physical rollback not_implemented metadata_only yes
}