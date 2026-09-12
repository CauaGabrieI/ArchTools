#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
task_tmp=$(mktemp -d)
trap 'rm -rf -- "$task_tmp"' EXIT

source "$root/lib/state.sh"
source "$root/lib/transaction.sh"
source "$root/lib/packages.sh"
source "$root/lib/executor.sh"
source "$root/lib/logger.sh"

# File-backed mocks survive the deliberately exited child process.
transaction_test_guest() { return 0; }
is_package_installed() { [[ $(< "$CASE_DIR/package") == installed ]]; }
package_available() { [[ $1 == tiny ]]; }
systemctl() {
  [[ $1 == is-enabled && $2 == fixture.service ]] || return 1
  if [[ $(< "$CASE_DIR/service") == enabled ]]; then printf 'enabled\n'; return 0; fi
  printf 'disabled\n'; return 1
}
sudo() {
  case "$1:$2" in
    pacman:-S) [[ ${*: -1} == tiny ]] || return 1; printf 'installed\n' > "$CASE_DIR/package";;
    pacman:-R) [[ ${*: -1} == tiny ]] || return 1; printf 'absent\n' > "$CASE_DIR/package";;
    systemctl:enable) [[ $3 == fixture.service ]] || return 1; printf 'enabled\n' > "$CASE_DIR/service";;
    systemctl:disable) [[ $3 == fixture.service ]] || return 1; printf 'disabled\n' > "$CASE_DIR/service";;
    *) return 1;;
  esac
}

doctor() {
  env PATH="$root/tests/mock-bin:$PATH" OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" \
    XDG_STATE_HOME="$CASE_DIR" "$root/archtools" doctor
}
latest_status() {
  awk -F '\t' -v id="$1" '$1==id {status=$3} END {print status}' "$STATE_DIR/transactions.tsv"
}

run_case() {
  local point=$1 expected_changes=$2 expected_package=$3 expected_service=$4 expected_status=$5 rc id output
  CASE_DIR="$task_tmp/$point"; mkdir -p "$CASE_DIR"
  printf 'absent\n' > "$CASE_DIR/package"
  printf 'disabled\n' > "$CASE_DIR/service"
  STATE_DIR="$CASE_DIR/arch-smart-postinstall"; RUN_ID="failure-$point"; DRY_RUN=0; ASSUME_YES=1; LOG_FILE=''
  TRANSACTION_ID=''; TRANSACTION_STATUS=''; TRANSACTION_MODULE=''
  STATE_LOCK_HELD=0; STATE_LOCK_OWNER_PID=''
  if (
    ARCHTOOLS_TEST_FAILPOINT=$point
    begin_transaction install || exit $?
    install_packages tiny || exit $?
    enable_service_safe fixture.service || exit $?
    commit_transaction
  ) > "$CASE_DIR/failure-output" 2>&1; then
    printf 'Failpoint did not stop: %s\n' "$point" >&2; exit 1
  else rc=$?; fi
  [[ $rc == 86 ]] || { cat "$CASE_DIR/failure-output" >&2; exit 1; }
  grep -Fq "[TEST FAILPOINT] $point:" "$CASE_DIR/failure-output"
  id=$(awk -F '\t' '$3=="active" {print $1; exit}' "$STATE_DIR/transactions.tsv")
  [[ -n $id && $(latest_status "$id") == active ]]
  [[ $(awk -F '\t' '$6=="change" {n++} END {print n+0}' "$STATE_DIR/transactions/$id.tsv") == "$expected_changes" ]]
  [[ $(< "$CASE_DIR/package") == "$expected_package" && $(< "$CASE_DIR/service") == "$expected_service" ]]
  [[ -d $STATE_DIR/.lock && -f $STATE_DIR/transactions/$id.pid ]]
  if output=$(doctor); then printf 'Doctor accepted an orphan: %s\n' "$point" >&2; exit 1; fi
  [[ $output == *'Transação active sem processo correspondente'* && $output == *'Doctor: ISSUES FOUND'* ]]

  RUN_ID="recovery-$point"
  acquire_state_lock
  transaction_recover_orphans
  release_state_lock
  [[ $(latest_status "$id") == "$expected_status" ]]
  awk -F '\t' -v id="$id" -v run="failure-$point" '$1==id && $3!="active" && ($2!=run || $4!="install") {bad=1} END {exit bad}' "$STATE_DIR/transactions.tsv"
  [[ ! -e $STATE_DIR/.lock && ! -e $STATE_DIR/transactions/$id.pid ]]
  [[ $(< "$CASE_DIR/package") == absent && $(< "$CASE_DIR/service") == disabled ]]
  [[ ! -s $STATE_DIR/installed-packages.txt && ! -s $STATE_DIR/services.txt ]]
  doctor >/dev/null

  # A normal equivalent operation must work after recovery, then roll back.
  RUN_ID="normal-$point"; TRANSACTION_ID=''; TRANSACTION_STATUS=''; TRANSACTION_MODULE=''
  begin_transaction install
  install_packages tiny
  enable_service_safe fixture.service
  commit_transaction
  [[ $TRANSACTION_STATUS == committed && $(< "$CASE_DIR/package") == installed && $(< "$CASE_DIR/service") == enabled ]]
  rollback_transaction
  [[ $TRANSACTION_STATUS == rolled_back && ! -e $STATE_DIR/.lock ]]
  [[ $(< "$CASE_DIR/package") == absent && $(< "$CASE_DIR/service") == disabled ]]
  doctor >/dev/null
}

run_case after_transaction_begin 0 absent disabled aborted
run_case after_package_install 1 installed disabled rolled_back
run_case after_service_enable 2 installed enabled rolled_back
run_case before_commit 2 installed enabled rolled_back

# Unknown names and an untrusted host fail before even creating state.
CASE_DIR="$task_tmp/invalid"; mkdir -p "$CASE_DIR"
STATE_DIR="$CASE_DIR/arch-smart-postinstall"
transaction_test_guest() { return 1; }
if (ARCHTOOLS_TEST_FAILPOINT='after_package_install;touch injected'; begin_transaction install) > "$CASE_DIR/output" 2>&1; then exit 1; else rc=$?; fi
[[ $rc == 2 && ! -e $STATE_DIR && ! -e $CASE_DIR/injected ]]
grep -Fq 'Failpoint de teste desconhecido' "$CASE_DIR/output"
if (ARCHTOOLS_TEST_FAILPOINT=after_transaction_begin; begin_transaction install) > "$CASE_DIR/output" 2>&1; then exit 1; else rc=$?; fi
[[ $rc == 2 && ! -e $STATE_DIR ]]
grep -Fq 'só é permitida no guest' "$CASE_DIR/output"

echo 'test_failure_recovery: ok'
