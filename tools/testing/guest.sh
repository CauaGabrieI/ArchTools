#!/usr/bin/env bash
# Runs only inside the disposable nspawn guest. The host project is mounted RO.
set -Eeuo pipefail

[[ $(cat /etc/archtools-nspawn-test 2>/dev/null || true) == archtools-nspawn-v1:test ]] || {
  printf '[FAIL] Ambiente nspawn ArchTools não identificado.\n' >&2; exit 1;
}
[[ $(systemd-detect-virt --container 2>/dev/null || true) == systemd-nspawn ]] || {
  printf '[FAIL] Não está em systemd-nspawn.\n' >&2; exit 1;
}
[[ -d /run/systemd/system ]] || { printf '[FAIL] systemd não está ativo no container.\n' >&2; exit 1; }

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
STATE=/root/.local/state/arch-smart-postinstall
FAILURES=0
declare -a TEMP_FILES=()
cleanup() {
  local path
  for path in "${TEMP_FILES[@]}"; do rm -f -- "$path"; done
}
trap cleanup EXIT
pass() { printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }
check() {
  local label=$1; shift
  if "$@"; then pass "$label"; else fail "$label"; fi
}
service_status() {
  local unit=$1 enabled active
  enabled=$(systemctl is-enabled "$unit" 2>/dev/null || true)
  active=$(systemctl is-active "$unit" 2>/dev/null || true)
  [[ -n $enabled ]] || enabled=unsupported-in-container
  if [[ $enabled == not-found ]]; then active=not-installed
  else
    case $active in
      active) active=running;;
      failed) active=failed;;
      inactive|activating|deactivating) ;;
      *) active=unsupported-in-container;;
    esac
  fi
  printf '[SERVICE] %s enabled=%s runtime=%s\n' "$unit" "$enabled" "$active"
}
worktree() {
  mkdir -p /root/ArchTools-work
  cp -a --reflink=auto -- /opt/ArchTools/. /root/ArchTools-work/
  cd /root/ArchTools-work
}
minimal_install() {
  ./install.sh --hardware-profile vm --usage-profile minimal --desktop minimal --yes --no-reboot
}
quick() {
  local test
  cd "$ROOT"
  for test in tests/test_*.sh; do
    [[ $test == tests/test_nspawn.sh ]] && continue # host-side guard tests
    check "$(basename "$test")" bash "$test"
  done
  check 'bash -n' bash -c 'for f in install.sh archtools lib/*.sh tools/*.sh tools/testing/*.sh hardware/*.sh drivers/*.sh desktop/*.sh profiles/hardware/*.sh profiles/usage/*.sh services/*.sh; do bash -n "$f" || exit; done'
  check 'doctor' ./archtools doctor
  check 'detecção' ./install.sh --detect-only
  check 'dry-run minimal' ./install.sh --hardware-profile vm --usage-profile minimal --desktop minimal --dry-run
  check 'dry-run desktop GNOME' ./install.sh --hardware-profile vm --usage-profile desktop --desktop gnome --desktop-preset minimal --dry-run
  check 'dry-run development' ./install.sh --hardware-profile vm --usage-profile development --desktop minimal --dry-run
  (( FAILURES == 0 ))
}
integration() {
  local scenario=${1:-minimal}
  worktree
  case $scenario in
    minimal) check 'install minimal' minimal_install;;
    desktop) check 'install desktop GNOME' ./install.sh --hardware-profile vm --usage-profile desktop --desktop gnome --desktop-preset minimal --yes --no-reboot;;
    development) check 'install development' ./install.sh --hardware-profile vm --usage-profile development --desktop minimal --yes --no-reboot;;
    server) check 'install server' ./install.sh --hardware-profile vm --usage-profile server --desktop minimal --yes --no-reboot;;
    gaming-dry-run) check 'gaming dry-run' ./install.sh --hardware-profile vm --usage-profile gaming --desktop gnome --desktop-preset minimal --dry-run;;
    *) fail "Cenário inválido: $scenario";;
  esac
  check 'doctor após cenário' ./archtools doctor
  if [[ $scenario != gaming-dry-run ]]; then
    check 'transação de instalação confirmada' awk -F '\t' '$3=="committed" && $4=="install" {found=1} END {exit !found}' "$STATE/transactions.tsv"
    check 'pacotes gerenciados registrados' test -s "$STATE/installed-packages.txt"
    check 'list-changes' ./install.sh --list-changes
  fi
  service_status NetworkManager.service
  service_status fstrim.timer
  if [[ $scenario == desktop ]]; then service_status gdm.service; fi
  (( FAILURES == 0 ))
}
idempotency() {
  local before after before_metadata after_metadata last_tx changes
  worktree
  check 'primeira instalação minimal' minimal_install
  (( FAILURES == 0 )) || return 1
  before=$(mktemp); TEMP_FILES+=("$before")
  after=$(mktemp); TEMP_FILES+=("$after")
  before_metadata=$(mktemp); TEMP_FILES+=("$before_metadata")
  after_metadata=$(mktemp); TEMP_FILES+=("$after_metadata")
  {
    pacman -Qq | sort
    sort "$STATE/installed-packages.txt" "$STATE/services.txt" "$STATE/modified-files.txt"
  } > "$before"
  stat -c '%n %y %s' "$STATE/installed-packages.txt" "$STATE/services.txt" \
    "$STATE/modified-files.txt" "$STATE/backups/manifest.tsv" > "$before_metadata"
  check 'segunda instalação idêntica' minimal_install
  (( FAILURES == 0 )) || return 1
  {
    pacman -Qq | sort
    sort "$STATE/installed-packages.txt" "$STATE/services.txt" "$STATE/modified-files.txt"
  } > "$after"
  stat -c '%n %y %s' "$STATE/installed-packages.txt" "$STATE/services.txt" \
    "$STATE/modified-files.txt" "$STATE/backups/manifest.tsv" > "$after_metadata"
  if diff -u "$before" "$after"; then pass 'pacotes/serviços/arquivos gerenciados estáveis';
  else fail 'estado gerenciado mudou no segundo run'; fi
  if diff -u "$before_metadata" "$after_metadata"; then pass 'estado e backups não regravados';
  else fail 'arquivos de estado foram regravados no segundo run'; fi
  last_tx=$(awk -F '\t' '$3=="committed" && $4=="install" {id=$1} END {print id}' "$STATE/transactions.tsv")
  [[ -n $last_tx ]] || { fail 'segunda transação ausente'; return 1; }
  changes=$(awk -F '\t' '$6=="change" {n++} END {print n+0}' "$STATE/transactions/$last_tx.tsv")
  if (( changes == 0 )); then pass 'segundo run sem alterações de transação';
  else fail "segundo run registrou $changes alterações"; fi
  (( FAILURES == 0 ))
}
rollback() {
  local initial_packages managed_packages before_network after_network package left=0
  worktree
  initial_packages=$(mktemp); TEMP_FILES+=("$initial_packages")
  managed_packages=$(mktemp); TEMP_FILES+=("$managed_packages")
  pacman -Qq | sort > "$initial_packages"
  before_network=$(systemctl is-enabled NetworkManager.service 2>/dev/null || true)
  check 'instalação controlada' minimal_install
  (( FAILURES == 0 )) || return 1
  cp -- "$STATE/installed-packages.txt" "$managed_packages"
  [[ -s $managed_packages ]] || { fail 'instalação não alterou pacotes'; return 1; }
  check 'rollback ArchTools' ./install.sh --rollback --yes
  (( FAILURES == 0 )) || return 1
  while IFS= read -r package; do
    [[ -n $package ]] || continue
    if ! grep -Fxq -- "$package" "$initial_packages" && pacman -Q "$package" >/dev/null 2>&1; then
      printf '[DIFF] Pacote gerenciado ainda instalado: %s\n' "$package" >&2
      left=$((left + 1))
    fi
  done < "$managed_packages"
  if (( left == 0 )); then pass 'pacotes gerenciados removidos'; else fail "$left pacote(s) gerenciado(s) permaneceram"; fi
  if [[ ! -s $STATE/installed-packages.txt && ! -s $STATE/services.txt && ! -s $STATE/modified-files.txt ]]; then
    pass 'estado gerenciado limpo'
  else fail 'estado gerenciado residual'; fi
  after_network=$(systemctl is-enabled NetworkManager.service 2>/dev/null || true)
  if [[ $before_network == "$after_network" ]]; then pass 'enablement do serviço restaurado';
  else fail "NetworkManager: antes=${before_network:-unknown}, depois=${after_network:-unknown}"; fi
  check 'transação de instalação revertida' awk -F '\t' '$3=="rolled_back" && $4=="install" {found=1} END {exit !found}' "$STATE/transactions.tsv"
  check 'list-changes após rollback' ./install.sh --list-changes
  # Dependencies, caches, journals and transaction history are deliberately excluded.
  check 'doctor após rollback' ./archtools doctor
  (( FAILURES == 0 ))
}

mode=${1:-quick}
case $mode in
  quick) quick;;
  integration) integration "${2:-minimal}";;
  idempotency) idempotency;;
  rollback) rollback;;
  *) printf '[FAIL] Modo inválido: %s\n' "$mode" >&2; exit 2;;
esac
