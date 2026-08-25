#!/usr/bin/env bash
rollback_run() {
  local -a installed=(); mapfile -t installed < "$STATE_DIR/installed-packages.txt"
  printf 'Plano de rollback\n  Restaurar backups: '; wc -l < "$STATE_DIR/backups/manifest.tsv" 2>/dev/null || printf '0\n'; printf '  Remover pacotes registrados: %s\n' "${#installed[@]}"
  (( DRY_RUN )) && return; confirm_plan || return
  local path backup _hash _time _module operation
  while IFS=$'\t' read -r path backup _hash _time _module operation; do
    [[ -n $path ]] || continue
    if [[ $operation == modified ]]; then sudo cp -a -- "$backup" "$path"; elif [[ $operation == created && -e $path ]]; then sudo rm -f -- "$path"; fi
  done < "$STATE_DIR/backups/manifest.tsv"
  local service old _new
  while IFS='|' read -r service old _new; do
    [[ -n $service ]] || continue
    case "$old" in enabled) sudo systemctl enable "$service";; disabled) sudo systemctl disable "$service";; masked) sudo systemctl mask "$service";; static|indirect|generated|'') warn "[SKIP] Não há restauração segura para $service (estado anterior: ${old:-desconhecido})";; *) warn "[SKIP] Estado de serviço não reconhecido: $service=$old";; esac
  done < "$STATE_DIR/services.txt"
  uninstall_packages_registered
}
uninstall_packages_registered() { local -a packages=(); local p; mapfile -t packages < "$STATE_DIR/installed-packages.txt"; for p in "${packages[@]}"; do [[ -n $p ]] && remove_package "$p"; done; }
uninstall_run() { printf '[WARNING] Isto remove apenas componentes registrados pelo projeto.\n'; (( DRY_RUN )) && { list_changes; return; }; confirm_plan || return; uninstall_packages_registered; }
