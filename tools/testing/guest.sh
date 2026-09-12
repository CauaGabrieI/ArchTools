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

recover_failure() (
  STATE_DIR=$STATE
  RUN_ID="failure-recovery-$(date +%s%N)"
  DRY_RUN=0; LOG_FILE=''
  source "$ROOT/lib/state.sh"
  source "$ROOT/lib/transaction.sh"
  source "$ROOT/lib/packages.sh"
  acquire_state_lock || return 1
  trap 'release_state_lock' EXIT
  transaction_recover_orphans
)

failure_file_operation() (
  local point=${1:-}
  if [[ -n $point ]]; then export ARCHTOOLS_TEST_FAILPOINT=$point
  else unset ARCHTOOLS_TEST_FAILPOINT; fi
  STATE_DIR=$STATE
  RUN_ID="failure-files-$(date +%s%N)"
  DRY_RUN=0; ASSUME_YES=1; LOG_FILE=''
  source "$ROOT/lib/logger.sh"
  source "$ROOT/lib/state.sh"
  source "$ROOT/lib/transaction.sh"
  source "$ROOT/lib/packages.sh"
  source "$ROOT/lib/executor.sh"
  source "$ROOT/lib/backup.sh"
  begin_transaction failure-files || return 1
  backup_file "$ROOT/.failure-fixture" failure-files || return 1
  printf 'modified by failure test\n' > "$ROOT/.failure-fixture" || return 1
  install_packages nano || return 1
  enable_service_safe fstrim.timer || return 1
  commit_transaction
)

failure_files() {
  local id rc doctor_output before_timer after_timer fixture backup committed_id ROOT
  worktree
  ROOT=$PWD
  fixture=$ROOT/.failure-fixture
  [[ ! -e $STATE && ! -e $fixture ]] || { fail 'Estado inicial ou fixture não está limpo'; return 1; }
  if pacman -Q nano >/dev/null 2>&1; then fail 'nano já está instalado na base'; return 1; fi
  before_timer=$(systemctl is-enabled fstrim.timer 2>/dev/null || true)
  [[ $before_timer == disabled ]] || { fail "fstrim.timer precisa iniciar desabilitado: $before_timer"; return 1; }
  printf 'original failure fixture\n' > "$fixture"
  ./archtools doctor >/dev/null || { fail 'Doctor inicial'; return 1; }

  if failure_file_operation before_commit; then fail 'Failpoint before_commit não interrompeu operação de arquivos'; return 1
  else rc=$?; fi
  [[ $rc == 86 ]] || { fail "Failpoint de arquivos retornou $rc, esperado 86"; return 1; }
  id=$(awk -F '\t' '$3=="active" {print $1; exit}' "$STATE/transactions.tsv")
  [[ -n $id ]] || { fail 'Transação active ausente'; return 1; }
  [[ $(< "$fixture") == 'modified by failure test' ]] || { fail 'Fixture não foi modificada'; return 1; }
  awk -F '\t' -v path="$fixture" '
    $6=="change" && $7=="file" && $8==path {file=1}
    $6=="change" && $7=="package" && $8=="nano" {package=1}
    $6=="change" && $7=="service" && $8=="fstrim.timer" {service=1}
    END {exit !(file && package && service)}' "$STATE/transactions/$id.tsv" ||
    { fail 'Eventos de arquivo/pacote/serviço ausentes'; return 1; }
  backup=$(awk -F '\t' -v path="$fixture" '$1==path {print $2; exit}' "$STATE/backups/manifest.tsv")
  [[ -r $backup && $(< "$backup") == 'original failure fixture' ]] || { fail 'Backup inválido'; return 1; }
  grep -Fqx -- "$fixture" "$STATE/modified-files.txt" || { fail 'Provenance de arquivo ausente'; return 1; }
  grep -Fqx nano "$STATE/installed-packages.txt" || { fail 'Provenance de pacote ausente'; return 1; }
  grep -Fq 'fstrim.timer|disabled|enabled' "$STATE/services.txt" || { fail 'Provenance de serviço ausente'; return 1; }
  [[ -d $STATE/.lock && -f $STATE/transactions/$id.pid ]] || { fail 'Lock/PID da transação interrompida ausente'; return 1; }
  if doctor_output=$(./archtools doctor); then fail 'Doctor aceitou transação incompleta'; return 1; fi
  [[ $doctor_output == *'Transação active sem processo correspondente'* ]] || { fail 'Doctor não identificou transação incompleta'; return 1; }
  pass 'before_commit detectado com arquivo, pacote, serviço e backup'

  recover_failure || { fail 'Recovery de arquivo/pacote/serviço'; return 1; }
  [[ $(awk -F '\t' -v id="$id" '$1==id {status=$3} END {print status}' "$STATE/transactions.tsv") == rolled_back ]] ||
    { fail 'Transação incompleta não foi revertida'; return 1; }
  [[ $(< "$fixture") == 'original failure fixture' ]] || { fail 'Fixture não foi restaurada'; return 1; }
  if pacman -Q nano >/dev/null 2>&1; then fail 'Pacote permaneceu após recovery'; return 1; fi
  after_timer=$(systemctl is-enabled fstrim.timer 2>/dev/null || true)
  [[ $after_timer == "$before_timer" ]] || { fail 'Serviço não foi restaurado'; return 1; }
  [[ ! -e $STATE/.lock && ! -e $STATE/transactions/$id.pid ]] || { fail 'Lock/PID residual'; return 1; }
  [[ ! -s $STATE/modified-files.txt && ! -s $STATE/installed-packages.txt && ! -s $STATE/services.txt ]] ||
    { fail 'Provenance residual após recovery'; return 1; }
  ./archtools doctor >/dev/null || { fail 'Doctor após recovery'; return 1; }
  pass 'recovery restaurou arquivo, pacote, serviço e lock'

  failure_file_operation || { fail 'Reexecução normal após recovery'; return 1; }
  [[ $(< "$fixture") == 'modified by failure test' ]] || { fail 'Reexecução não modificou fixture'; return 1; }
  committed_id=$(awk -F '\t' '$3=="committed" && $4=="failure-files" {id=$1} END {print id}' "$STATE/transactions.tsv")
  [[ -n $committed_id ]] && awk -F '\t' -v path="$fixture" '$6=="change" && $7=="file" && $8==path {found=1} END {exit !found}' \
    "$STATE/transactions/$committed_id.tsv" || { fail 'Backup reutilizado não registrou alteração na nova transação'; return 1; }
  ./install.sh --rollback --yes || { fail 'Rollback após reexecução'; return 1; }
  [[ $(< "$fixture") == 'original failure fixture' ]] || { fail 'Rollback final não restaurou fixture'; return 1; }
  if pacman -Q nano >/dev/null 2>&1; then fail 'Pacote permaneceu após rollback final'; return 1; fi
  [[ $(systemctl is-enabled fstrim.timer 2>/dev/null || true) == "$before_timer" ]] || { fail 'Serviço incorreto após rollback final'; return 1; }
  [[ ! -e $STATE/.lock && ! -s $STATE/modified-files.txt && ! -s $STATE/installed-packages.txt && ! -s $STATE/services.txt ]] ||
    { fail 'Estado residual após rollback final'; return 1; }
  ./archtools doctor >/dev/null || { fail 'Doctor após rollback final'; return 1; }
  pass 'reexecução e rollback restauraram fixture, pacote e serviço'
  (( FAILURES == 0 ))
}

failure() {
  local scenario=${1:-} point expected_status rc id changes doctor_output before_network after_network
  case $scenario in
    files) failure_files; return;;
    begin) point=after_transaction_begin; expected_status=aborted;;
    package) point=after_package_install; expected_status=rolled_back;;
    service) point=after_service_enable; expected_status=rolled_back;;
    commit) point=before_commit; expected_status=rolled_back;;
    *) fail "Cenário de falha inválido: $scenario"; return 1;;
  esac
  worktree
  [[ ! -e $STATE ]] || { fail 'Estado inicial do cenário não está limpo'; return 1; }
  if pacman -Q networkmanager >/dev/null 2>&1; then fail 'networkmanager já estava instalado na base'; return 1; fi
  before_network=$(systemctl is-enabled NetworkManager.service 2>/dev/null || true)
  ./archtools doctor >/dev/null || { fail 'Doctor inicial'; return 1; }

  if env ARCHTOOLS_TEST_FAILPOINT="$point" ./install.sh --hardware-profile vm --usage-profile minimal --desktop minimal --yes --no-reboot; then
    fail "Failpoint $point não interrompeu a instalação"; return 1
  else rc=$?; fi
  [[ $rc == 86 ]] || { fail "Failpoint $point retornou $rc, esperado 86"; return 1; }
  id=$(awk -F '\t' '$3=="active" {print $1; exit}' "$STATE/transactions.tsv")
  [[ -n $id ]] || { fail 'Transação active ausente após falha controlada'; return 1; }
  changes=$(awk -F '\t' '$6=="change" {n++} END {print n+0}' "$STATE/transactions/$id.tsv")
  case $scenario in
    begin) [[ $changes == 0 && ! -s $STATE/installed-packages.txt && ! -s $STATE/services.txt ]] || { fail 'Mutação antes do failpoint begin'; return 1; };;
    package) (( changes >= 1 )) && grep -Fqx networkmanager "$STATE/installed-packages.txt" || { fail 'Pacote sem provenance após failpoint package'; return 1; };;
    service|commit)
      (( changes >= 2 )) && grep -Fqx networkmanager "$STATE/installed-packages.txt" &&
        grep -Fq 'NetworkManager.service|disabled|enabled' "$STATE/services.txt" ||
        { fail 'Pacote ou serviço sem provenance após falha'; return 1; }
      ;;
  esac
  [[ -d $STATE/.lock && -f $STATE/transactions/$id.pid ]] || { fail 'Lock ou PID ausente na transação interrompida'; return 1; }
  if doctor_output=$(./archtools doctor); then fail 'Doctor aceitou transação incompleta'; return 1; fi
  [[ $doctor_output == *'Transação active sem processo correspondente'* && $doctor_output == *'Doctor: ISSUES FOUND'* ]] ||
    { fail 'Doctor não identificou a transação incompleta'; return 1; }
  pass "falha $scenario detectada pelo doctor"

  recover_failure || { fail "Recovery do cenário $scenario"; return 1; }
  [[ $(awk -F '\t' -v id="$id" '$1==id {status=$3} END {print status}' "$STATE/transactions.tsv") == "$expected_status" ]] ||
    { fail "Status incorreto após recovery de $scenario"; return 1; }
  ! awk -F '\t' -v id="$id" '$1==id && $3=="committed" {found=1} END {exit !found}' "$STATE/transactions.tsv" ||
    { fail 'Transação falha apareceu como committed'; return 1; }
  [[ ! -e $STATE/.lock && ! -e $STATE/transactions/$id.pid ]] || { fail 'Lock/PID residual após recovery'; return 1; }
  [[ ! -s $STATE/installed-packages.txt && ! -s $STATE/services.txt && ! -s $STATE/modified-files.txt ]] ||
    { fail 'Provenance residual após recovery'; return 1; }
  [[ ! -s $STATE/backups/manifest.tsv ]] || { fail 'Backup inesperado após perfil minimal'; return 1; }
  if pacman -Q networkmanager >/dev/null 2>&1; then fail 'Pacote gerenciado permaneceu após recovery'; return 1; fi
  after_network=$(systemctl is-enabled NetworkManager.service 2>/dev/null || true)
  [[ $after_network == "$before_network" ]] || { fail "Serviço não restaurado: $before_network -> $after_network"; return 1; }
  ./archtools doctor >/dev/null || { fail 'Doctor após recovery'; return 1; }
  pass "recovery $scenario consistente"

  minimal_install || { fail "Reexecução normal após $scenario"; return 1; }
  ./archtools doctor >/dev/null || { fail 'Doctor após reexecução normal'; return 1; }
  ./install.sh --rollback --yes || { fail "Rollback da reexecução após $scenario"; return 1; }
  [[ ! -e $STATE/.lock && ! -s $STATE/installed-packages.txt && ! -s $STATE/services.txt ]] ||
    { fail 'Estado residual após rollback da reexecução'; return 1; }
  ./archtools doctor >/dev/null || { fail 'Doctor após rollback da reexecução'; return 1; }
  pass "reexecução e rollback após $scenario"
  (( FAILURES == 0 ))
}

mode=${1:-quick}
case $mode in
  quick) quick;;
  integration) integration "${2:-minimal}";;
  idempotency) idempotency;;
  rollback) rollback;;
  failure) failure "${2:-}";;
  *) printf '[FAIL] Modo inválido: %s\n' "$mode" >&2; exit 2;;
esac
