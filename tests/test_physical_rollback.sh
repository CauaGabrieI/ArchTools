#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT
STATE_DIR="$task_tmp/state"; RUN_ID=physical-rollback; DRY_RUN=0; LOG_FILE=''; APP_ID=arch-smart-postinstall
source "$root/lib/logger.sh"
source "$root/lib/state.sh"
source "$root/lib/transaction.sh"
source "$root/lib/packages.sh"
source "$root/lib/executor.sh"
source "$root/lib/backup.sh"
init_state

declare -A installed=([good]=0 [second]=0) services=([test.service]=disabled)
is_package_installed() { [[ ${installed[$1]:-0} == 1 ]]; }
package_available() { return 0; }
systemctl() { [[ $1 == is-enabled ]] && { printf '%s\n' "${services[$2]:-disabled}"; [[ ${services[$2]:-disabled} == enabled ]]; }; }
sudo() {
  if [[ $1 == pacman && $2 == -S ]]; then local seen_separator=0 p; for p in "${@:3}"; do [[ $p == -- ]] && { seen_separator=1; continue; }; (( seen_separator )) && installed[$p]=1; done; [[ ${FAIL_AFTER_INSTALL:-0} == 0 ]]; return; fi
  if [[ $1 == pacman && $2 == -R ]]; then installed[${@: -1}]=0; return 0; fi
  if [[ $1 == systemctl && $2 == enable ]]; then services[$3]=enabled; return 0; fi
  if [[ $1 == systemctl && $2 == disable ]]; then services[$3]=disabled; return 0; fi
  if [[ $1 == cp ]]; then command cp "${@:2}"; return; fi
  if [[ $1 == rm ]]; then command rm "${@:2}"; return; fi
  return 1
}

begin_transaction packages
install_packages good
[[ ${installed[good]} == 1 ]]
abort_transaction simulated
rollback_transaction
[[ ${installed[good]} == 0 && $TRANSACTION_STATUS == rolled_back ]]

TRANSACTION_ID=''; TRANSACTION_STATUS=''; TRANSACTION_MODULE=''
begin_transaction services
enable_service_safe test.service
[[ ${services[test.service]} == enabled ]]
abort_transaction simulated
rollback_transaction
[[ ${services[test.service]} == disabled && $TRANSACTION_STATUS == rolled_back ]]

TRANSACTION_ID=''; TRANSACTION_STATUS=''; TRANSACTION_MODULE=''
FAIL_AFTER_INSTALL=1
installed[good]=0; installed[second]=0
PLAN_PACKAGES=(good second); PLAN_SERVICES_ENABLE=()
if execute_plan; then exit 1; fi
[[ ${installed[good]} == 0 && ${installed[second]} == 0 && $TRANSACTION_STATUS == rolled_back ]]
! grep -q $'\tcommitted\t' "$STATE_DIR/transactions.tsv"

TRANSACTION_ID=''; TRANSACTION_STATUS=''; TRANSACTION_MODULE=''; FAIL_AFTER_INSTALL=0
target="$task_tmp/config"; printf 'before\n' > "$target"
begin_transaction files
backup_file "$target" files
printf 'after\n' > "$target"
abort_transaction simulated
rollback_transaction
[[ $(< "$target") == before && $TRANSACTION_STATUS == rolled_back ]]

echo 'test_physical_rollback: ok'
