#!/usr/bin/env bash
usage() { cat <<'EOF'
Usage: ./install.sh [options]
  --desktop gnome|kde|xfce|cinnamon|hyprland|minimal
  --desktop-components terminal,browser,store,files,editor,archive|all|none
  --hardware-profile auto|desktop|notebook|server|vm
  --usage-profile minimal|desktop|gaming|development|server
  --profile minimal|desktop|gaming (alias temporário de --usage-profile)
  --dry-run    --detect-only
  --rollback    --uninstall    --list-changes    --verbose    --yes
  --no-reboot (accepted; the program never reboots automatically)    --help
EOF
}
parse_cli() {
  local legacy_profile=''
  while (($#)); do case "$1" in
    --desktop) DESKTOP=${2:-}; shift 2;;
    --hardware-profile) HARDWARE_PROFILE=${2:-}; HARDWARE_PROFILE_EXPLICIT=1; shift 2;;
    --usage-profile) USAGE_PROFILE=${2:-}; shift 2;;
    --profile) legacy_profile=${2:-}; shift 2;;
    --desktop-components) DESKTOP_COMPONENTS_SPEC=${2:-}; shift 2;;
    --dry-run) DRY_RUN=1; shift;; --detect-only) ACTION=detect-only; shift;;
    --rollback) ACTION=rollback; shift;; --uninstall) ACTION=uninstall; shift;;
    --list-changes) ACTION=list-changes; shift;; --verbose) VERBOSE=1; shift;;
    --no-reboot) NO_REBOOT=1; shift;; --yes) ASSUME_YES=1; shift;; --help|-h) ACTION=help; shift;;
    *) die "Opção inválida: $1. Use --help.";; esac; done
  [[ -z $DESKTOP || $DESKTOP =~ ^(gnome|kde|xfce|cinnamon|hyprland|minimal)$ ]] || die "Desktop inválido: $DESKTOP"
  [[ $HARDWARE_PROFILE =~ ^(auto|desktop|notebook|server|vm)$ ]] || die "Hardware profile inválido: $HARDWARE_PROFILE"
  [[ -z $legacy_profile || $legacy_profile =~ ^(minimal|desktop|gaming)$ ]] || die "Perfil legado inválido: $legacy_profile"
  [[ -z $USAGE_PROFILE || $USAGE_PROFILE =~ ^(minimal|desktop|gaming|development|server)$ ]] || die "Usage profile inválido: $USAGE_PROFILE"
  [[ -z $legacy_profile || -z $USAGE_PROFILE || $legacy_profile == "$USAGE_PROFILE" ]] || die 'Use apenas um usage profile consistente.'
  USAGE_PROFILE=${USAGE_PROFILE:-$legacy_profile}; PROFILE=$USAGE_PROFILE
  [[ -z $DESKTOP_COMPONENTS_SPEC ]] || parse_desktop_components "$DESKTOP_COMPONENTS_SPEC" || die "Seleção de componentes inválida: $DESKTOP_COMPONENTS_SPEC"
}
