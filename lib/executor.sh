#!/usr/bin/env bash
execute_plan() {
  log INFO 'Executando plano confirmado.'
  install_packages "${PLAN_PACKAGES[@]}"
  local service; for service in "${PLAN_SERVICES_ENABLE[@]}"; do enable_service_safe "$service"; done
}
enable_service_safe() {
  local s=$1 old; old=$(systemctl is-enabled "$s" 2>/dev/null || true)
  if [[ $old == enabled ]]; then log INFO "[OK] $s já habilitado"; return; fi
  sudo systemctl enable "$s"; state_add_unique "$STATE_DIR/services.txt" "$s|$old|enabled"; log INFO "[OK] Habilitado: $s"
}
