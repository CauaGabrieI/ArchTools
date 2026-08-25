#!/usr/bin/env bash
execute_plan() {
  local owns_transaction=0
  if [[ ${TRANSACTION_STATUS:-} != active ]] && declare -F begin_transaction >/dev/null 2>&1; then
    begin_transaction "${TRANSACTION_MODULE:-install}" || return 1
    owns_transaction=1
  fi
  log INFO 'Executando plano confirmado.'
  if ! install_packages "${PLAN_PACKAGES[@]}"; then
    (( owns_transaction )) && abort_transaction "falha na instalação de pacotes"
    return 1
  fi
  local service
  for service in "${PLAN_SERVICES_ENABLE[@]}"; do
    if ! enable_service_safe "$service"; then
      (( owns_transaction )) && abort_transaction "falha ao habilitar serviço $service"
      return 1
    fi
  done
  if (( owns_transaction )); then
    commit_transaction || return 1
  fi
}
enable_service_safe() {
  local s=$1 old; old=$(systemctl is-enabled "$s" 2>/dev/null || true)
  if [[ $old == enabled ]]; then log INFO "[OK] $s já habilitado"; return; fi
  sudo systemctl enable "$s" || return 1
  if [[ $(systemctl is-enabled "$s" 2>/dev/null || true) == enabled ]]; then
    state_add_unique "$STATE_DIR/services.txt" "$s|$old|enabled"
    if [[ ${TRANSACTION_STATUS:-} == active ]] && declare -F record_change >/dev/null 2>&1; then
      record_change services service "$s" "$old" enabled yes
    fi
    log INFO "[OK] Habilitado: $s"
  else
    log ERROR "Falha ao confirmar serviço habilitado: $s"
    return 1
  fi
}
