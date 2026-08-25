#!/usr/bin/env bash
validate_plan() {
  printf '\nValidação\n'; local p s status=0
  for p in "${PLAN_PACKAGES[@]}"; do is_package_installed "$p" && printf '[OK] pacote %s\n' "$p" || { printf '[WARN] pacote ausente: %s\n' "$p"; status=1; }; done
  for s in "${PLAN_SERVICES_ENABLE[@]}"; do systemctl is-enabled "$s" >/dev/null 2>&1 && printf '[OK] serviço %s\n' "$s" || printf '[WARN] serviço não habilitado: %s\n' "$s"; done
  return "$status"
}
show_report() { printf '\nConcluído. Log: %s\nEstado: %s\nNão houve reinicialização automática.\n' "$LOG_FILE" "$STATE_DIR"; }
