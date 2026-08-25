#!/usr/bin/env bash
execute_plan() {
  local owns_transaction=0
  if declare -F validate_plan_pre_execution >/dev/null 2>&1; then
    validate_plan_pre_execution || { log ERROR 'Plano inválido antes da execução.'; return 1; }
  fi
  if [[ ${TRANSACTION_STATUS:-} != active ]] && declare -F begin_transaction >/dev/null 2>&1; then
    begin_transaction "${TRANSACTION_MODULE:-install}" || return 1
    owns_transaction=1
  fi
  log INFO 'Executando plano confirmado.'
  if ! install_packages "${PLAN_PACKAGES[@]}"; then
    (( owns_transaction )) && transaction_abort_and_rollback "falha na instalação de pacotes"
    return 1
  fi
  local service
  for service in "${PLAN_SERVICES_ENABLE[@]}"; do
    if ! enable_service_safe "$service"; then
      (( owns_transaction )) && transaction_abort_and_rollback "falha ao habilitar serviço $service"
      return 1
    fi
  done
  if (( owns_transaction )); then
    if declare -F validate_plan >/dev/null 2>&1 && ! validate_plan; then
      transaction_abort_and_rollback "falha na validação final"
      return 1
    fi
    commit_transaction || return 1
  fi
}
enable_service_safe() {
  local s=$1 old; old=$(systemctl is-enabled "$s" 2>/dev/null || true)
  if [[ $old == enabled ]]; then log INFO "[OK] $s já habilitado"; return; fi
  [[ $old == disabled || $old == masked ]] || { log ERROR "Estado anterior de serviço não reversível: $s=${old:-desconhecido}"; return 1; }
  sudo systemctl enable "$s" || return 1
  if [[ $(systemctl is-enabled "$s" 2>/dev/null || true) == enabled ]]; then
    if [[ ${TRANSACTION_STATUS:-} == active ]] && declare -F record_change >/dev/null 2>&1; then
      record_change services service "$s" "$old" enabled yes || { transaction_restore_service "$s" "$old"; return 1; }
    fi
    state_add_unique "$STATE_DIR/services.txt" "$s|$old|enabled" || return 1
    log INFO "[OK] Habilitado: $s"
  else
    log ERROR "Falha ao confirmar serviço habilitado: $s"
    if declare -F transaction_restore_service >/dev/null 2>&1; then transaction_restore_service "$s" "$old" || true; fi
    return 1
  fi
}
