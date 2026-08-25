#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
state=$(mktemp -d)
trap 'rm -rf "$state"' EXIT

STATE_DIR="$state/arch-smart-postinstall"
PROJECT_DIR=$root
RUN_ID=run-lifecycle-test
DRY_RUN=0
LOG_FILE=''
PLAN_PACKAGES=()
PLAN_SERVICES_ENABLE=()
source "$root/lib/transaction.sh"
source "$root/lib/packages.sh"
source "$root/lib/executor.sh"
source "$root/lib/logger.sh"
source "$root/lib/state.sh"
init_state

declare -A installed=([good]=0 [failed]=0)
is_package_installed() { [[ ${installed[$1]:-0} == 1 ]]; }
package_available() { return 0; }
sudo() {
  [[ ${SUDO_FAIL:-0} == 0 ]] || return 1
  if [[ ${1:-} == pacman ]]; then installed[good]=1; fi
  return 0
}

PLAN_PACKAGES=(good)
execute_plan
[[ $TRANSACTION_STATUS == committed ]]
grep -q $'\tchange\tpackage\tgood\tabsent\tinstalled\tyes$' "$STATE_DIR/transactions/$TRANSACTION_ID.tsv"

TRANSACTION_ID=''; TRANSACTION_STATUS=''; TRANSACTION_MODULE=''
PLAN_PACKAGES=(failed)
SUDO_FAIL=1
if execute_plan; then exit 1; fi
[[ $TRANSACTION_STATUS == rolled_back ]]
! grep -q $'\tchange\tpackage\tfailed\t' "$STATE_DIR/transactions/$TRANSACTION_ID.tsv"
SUDO_FAIL=0

SERVICE_ENABLED=0
systemctl() {
  if [[ ${1:-} == is-enabled && ${SERVICE_ENABLED} == 1 ]]; then
    printf 'enabled\n'
    return 0
  fi
  printf 'disabled\n'
  return 1
}
sudo() {
  if [[ ${1:-} == systemctl && ${2:-} == enable ]]; then SERVICE_ENABLED=1; fi
  return 0
}

TRANSACTION_ID=''; TRANSACTION_STATUS=''; TRANSACTION_MODULE=''
PLAN_PACKAGES=()
PLAN_SERVICES_ENABLE=(test.service)
execute_plan
[[ $TRANSACTION_STATUS == committed ]]
grep -q $'\tchange\tservice\ttest.service\tdisabled\tenabled\tyes$' "$STATE_DIR/transactions/$TRANSACTION_ID.tsv"

SERVICE_ENABLED=0
TRANSACTION_ID=''; TRANSACTION_STATUS=''; TRANSACTION_MODULE=''
PLAN_SERVICES_ENABLE=(failed.service)
systemctl() { printf 'disabled\n'; return 1; }
if execute_plan; then exit 1; fi
[[ $TRANSACTION_STATUS == rolled_back ]]
! grep -q $'\tchange\tservice\tfailed.service\t' "$STATE_DIR/transactions/$TRANSACTION_ID.tsv"

TRANSACTION_ID=''; TRANSACTION_STATUS=''; TRANSACTION_MODULE=''
PLAN_PACKAGES=()
PLAN_SERVICES_ENABLE=()
execute_plan
[[ $TRANSACTION_STATUS == committed ]]
[[ $(grep -c $'\tstatus\ttransaction\tstatus\tactive\tcommitted\tyes$' "$STATE_DIR/transactions/$TRANSACTION_ID.tsv") == 1 ]]

echo 'test_transaction_lifecycle: ok'
