#!/usr/bin/env bash
execute_plan() {
  log INFO 'Executando plano confirmado.'
  install_packages "${PLAN_PACKAGES[@]}"
  local service; for service in "${PLAN_SERVICES_ENABLE[@]}"; do enable_service_safe "$service"; done
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
