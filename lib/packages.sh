#!/usr/bin/env bash
is_package_installed() { pacman -Q "$1" >/dev/null 2>&1; }
package_available() { pacman -Si "$1" >/dev/null 2>&1; }
plan_package() { local p=$1; [[ " ${PLAN_PACKAGES[*]} " == *" $p "* ]] || PLAN_PACKAGES+=("$p"); }
install_package() { install_packages "$@"; }
install_packages() {
  local p missing=()
  for p in "$@"; do
    if is_package_installed "$p"; then state_add_unique "$STATE_DIR/existing-packages.txt" "$p"; log INFO "[OK] $p já instalado"
    elif ! package_available "$p"; then warn "[SKIP] $p não está disponível nos repositórios configurados"
    else missing+=("$p"); fi
  done
  ((${#missing[@]})) || return 0
  log INFO "Instalando: ${missing[*]}"; sudo pacman -S --needed "${missing[@]}" || return 1
  for p in "${missing[@]}"; do
    if is_package_installed "$p"; then
      state_add_unique "$STATE_DIR/installed-packages.txt" "$p"
      if [[ ${TRANSACTION_STATUS:-} == active ]] && declare -F record_change >/dev/null 2>&1; then
        record_change packages package "$p" absent installed yes
      fi
    fi
  done
}
remove_package() {
  local p=$1 tmp
  grep -Fqx -- "$p" "$STATE_DIR/installed-packages.txt" || { warn "[SKIP] $p não pertence ao registro do projeto"; return 0; }
  if is_package_installed "$p"; then
    log INFO "Removendo pacote registrado: $p"
    sudo pacman -R -- "$p" || { log ERROR "Failed to remove package: $p"; return 1; }
  else
    warn "[SKIP] $p já não está instalado; removendo somente o registro"
  fi
  tmp=$(mktemp "$STATE_DIR/.installed-packages.XXXXXX")
  grep -Fvx -- "$p" "$STATE_DIR/installed-packages.txt" > "$tmp" || [[ $? == 1 ]]
  mv -- "$tmp" "$STATE_DIR/installed-packages.txt"
}
