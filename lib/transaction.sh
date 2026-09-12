#!/usr/bin/env bash

if ! declare -F init_state >/dev/null 2>&1; then
  source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/state.sh"
fi

TRANSACTION_ID=""
TRANSACTION_STATUS=""

transaction_fail() { printf '[TRANSACTION ERROR] %s\n' "$1" >&2; return 1; }
transaction_require_active() { [[ ${TRANSACTION_STATUS:-} == active && -n ${TRANSACTION_ID:-} ]] || transaction_fail "Nenhuma transação active está aberta."; }

# A deliberate process exit in the disposable nspawn guest leaves the existing
# ledger and lock intact so the real orphan recovery path can be exercised.
transaction_test_guest() {
  [[ -r /etc/archtools-nspawn-test && $(< /etc/archtools-nspawn-test) == archtools-nspawn-v1:test ]] &&
    command -v systemd-detect-virt >/dev/null 2>&1 &&
    [[ $(systemd-detect-virt --container 2>/dev/null) == systemd-nspawn ]] &&
    [[ -d /run/systemd/system ]]
}

transaction_test_failpoint_validate() {
  [[ -n ${ARCHTOOLS_TEST_FAILPOINT:-} ]] || return 0
  case $ARCHTOOLS_TEST_FAILPOINT in
    after_transaction_begin|after_package_install|after_service_enable|before_commit) ;;
    *) transaction_fail "Failpoint de teste desconhecido: $ARCHTOOLS_TEST_FAILPOINT"; return 2;;
  esac
  transaction_test_guest || { transaction_fail 'Fault injection só é permitida no guest archtools-test.'; return 2; }
}

transaction_test_failpoint() {
  local point=$1
  [[ -n ${ARCHTOOLS_TEST_FAILPOINT:-} ]] || return 0
  transaction_test_failpoint_validate || return 2
  [[ $ARCHTOOLS_TEST_FAILPOINT == "$point" ]] || return 0
  printf '[TEST FAILPOINT] %s: saída controlada antes do commit; transação preservada para recovery.\n' "$point" >&2
  exit 86
}

transaction_validate_field() {
  local field=$1 value=$2
  [[ -n $value ]] || { transaction_fail "Campo vazio: $field"; return 1; }
  [[ $value != *$'\t'* && $value != *$'\n'* && $value != *$'\r'* ]] || { transaction_fail "Campo contém separador inválido: $field"; return 1; }
}

transaction_event_file() { printf '%s/transactions/%s.tsv' "$STATE_DIR" "$TRANSACTION_ID"; }

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
  awk -F '\t' '{status[$1]=$3} END {for (id in status) if (status[id]=="active") print id}' "$STATE_DIR/transactions.tsv"
}

transaction_recover_orphans() {
  local id owner event_file original_run original_module rc=0
  local saved_run=$RUN_ID saved_id=${TRANSACTION_ID:-} saved_status=${TRANSACTION_STATUS:-} saved_module=${TRANSACTION_MODULE:-}
  while IFS= read -r id; do
    [[ -n $id ]] || continue
    owner=""
    [[ -r $STATE_DIR/transactions/$id.pid ]] && read -r owner < "$STATE_DIR/transactions/$id.pid"
    if [[ ! $owner =~ ^[0-9]+$ ]] || ! kill -0 "$owner" 2>/dev/null; then
      event_file="$STATE_DIR/transactions/$id.tsv"
      if [[ ! -r $event_file ]] || ! awk -F '\t' 'NF && NF!=11 {bad=1} END {exit bad}' "$event_file"; then
        transaction_fail "Event file inválido na transação órfã: $id"; rc=1; break
      fi
      original_run=$(awk -F '\t' -v id="$id" '$1==id && $3=="active" {print $2; exit}' "$STATE_DIR/transactions.tsv")
      original_module=$(awk -F '\t' -v id="$id" '$1==id && $3=="active" {print $4; exit}' "$STATE_DIR/transactions.tsv")
      [[ -n $original_run && -n $original_module ]] || { transaction_fail "Metadados inválidos na transação órfã: $id"; rc=1; break; }
      RUN_ID=$original_run; TRANSACTION_ID=$id; TRANSACTION_STATUS=active; TRANSACTION_MODULE=$original_module
      if awk -F '\t' '$6=="change" {found=1} END {exit !found}' "$event_file"; then
        rollback_transaction || { rc=1; break; }
        acquire_state_lock || { rc=1; break; }
      else
        transaction_write_event status transaction status active aborted yes || { rc=1; break; }
        transaction_set_status aborted || { rc=1; break; }
        save_run_result aborted || { rc=1; break; }
        rm -f -- "$STATE_DIR/transactions/$id.pid" || { rc=1; break; }
      fi
    fi
  done < <(transaction_find_active)
  RUN_ID=$saved_run; TRANSACTION_ID=$saved_id; TRANSACTION_STATUS=$saved_status; TRANSACTION_MODULE=$saved_module
  return "$rc"
}

transaction_generate_id() {
  local candidate suffix=0
  while :; do
    candidate="txn-${RUN_ID}-$$-$(date +%s%N)-$suffix"
    if ! awk -F '\t' -v id="$candidate" '$1==id {found=1} END {exit !found}' "$STATE_DIR/transactions.tsv"; then TRANSACTION_ID=$candidate; return 0; fi
    suffix=$((suffix + 1))
  done
}

begin_transaction() {
  local module=${1:-unknown} active
  transaction_test_failpoint_validate || return 2
  [[ -n ${STATE_DIR:-} && -n ${RUN_ID:-} ]] || transaction_fail "STATE_DIR e RUN_ID devem estar definidos."
  transaction_validate_field RUN_ID "$RUN_ID" || return
  [[ $module =~ ^[a-zA-Z0-9_.:-]+$ ]] || transaction_fail "Módulo de transação inválido: $module"
  if (( ${DRY_RUN:-0} )); then TRANSACTION_ID="dryrun-${RUN_ID}-$$-$(date +%N)"; TRANSACTION_STATUS=active; TRANSACTION_MODULE=$module; return 0; fi
  [[ ${TRANSACTION_STATUS:-} != active ]] || { transaction_fail "Já existe uma transação ativa: $TRANSACTION_ID"; return 1; }
  init_state
  acquire_state_lock || return 1
  transaction_recover_orphans || { release_state_lock; return 1; }
  active=$(transaction_find_active)
  [[ -z $active ]] || { release_state_lock; transaction_fail "Já existe uma transação ativa: $active"; return 1; }
  transaction_generate_id
  TRANSACTION_STATUS=active; TRANSACTION_MODULE=$module
  printf '%s\t%s\tactive\t%s\t%s\n' "$TRANSACTION_ID" "$RUN_ID" "$module" "$(date -Is)" >> "$STATE_DIR/transactions.tsv"
  : > "$(transaction_event_file)"; chmod 600 "$(transaction_event_file)"
  printf '%s\n' "${BASHPID:-$$}" > "$STATE_DIR/transactions/$TRANSACTION_ID.pid"; chmod 600 "$STATE_DIR/transactions/$TRANSACTION_ID.pid"
  transaction_test_failpoint after_transaction_begin
}

record_change() {
  [[ $# == 6 ]] || transaction_fail "Uso: record_change <módulo> <tipo> <recurso> <estado-anterior> <estado-posterior> <reversível>"
  transaction_require_active || return
  local module=$1 type=$2 resource=$3 before=$4 after=$5 reversible=$6 value
  for value in "$module" "$type" "$resource" "$before" "$after"; do transaction_validate_field campo "$value" || return; done
  [[ $module =~ ^[a-zA-Z0-9_.:-]+$ ]] || transaction_fail "Módulo de mudança inválido: $module"
  [[ $reversible == yes || $reversible == no ]] || transaction_fail "Reversível deve ser yes ou no."
  (( ${DRY_RUN:-0} )) || transaction_write_event change "$type" "$resource" "$before" "$after" "$reversible"
}

commit_transaction() {
  transaction_require_active || return
  if (( ${DRY_RUN:-0} )); then TRANSACTION_STATUS=committed; return 0; fi
  transaction_test_failpoint before_commit
  save_run_result committed || return 1
  transaction_write_event status transaction status active committed yes
  transaction_set_status committed || return 1
  rm -f -- "$STATE_DIR/transactions/$TRANSACTION_ID.pid"
  release_state_lock
}

abort_transaction() {
  local reason=${1:-sem motivo informado}
  transaction_require_active || return
  transaction_validate_field motivo "$reason" || return
  if (( ${DRY_RUN:-0} )); then TRANSACTION_STATUS=aborted; return 0; fi
  save_run_result aborted || return 1
  transaction_set_status aborted || return 1
  transaction_write_event status transaction status active "$reason" yes
}

transaction_restore_service() {
  local service=$1 old=$2
  case "$old" in
    enabled) sudo systemctl enable "$service" ;;
    disabled) sudo systemctl disable "$service" ;;
    masked) sudo systemctl mask "$service" ;;
    *) return 1 ;;
  esac
}

transaction_rollback_change() {
  local type=$1 resource=$2 before=$3 after=$4
  case "$type" in
    package)
      [[ $before == absent && $after == installed ]] || return 1
      is_package_installed "$resource" && sudo pacman -R --noconfirm -- "$resource"
      state_remove_value "$STATE_DIR/installed-packages.txt" "$resource"
      ;;
    service)
      transaction_restore_service "$resource" "$before"
      state_remove_value "$STATE_DIR/services.txt" "$resource|$before|$after"
      ;;
    file)
      if [[ $after == modified ]]; then sudo cp -a -- "$before" "$resource"
      elif [[ $after == created ]]; then [[ ! -e $resource ]] || sudo rm -f -- "$resource"
      else return 1; fi
      state_remove_value "$STATE_DIR/modified-files.txt" "$resource"
      ;;
    *) return 1 ;;
  esac
}

rollback_transaction() {
  [[ ${TRANSACTION_STATUS:-} == active || ${TRANSACTION_STATUS:-} == committed || ${TRANSACTION_STATUS:-} == aborted ]] || { transaction_fail "Transação não pode sofrer rollback: ${TRANSACTION_STATUS:-inexistente}"; return 1; }
  if (( ${DRY_RUN:-0} )); then TRANSACTION_STATUS=rolled_back; return 0; fi
  (( STATE_LOCK_HELD )) || acquire_state_lock || return 1
  local -a events=(); local type resource before after reversible i prior_status=$TRANSACTION_STATUS
  mapfile -t events < <(awk -F '\t' '$6=="change" {print $7 "\t" $8 "\t" $9 "\t" $10 "\t" $11}' "$(transaction_event_file)")
  for ((i=${#events[@]}-1; i>=0; i--)); do
    IFS=$'\t' read -r type resource before after reversible <<< "${events[i]}"
    [[ $reversible == yes ]] || { transaction_fail "Rollback rejeitado: alteração não reversível em $resource"; return 1; }
    transaction_rollback_change "$type" "$resource" "$before" "$after" || { transaction_fail "Falha no rollback de $type:$resource"; return 1; }
    transaction_write_event rollback "$type" "$resource" "$after" "$before" yes
  done
  save_run_result rolled_back || return 1
  transaction_set_status rolled_back || return 1
  transaction_write_event status transaction status "$prior_status" rolled_back yes
  rm -f -- "$STATE_DIR/transactions/$TRANSACTION_ID.pid"
  release_state_lock
}

transaction_abort_and_rollback() {
  local reason=$1
  abort_transaction "$reason" || return 1
  rollback_transaction
}
