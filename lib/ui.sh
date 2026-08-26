#!/usr/bin/env bash

ui_color_enabled() { [[ -t 1 && -z ${NO_COLOR:-} ]]; }
ui_color() { ui_color_enabled && printf '\033[%sm' "$1" || true; }
ui_reset() { ui_color_enabled && printf '\033[0m' || true; }
ui_divider() { printf '%s\n' '────────────────────────────────────────'; }
ui_header() { printf '\n'; ui_color '1;36'; printf '%s\n' "$1"; ui_reset; ui_divider; }
ui_section() { printf '\n'; ui_color '1'; printf '%s\n' "$1"; ui_reset; }
ui_ok() { ui_color '32'; printf '  ✓ '; ui_reset; printf '%s\n' "$*"; }
ui_warn() { ui_color '33'; printf '  ! '; ui_reset; printf '%s\n' "$*"; }
ui_error() { { ui_color '31'; printf '  ✗ '; ui_reset; printf '%s\n' "$*"; } >&2; }
ui_info() { printf '  › %s\n' "$*"; }
ui_key_value() { printf '  %-16s %s\n' "$1" "$2"; }

ui_title_case() {
  case "${1,,}" in
    vm) printf 'VM' ;; kde) printf 'KDE Plasma' ;; gnome) printf 'GNOME' ;;
    xfce) printf 'XFCE' ;; hyprland) printf 'Hyprland' ;; cinnamon) printf 'Cinnamon' ;;
    minimal) printf 'Minimal' ;; recommended) printf 'Recomendado' ;; custom) printf 'Personalizado' ;;
    desktop) printf 'Desktop' ;; notebook) printf 'Notebook' ;; server) printf 'Servidor' ;;
    development) printf 'Desenvolvimento' ;; gaming) printf 'Gaming' ;;
    *) printf '%s' "$1" ;;
  esac
}

banner() { ui_header 'ArchTools'; }
