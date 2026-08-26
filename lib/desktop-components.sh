#!/usr/bin/env bash

declare -ga DESKTOP_COMPONENT_CATEGORIES=(terminal browser store files editor archive)
declare -ga DESKTOP_COMPONENTS_SELECTED=()
declare -gA DESKTOP_COMPONENT_PACKAGES=(
  [gnome:terminal]=gnome-console [gnome:browser]=epiphany [gnome:store]=gnome-software
  [gnome:files]=nautilus [gnome:editor]=gnome-text-editor [gnome:archive]=file-roller
  [kde:terminal]=konsole [kde:browser]=falkon [kde:store]=discover
  [kde:files]=dolphin [kde:editor]=kate [kde:archive]=ark
  [xfce:terminal]=xfce4-terminal [xfce:browser]=firefox [xfce:store]=gnome-software
  [xfce:files]=thunar [xfce:editor]=mousepad [xfce:archive]=file-roller
  [cinnamon:terminal]=gnome-terminal [cinnamon:browser]=firefox [cinnamon:store]=gnome-software
  [cinnamon:files]=nemo [cinnamon:editor]=xed [cinnamon:archive]=file-roller
  [hyprland:terminal]=foot [hyprland:browser]=firefox [hyprland:store]=gnome-software
  [hyprland:files]=thunar [hyprland:editor]=mousepad [hyprland:archive]=file-roller
)

normalize_desktop() {
  local value=${1:-}
  value=${value,,}; value=${value// /}
  case "$value" in
    gnome|gnome:*|gnome-classic|ubuntu:gnome) printf 'gnome\n' ;;
    kde|kde:*|kdeplasma|plasma|plasmawayland|plasmax11) printf 'kde\n' ;;
    xfce|xfce4) printf 'xfce\n' ;;
    x-cinnamon|cinnamon) printf 'cinnamon\n' ;;
    hyprland) printf 'hyprland\n' ;;
    minimal) printf 'minimal\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

detect_current_desktop() {
  local explicit=${1:-} detected normalized
  if [[ -n $explicit ]]; then normalize_desktop "$explicit"; return; fi
  detected=${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-}}
  normalized=$(normalize_desktop "$detected")
  printf '%s\n' "$normalized"
}

desktop_component_package() { printf '%s\n' "${DESKTOP_COMPONENT_PACKAGES[$1:$2]:-}"; }

parse_desktop_components() {
  local spec=${1:-none} item category found
  local -a requested=()
  DESKTOP_COMPONENTS_SELECTED=()
  [[ -n $spec ]] || spec=none
  if [[ $spec == none ]]; then return 0; fi
  if [[ $spec == all ]]; then DESKTOP_COMPONENTS_SELECTED=("${DESKTOP_COMPONENT_CATEGORIES[@]}"); return 0; fi
  [[ $spec != *all* && $spec != *none* ]] || { printf 'Seleção de componentes inválida: %s\n' "$spec" >&2; return 1; }
  IFS=',' read -ra requested <<< "$spec"
  for item in "${requested[@]}"; do
    [[ -n $item ]] || { printf 'Componente vazio na seleção.\n' >&2; return 1; }
    found=0
    for category in "${DESKTOP_COMPONENT_CATEGORIES[@]}"; do [[ $item == "$category" ]] && found=1; done
    (( found )) || { printf 'Componente inválido: %s\n' "$item" >&2; return 1; }
    [[ " ${DESKTOP_COMPONENTS_SELECTED[*]} " == *" $item "* ]] || DESKTOP_COMPONENTS_SELECTED+=("$item")
  done
}

desktop_components_show_suggestions() {
  local desktop=$1 component package
  printf '\nDesktop detectado: %s\n' "$desktop"
  if [[ $desktop == unknown ]]; then printf 'Não foi possível identificar o desktop. Use --desktop explicitamente.\n'; return 0; fi
  if [[ $desktop == minimal ]]; then printf 'Minimal não possui sugestões automáticas de componentes.\n'; return 0; fi
  printf 'Componentes:\n'
  for component in "${DESKTOP_COMPONENT_CATEGORIES[@]}"; do
    package=$(desktop_component_package "$desktop" "$component")
    if [[ -z $package ]]; then printf '  ! %-8s indisponível para este desktop\n' "$component"
    elif is_package_installed "$package"; then printf '  = %-8s %s\n' "$component" "$package"
    elif package_available "$package"; then printf '  + %-8s %s\n' "$component" "$package"
    else printf '  ! %-8s %s (indisponível)\n' "$component" "$package"; fi
  done
}

desktop_components_plan() {
  local desktop=$1 spec=${2:-none} component package
  [[ $desktop != unknown ]] || { printf 'Desktop desconhecido; use --desktop para instalar componentes.\n' >&2; return 1; }
  parse_desktop_components "$spec" || return 1
  if [[ $desktop == minimal && ${#DESKTOP_COMPONENTS_SELECTED[@]} -gt 0 ]]; then
    printf 'Desktop minimal não aceita componentes automáticos; escolha um desktop explicitamente.\n' >&2
    return 1
  fi
  for component in "${DESKTOP_COMPONENTS_SELECTED[@]}"; do
    package=$(desktop_component_package "$desktop" "$component")
    [[ -n $package ]] || { printf 'Componente %s indisponível para %s.\n' "$component" "$desktop" >&2; return 1; }
    plan_package "$package"
  done
}

desktop_components_interactive_select() {
  local desktop=$1 answer
  [[ -t 0 && $desktop != minimal && -z ${DESKTOP_COMPONENTS_SPEC:-} ]] || return 0
  desktop_components_show_suggestions "$desktop"
  printf 'Componentes [terminal,browser,store,files,editor,archive|all|none] (none): '
  read -r answer
  DESKTOP_COMPONENTS_SPEC=${answer:-none}
  parse_desktop_components "$DESKTOP_COMPONENTS_SPEC"
}

desktop_apps_usage() {
  cat <<'EOF'
Uso:
  ./archtools desktop-apps suggest [--desktop DESKTOP]
  ./archtools desktop-apps install COMPONENTES [--desktop DESKTOP] [--dry-run] [--yes]
EOF
}

desktop_apps_cli_main() {
  local action=${1:-} selection='' explicit_desktop='' desktop plan_status=0
  [[ -n $action ]] && shift || true
  if [[ $action == install ]]; then selection=${1:-}; [[ -n $selection && $selection != --* ]] && shift || { die 'Seleção de componentes ausente.'; return 1; }; fi
  while (($#)); do case "$1" in
    --desktop) explicit_desktop=${2:-}; shift 2;; --dry-run) DRY_RUN=1; shift;;
    --yes) ASSUME_YES=1; shift;; --verbose) VERBOSE=1; shift;;
    --help|-h) desktop_apps_usage; return 0;; *) die "Opção inválida: $1. Use --help.";; esac; done
  [[ -z $explicit_desktop || $(normalize_desktop "$explicit_desktop") != unknown ]] || die "Desktop inválido: $explicit_desktop"
  desktop=$(detect_current_desktop "$explicit_desktop")
  case "$action" in
    suggest)
      READ_ONLY_ACTION=1; require_supported_system; desktop_components_show_suggestions "$desktop"
      ;;
    install)
      [[ $desktop != unknown ]] || die 'Desktop desconhecido; use --desktop.'
      require_supported_system
      DESKTOP=$desktop; USAGE_PROFILE=desktop; PROFILE=desktop; archtools_reset_plan
      desktop_components_plan "$desktop" "$selection" || return 1
      validate_plan_pre_execution || plan_status=$?
      archtools_show_module_plan desktop-apps
      (( plan_status == 0 )) || { log ERROR 'Plano inválido; nenhuma alteração foi executada.'; trap - ERR; return "$plan_status"; }
      ((${#PLAN_PACKAGES[@]})) || { log INFO 'Nenhum componente selecionado; nenhuma alteração foi executada.'; return 0; }
      (( DRY_RUN )) && { log INFO 'Dry-run concluído: nenhuma alteração foi feita nem estado persistente criado.'; return 0; }
      init_logger
      confirm_plan || { log INFO 'Cancelado pelo usuário.'; return 0; }
      begin_transaction desktop-apps
      execute_plan || return 1
      validate_plan || { transaction_abort_and_rollback 'falha na validação de desktop-apps'; return 1; }
      commit_transaction
      ;;
    help|-h|--help|'') desktop_apps_usage ;;
    *) die "Ação desktop-apps inválida: $action" ;;
  esac
}
