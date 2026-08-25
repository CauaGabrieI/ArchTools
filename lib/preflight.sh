#!/usr/bin/env bash

preflight_check_command() {
  local name=$1 required=$2
  if command -v "$name" >/dev/null 2>&1; then
    printf '[OK] comando: %s\n' "$name"
    if (( PREFLIGHT_VERBOSE )); then printf '     caminho: %s\n' "$(command -v "$name")"; fi
    return 0
  fi
  if [[ $required == yes ]]; then
    printf '[FAIL] comando ausente: %s\n' "$name"
    return 1
  fi
  printf '[WARN] comando opcional ausente: %s\n' "$name"
}

preflight_run() {
  local os_release=${OS_RELEASE_FILE:-/etc/os-release} os_id os_like status=0 command_name
  PREFLIGHT_VERBOSE=0
  while (($#)); do
    case "$1" in
      --verbose) PREFLIGHT_VERBOSE=1; shift;;
      --help|-h) printf 'Uso: ./archtools preflight [--verbose|--help]\n'; return 0;;
      *) printf '[FAIL] Opção inválida: %s\n' "$1" >&2; return 2;;
    esac
  done

  printf 'Preflight ArchTools\n'
  printf '[OK] Bash: %s\n' "${BASH_VERSION%%(*}"
  [[ -r $os_release ]] || { printf '[FAIL] sistema operacional: %s não pode ser lido\n' "$os_release"; status=1; }
  if [[ -r $os_release ]]; then
    os_id=$(awk -F= '$1=="ID" {gsub(/"/,"",$2); print tolower($2)}' "$os_release")
    os_like=$(awk -F= '$1=="ID_LIKE" {gsub(/"/,"",$2); print tolower($2)}' "$os_release")
    if [[ $os_id == arch || " $os_like " == *' arch '* ]]; then
      printf '[OK] sistema operacional: %s\n' "$os_id"
    else
      printf '[FAIL] sistema operacional não compatível: %s\n' "${os_id:-desconhecido}"
      status=1
    fi
  fi
  printf '[OK] arquitetura: %s\n' "$(uname -m 2>/dev/null || { status=1; printf 'desconhecida'; })"

  for command_name in bash pacman sudo systemctl awk grep sed find mktemp date uname; do
    preflight_check_command "$command_name" yes || status=1
  done
  for command_name in lscpu lspci lsblk findmnt ip iw free glxinfo vulkaninfo bluetoothctl; do
    preflight_check_command "$command_name" no || true
  done

  if [[ -d $PROJECT_DIR && -r $PROJECT_DIR ]]; then
    printf '[OK] diretório do projeto: %s\n' "$PROJECT_DIR"
  else
    printf '[FAIL] diretório do projeto indisponível: %s\n' "$PROJECT_DIR"
    status=1
  fi
  local state_parent=${STATE_DIR%/*}
  if [[ -d $state_parent && -w $state_parent ]]; then
    printf '[OK] diretório pai do estado: %s\n' "$state_parent"
  else
    printf '[FAIL] diretório pai do estado não gravável: %s\n' "$state_parent"
    status=1
  fi
  if (( PREFLIGHT_VERBOSE )); then
    printf '     estado configurado: %s\n' "$STATE_DIR"
    printf '     nenhum pacote, serviço ou arquivo será alterado\n'
  fi
  (( status == 0 )) && printf 'Preflight: OK\n' || printf 'Preflight: FALHOU\n'
  return "$status"
}