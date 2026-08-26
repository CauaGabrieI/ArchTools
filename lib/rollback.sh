#!/usr/bin/env bash

rollback_target_status() { awk -F '\t' -v id="$1" '$1==id {status=$3} END {print status}' "$STATE_DIR/transactions.tsv"; }
rollback_target_event_file() { printf '%s/transactions/%s.tsv\n' "$STATE_DIR" "$ROLLBACK_TARGET"; }

rollback_target_services() {
  awk -F '\t' '$6=="change" && $7=="service" && $11=="yes" {print $8 "|" $9 "|" $10}' "$(rollback_target_event_file)"
}

rollback_target_files() {
  awk -F '\t' '$6=="change" && $7=="file" && $11=="yes" {print $8 "\t" $9 "\t" $10}' "$(rollback_target_event_file)"
}

rollback_select_target() {
  local id status event_file
  declare -A seen=()
  while IFS= read -r id; do
    [[ -n $id && -z ${seen[$id]:-} ]] || continue
    seen[$id]=1; status=$(rollback_target_status "$id"); event_file="$STATE_DIR/transactions/$id.tsv"
    if [[ $status == committed && -r $event_file ]] && awk -F '\t' '$6=="change" && $7!="rollback" {found=1} END {exit !found}' "$event_file"; then
      printf '%s\n' "$id"; return 0
    fi
  done < <(awk -F '\t' '$3=="committed" && $4!="rollback" {print $1}' "$STATE_DIR/transactions.tsv" | tac)
  return 1
}

rollback_target_set_status() {
  local target=$1 status=$2 target_run target_module
  target_run=$(awk -F '\t' -v id="$target" '$1==id {run=$2} END {print run}' "$STATE_DIR/transactions.tsv")
  target_module=$(awk -F '\t' -v id="$target" '$1==id {module=$4} END {print module}' "$STATE_DIR/transactions.tsv")
  printf '%s\t%s\t%s\t%s\t%s\n' "$target" "$target_run" "$status" "${target_module:-install}" "$(date -Is)" >> "$STATE_DIR/transactions.tsv"
}

rollback_collect_packages() {
  local p
  ROLLBACK_PACKAGES=()
  while IFS= read -r p; do
    [[ -n $p ]] || continue
    grep -Fqx -- "$p" "$STATE_DIR/existing-packages.txt" && { log ERROR "Rollback inseguro: pacote também marcado como preexistente: $p"; return 1; }
    ROLLBACK_PACKAGES+=("$p")
  done < <(awk -F '\t' '$6=="change" && $7=="package" && $9=="absent" && $10=="installed" && $11=="yes" {print $8}' "$(rollback_target_event_file)")
}

rollback_preflight() {
  local p path backup _hash _time _module operation service old new current resolved
  rollback_collect_packages || return 1
  for p in "${ROLLBACK_PACKAGES[@]}"; do is_package_installed "$p" || { log ERROR "Rollback inválido: pacote gerenciado ausente: $p"; return 1; }; done
  ROLLBACK_RESOLVED_PACKAGES=()
  if ((${#ROLLBACK_PACKAGES[@]})); then
    resolved=$(sudo pacman -Rs --print --print-format '%n' -- "${ROLLBACK_PACKAGES[@]}") || { log ERROR 'Rollback inválido: o conjunto de pacotes não pode ser removido de forma coerente.'; return 1; }
    mapfile -t ROLLBACK_RESOLVED_PACKAGES <<< "$resolved"
    for p in "${ROLLBACK_RESOLVED_PACKAGES[@]}"; do
      [[ -n $p ]] || continue
      grep -Fqx -- "$p" "$STATE_DIR/existing-packages.txt" && { log ERROR "Rollback inseguro: a resolução removeria pacote preexistente: $p"; return 1; }
    done
  fi
  while IFS='|' read -r service old new; do
    [[ -n $service ]] || continue; current=$(systemctl is-enabled "$service" 2>/dev/null || true)
    [[ $current == "$new" ]] || { log ERROR "Rollback inválido: estado atual de $service é ${current:-desconhecido}, esperado $new."; return 1; }
    [[ $old == enabled || $old == disabled || $old == masked ]] || { log ERROR "Rollback inválido: estado anterior não restaurável para $service: $old"; return 1; }
  done < <(rollback_target_services)
  while IFS=$'\t' read -r path backup operation; do
    [[ -n $path ]] || continue
    [[ $operation == created || $operation == modified ]] || { log ERROR "Rollback inválido: operação de arquivo desconhecida: $operation"; return 1; }
    [[ $operation != modified || -r $backup ]] || { log ERROR "Rollback inválido: backup ausente para $path"; return 1; }
  done < <(rollback_target_files)
}

rollback_finish_transaction() {
  local status=$1 reason=$2 prior=${TRANSACTION_STATUS:-active}
  transaction_write_event status rollback "$ROLLBACK_TARGET" "$prior" "$status" yes
  save_run_result "$status" || return 1
  transaction_set_status "$status" || return 1
  rm -f -- "$STATE_DIR/transactions/$TRANSACTION_ID.pid"
  release_state_lock
  [[ $status == committed ]]
}

rollback_push_compensation() { ROLLBACK_COMPENSATIONS+=("$1"); ROLLBACK_MUTATED=1; }

rollback_compensate() {
  local i type resource desired snapshot existed status=0
  for ((i=${#ROLLBACK_COMPENSATIONS[@]}-1; i>=0; i--)); do
    IFS=$'\t' read -r type resource desired snapshot existed <<< "${ROLLBACK_COMPENSATIONS[i]}"
    case "$type" in
      service) transaction_restore_service "$resource" "$desired" || status=1 ;;
      file) if [[ $existed == yes ]]; then sudo cp -a -- "$snapshot" "$resource" || status=1; else sudo rm -f -- "$resource" || status=1; fi ;;
      packages) sudo pacman -S --needed --noconfirm -- "${ROLLBACK_PACKAGES[@]}" || status=1 ;;
      *) status=1 ;;
    esac
    transaction_write_event compensation "$type" "$resource" rollback restored yes || status=1
  done
  return "$status"
}

rollback_sync_partial_state() {
  local p service old new current
  for p in "${ROLLBACK_PACKAGES[@]}"; do is_package_installed "$p" || state_remove_value "$STATE_DIR/installed-packages.txt" "$p"; done
  while IFS='|' read -r service old new; do
    [[ -n $service ]] || continue; current=$(systemctl is-enabled "$service" 2>/dev/null || true)
    [[ $current != "$old" ]] || state_remove_value "$STATE_DIR/services.txt" "$service|$old|$new"
  done < <(rollback_target_services)
}

rollback_fail() {
  local reason=$1
  if (( ROLLBACK_MUTATED )); then
    if rollback_compensate; then rollback_finish_transaction aborted "$reason; alterações compensadas" || true
    else rollback_sync_partial_state; rollback_target_set_status "$ROLLBACK_TARGET" partial; rollback_finish_transaction rollback_failed "$reason; compensação falhou" || true
    fi
  else rollback_finish_transaction aborted "$reason" || true
  fi
  return 1
}

rollback_apply_files() {
  local path backup operation snapshot existed index=0
  while IFS=$'\t' read -r path backup operation; do
    [[ -n $path ]] || continue; snapshot="$ROLLBACK_COMP_DIR/file-$index"; existed=no
    if [[ -e $path ]]; then sudo cp -a -- "$path" "$snapshot" || return 1; existed=yes; fi
    if [[ $operation == modified ]]; then sudo cp -a -- "$backup" "$path" || return 1; elif [[ $operation == created ]]; then sudo rm -f -- "$path" || return 1; fi
    rollback_push_compensation $'file\t'"$path"$'\t-\t'"$snapshot"$'\t'"$existed"
    record_change rollback file "$path" applied reverted yes || return 1; index=$((index + 1))
  done < <(rollback_target_files)
}

rollback_apply_services() {
  local service old new
  while IFS='|' read -r service old new; do
    [[ -n $service ]] || continue; transaction_restore_service "$service" "$old" || return 1
    rollback_push_compensation $'service\t'"$service"$'\t'"$new"$'\t-\t-'
    record_change rollback service "$service" "$new" "$old" yes || return 1
  done < <(rollback_target_services)
}

rollback_apply_packages() {
  local p
  ((${#ROLLBACK_PACKAGES[@]})) || return 0
  sudo pacman -Rns --noconfirm -- "${ROLLBACK_PACKAGES[@]}" || return 1
  rollback_push_compensation $'packages\tpackage-set\t-\t-\t-'
  for p in "${ROLLBACK_PACKAGES[@]}"; do
    is_package_installed "$p" && return 1
    record_change rollback package "$p" installed absent yes || return 1
  done
  for p in "${ROLLBACK_RESOLVED_PACKAGES[@]}"; do
    [[ -n $p ]] || continue
    record_change rollback dependency "$p" installed absent yes || return 1
  done
}

rollback_clear_current_changes() {
  local p service old new path backup operation
  for p in "${ROLLBACK_PACKAGES[@]}"; do state_remove_value "$STATE_DIR/installed-packages.txt" "$p"; done
  while IFS='|' read -r service old new; do
    [[ -n $service ]] && state_remove_value "$STATE_DIR/services.txt" "$service|$old|$new"
  done < <(rollback_target_services)
  while IFS=$'\t' read -r path backup operation; do
    [[ -n $path ]] || continue
    state_remove_value "$STATE_DIR/modified-files.txt" "$path"
    awk -F '\t' -v path="$path" -v backup="$backup" '!($1==path && $2==backup)' "$STATE_DIR/backups/manifest.tsv" | atomic_write "$STATE_DIR/backups/manifest.tsv"
  done < <(rollback_target_files)
}

rollback_cleanup_compensation() {
  [[ -n ${ROLLBACK_COMP_DIR:-} && -d $ROLLBACK_COMP_DIR ]] || return 0
  sudo rm -rf -- "$ROLLBACK_COMP_DIR" 2>/dev/null || rm -rf -- "$ROLLBACK_COMP_DIR"
}

rollback_show_plan() {
  local target=$1 service old new path backup _hash _time _module operation
  rollback_collect_packages || return 1
  printf 'Plano de rollback\n  Transação alvo: %s\n  Pacotes gerenciados:\n' "$target"
  ((${#ROLLBACK_PACKAGES[@]})) && printf '    - %s\n' "${ROLLBACK_PACKAGES[@]}" || printf '    (nenhum)\n'
  printf '  Serviços a restaurar:\n'
  if [[ -n $(rollback_target_services) ]]; then while IFS='|' read -r service old new; do printf '    - %s: %s -> %s\n' "$service" "$new" "$old"; done < <(rollback_target_services); else printf '    (nenhum)\n'; fi
  printf '  Arquivos a restaurar/remover:\n'
  if [[ -n $(rollback_target_files) ]]; then while IFS=$'\t' read -r path backup operation; do printf '    - %s (%s)\n' "$path" "$operation"; done < <(rollback_target_files); else printf '    (nenhum)\n'; fi
  printf '  Pacotes preexistentes preservados:\n'; sed 's/^/    = /' "$STATE_DIR/existing-packages.txt"
}

rollback_run() {
  ROLLBACK_TARGET=$(rollback_select_target) || { log ERROR 'Nenhuma transação committed com alterações aplicadas pode ser revertida.'; return 1; }
  rollback_show_plan "$ROLLBACK_TARGET" || return 1
  (( DRY_RUN )) && return 0
  confirm_plan || return 0
  begin_transaction rollback || return 1
  ROLLBACK_COMPENSATIONS=(); ROLLBACK_MUTATED=0
  record_change rollback transaction "$ROLLBACK_TARGET" committed rollback_requested yes || { rollback_fail 'falha ao associar transação alvo'; return 1; }
  if ! rollback_preflight; then rollback_fail 'preflight do rollback falhou'; return 1; fi
  ROLLBACK_COMP_DIR="$STATE_DIR/transactions/$TRANSACTION_ID.compensation"; mkdir -p "$ROLLBACK_COMP_DIR"; chmod 700 "$ROLLBACK_COMP_DIR"
  if ! rollback_apply_files || ! rollback_apply_services || ! rollback_apply_packages; then rollback_fail 'execução do rollback falhou'; rollback_cleanup_compensation; return 1; fi
  if ! rollback_clear_current_changes; then rollback_fail 'falha ao atualizar estado atual'; rollback_cleanup_compensation; return 1; fi
  rollback_target_set_status "$ROLLBACK_TARGET" rolled_back
  rollback_finish_transaction committed 'rollback completo'
  rollback_cleanup_compensation
}

uninstall_packages_registered() { local -a packages=(); local p; mapfile -t packages < "$STATE_DIR/installed-packages.txt"; for p in "${packages[@]}"; do [[ -n $p ]] && remove_package "$p"; done; }
uninstall_run() { printf '[WARNING] Isto remove apenas componentes registrados pelo projeto.\n'; (( DRY_RUN )) && { list_changes; return; }; confirm_plan || return; acquire_state_lock || return 1; uninstall_packages_registered; release_state_lock; }
