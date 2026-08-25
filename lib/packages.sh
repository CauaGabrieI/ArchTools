#!/usr/bin/env bash
is_package_installed() { pacman -Q "$1" >/dev/null 2>&1; }
package_available() { pacman -Si "$1" >/dev/null 2>&1; }
plan_package() { local p=$1; [[ " ${PLAN_PACKAGES[*]} " == *" $p "* ]] || PLAN_PACKAGES+=("$p"); }
plan_optional_package() { local p=$1; plan_package "$p"; [[ " ${PLAN_OPTIONAL_PACKAGES[*]} " == *" $p "* ]] || PLAN_OPTIONAL_PACKAGES+=("$p"); }
install_package() { install_packages "$@"; }
package_was_installed_by_archtools() {
  [[ -n ${STATE_DIR:-} ]] && grep -Fqx -- "$1" "$STATE_DIR/installed-packages.txt" 2>/dev/null
}
package_was_preexisting() {
  [[ -n ${STATE_DIR:-} ]] && grep -Fqx -- "$1" "$STATE_DIR/existing-packages.txt" 2>/dev/null
}
record_existing_package_provenance() {
  local p=$1
  if package_was_installed_by_archtools "$p"; then
    package_was_preexisting "$p" && state_remove_value "$STATE_DIR/existing-packages.txt" "$p"
  elif ! package_was_preexisting "$p"; then
    state_add_unique "$STATE_DIR/existing-packages.txt" "$p"
  fi
  return 0
}
record_managed_package_provenance() {
  local p=$1
  package_was_preexisting "$p" && state_remove_value "$STATE_DIR/existing-packages.txt" "$p"
  state_add_unique "$STATE_DIR/installed-packages.txt" "$p"
  return 0
}
install_packages() {
  local p rc=0 missing=()
  for p in "$@"; do
    if is_package_installed "$p"; then record_existing_package_provenance "$p"; log INFO "[OK] $p já instalado"
    elif ! package_available "$p"; then
      if declare -F package_is_optional >/dev/null 2>&1 && package_is_optional "$p"; then warn "[SKIP opcional] $p não está disponível"
      else log ERROR "Pacote obrigatório indisponível: $p"; return 1; fi
    else missing+=("$p"); fi
  done
  ((${#missing[@]})) || return 0
  log INFO "Instalando: ${missing[*]}"
  sudo pacman -S --needed "${missing[@]}" || rc=$?
  for p in "${missing[@]}"; do
    if is_package_installed "$p"; then
      if [[ ${TRANSACTION_STATUS:-} == active ]] && declare -F record_change >/dev/null 2>&1; then
        record_change packages package "$p" absent installed yes || { sudo pacman -R -- "$p"; return 1; }
      fi
      record_managed_package_provenance "$p" || return 1
    fi
  done
  return "$rc"
}
remove_package() {
  local p=$1
  grep -Fqx -- "$p" "$STATE_DIR/installed-packages.txt" || { warn "[SKIP] $p não pertence ao registro do projeto"; return 0; }
  if is_package_installed "$p"; then
    log INFO "Removendo pacote registrado: $p"
    sudo pacman -R -- "$p" || { log ERROR "Failed to remove package: $p"; return 1; }
  else
    warn "[SKIP] $p já não está instalado; removendo somente o registro"
  fi
  state_remove_value "$STATE_DIR/installed-packages.txt" "$p"
}
