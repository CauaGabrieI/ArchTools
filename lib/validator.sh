#!/usr/bin/env bash

declare -ga PLAN_PACKAGES_INSTALLED=() PLAN_PACKAGES_AVAILABLE=() PLAN_PACKAGES_UNAVAILABLE=() PLAN_PACKAGES_OPTIONAL_SKIPPED=()

multilib_enabled() {
  local conf=${PACMAN_CONF:-/etc/pacman.conf}
  awk '/^[[:space:]]*#/ {next} /^[[:space:]]*\[multilib\][[:space:]]*$/ {found=1} END {exit !found}' "$conf" 2>/dev/null
}

package_is_optional() {
  local wanted=$1 p
  for p in "${PLAN_OPTIONAL_PACKAGES[@]:-}"; do [[ $p == "$wanted" ]] && return 0; done
  return 1
}

validate_plan_pre_execution() {
  PLAN_PACKAGES_INSTALLED=(); PLAN_PACKAGES_AVAILABLE=(); PLAN_PACKAGES_UNAVAILABLE=(); PLAN_PACKAGES_OPTIONAL_SKIPPED=()
  local p status=0 needs_multilib=0 multilib_ok=1
  multilib_enabled || multilib_ok=0
  for p in "${PLAN_PACKAGES[@]}"; do
    if is_package_installed "$p"; then PLAN_PACKAGES_INSTALLED+=("$p")
    else
      if [[ $p == steam || $p == lib32-* ]]; then
        needs_multilib=1
        if (( ! multilib_ok )); then
          if package_is_optional "$p"; then PLAN_PACKAGES_OPTIONAL_SKIPPED+=("$p")
          else PLAN_PACKAGES_UNAVAILABLE+=("$p"); status=1; fi
          continue
        fi
      fi
      if package_available "$p"; then PLAN_PACKAGES_AVAILABLE+=("$p")
      elif package_is_optional "$p"; then PLAN_PACKAGES_OPTIONAL_SKIPPED+=("$p")
      else PLAN_PACKAGES_UNAVAILABLE+=("$p"); status=1
      fi
    fi
  done
  if (( needs_multilib && ! multilib_ok )); then
    PLAN_NOTES+=("[ERRO] Repositório multilib está desabilitado; Steam e bibliotecas 32-bit não podem ser instalados.")
    status=1
  fi
  ((${#PLAN_PACKAGES_UNAVAILABLE[@]} == 0)) || PLAN_NOTES+=("[ERRO] Pacotes obrigatórios indisponíveis: ${PLAN_PACKAGES_UNAVAILABLE[*]}")
  return "$status"
}

validate_plan() {
  printf '\nValidação final\n'; local p s status=0
  for p in "${PLAN_PACKAGES[@]}"; do
    package_is_optional "$p" && ! package_available "$p" && ! is_package_installed "$p" && continue
    is_package_installed "$p" && printf '[OK] pacote %s\n' "$p" || { printf '[ERROR] pacote ausente: %s\n' "$p"; status=1; }
  done
  for s in "${PLAN_SERVICES_ENABLE[@]}"; do
    systemctl is-enabled "$s" >/dev/null 2>&1 && printf '[OK] serviço %s\n' "$s" || { printf '[ERROR] serviço não habilitado: %s\n' "$s"; status=1; }
  done
  return "$status"
}

show_report() { printf '\nConcluído. Log: %s\nEstado: %s\nNão houve reinicialização automática.\n' "$LOG_FILE" "$STATE_DIR"; }
