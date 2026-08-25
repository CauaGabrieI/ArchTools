#!/usr/bin/env bash
usage() { cat <<'EOF'
Usage: ./install.sh [options]
  --desktop gnome|kde|xfce|cinnamon|hyprland|minimal
  --profile minimal|desktop|gaming    --dry-run    --detect-only
  --rollback    --uninstall    --list-changes    --verbose    --yes
  --no-reboot (accepted; the program never reboots automatically)    --help
EOF
}
parse_cli() {
  while (($#)); do case "$1" in
    --desktop) DESKTOP=${2:-}; shift 2;; --profile) PROFILE=${2:-}; shift 2;;
    --dry-run) DRY_RUN=1; shift;; --detect-only) ACTION=detect-only; shift;;
    --rollback) ACTION=rollback; shift;; --uninstall) ACTION=uninstall; shift;;
    --list-changes) ACTION=list-changes; shift;; --verbose) VERBOSE=1; shift;;
    --no-reboot) NO_REBOOT=1; shift;; --yes) ASSUME_YES=1; shift;; --help|-h) ACTION=help; shift;;
    *) die "Opção inválida: $1. Use --help.";; esac; done
  [[ -z $DESKTOP || $DESKTOP =~ ^(gnome|kde|xfce|cinnamon|hyprland|minimal)$ ]] || die "Desktop inválido: $DESKTOP"
  [[ -z $PROFILE || $PROFILE =~ ^(minimal|desktop|gaming)$ ]] || die "Perfil inválido: $PROFILE"
}
