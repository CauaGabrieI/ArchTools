#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT

source "$root/lib/logger.sh"
source "$root/lib/state.sh"
source "$root/lib/transaction.sh"
source "$root/lib/packages.sh"
source "$root/lib/rollback.sh"
confirm_plan() { return 0; }

declare -A installed=() service_state=()
PREFLIGHT_FAIL=0 RESOLVE_SHARED=0 REMOVE_FAIL=0 COMPENSATION_FAIL=0 REMOVE_CALLS=0 SERVICE_CHANGES=0
is_package_installed() { [[ ${installed[$1]:-0} == 1 ]]; }
systemctl() {
  [[ $1 == is-enabled ]] || return 1
  printf '%s\n' "${service_state[$2]:-disabled}"
  [[ ${service_state[$2]:-disabled} == enabled ]]
}
sudo() {
  if [[ $1 == pacman && $2 == -Rs && $3 == --print ]]; then
    (( PREFLIGHT_FAIL == 0 )) || return 1
    printf 'app-a\nlib-b\ndependency-d\n'
    (( RESOLVE_SHARED == 0 )) || printf 'shared-c\n'
    return 0
  fi
  if [[ $1 == pacman && $2 == -Rns ]]; then
    REMOVE_CALLS=$((REMOVE_CALLS + 1))
    [[ $3 == -- && $4 == app-a && $5 == lib-b && ${6:-} == '' ]]
    (( REMOVE_FAIL == 0 )) || return 1
    installed[app-a]=0; installed[lib-b]=0; installed[dependency-d]=0
    return 0
  fi
  if [[ $1 == pacman && $2 == -S ]]; then installed[app-a]=1; installed[lib-b]=1; installed[dependency-d]=1; return 0; fi
  if [[ $1 == rm ]]; then command rm "${@:2}"; return 0; fi
  if [[ $1 == systemctl ]]; then
    local action=$2 service=$3
    if [[ $action == enable && $COMPENSATION_FAIL == 1 ]]; then return 1; fi
    case "$action" in enable) service_state[$service]=enabled;; disable) service_state[$service]=disabled;; mask) service_state[$service]=masked;; *) return 1;; esac
    SERVICE_CHANGES=$((SERVICE_CHANGES + 1)); return 0
  fi
  return 1
}

setup_applied_install() {
  local name=$1
  STATE_DIR="$task_tmp/$name"; RUN_ID="$name-install"; DRY_RUN=0; LOG_FILE=''; APP_ID=arch-smart-postinstall
  DESKTOP=gnome; PROFILE=desktop; ASSUME_YES=1
  TRANSACTION_ID=''; TRANSACTION_STATUS=''; TRANSACTION_MODULE=''
  installed=([app-a]=1 [lib-b]=1 [dependency-d]=1 [shared-c]=1); service_state=([display.service]=enabled)
  PREFLIGHT_FAIL=0; RESOLVE_SHARED=0; REMOVE_FAIL=0; COMPENSATION_FAIL=0; REMOVE_CALLS=0; SERVICE_CHANGES=0
  init_state
  begin_transaction install
  TARGET_TRANSACTION=$TRANSACTION_ID
  record_change packages package app-a absent installed yes
  record_change packages package lib-b absent installed yes
  record_change services service display.service disabled enabled yes
  printf 'app-a\nlib-b\n' > "$STATE_DIR/installed-packages.txt"
  printf 'shared-c\n' > "$STATE_DIR/existing-packages.txt"
  printf 'display.service|disabled|enabled\n' > "$STATE_DIR/services.txt"
  commit_transaction
  RUN_ID="$name-rollback"; TRANSACTION_ID=''; TRANSACTION_STATUS=''; TRANSACTION_MODULE=''
}

# Dependency-related packages are preflighted and removed in one batch.
setup_applied_install success
rollback_run
[[ $REMOVE_CALLS == 1 && ${installed[app-a]} == 0 && ${installed[lib-b]} == 0 && ${installed[dependency-d]} == 0 && ${installed[shared-c]} == 1 ]]
[[ ${service_state[display.service]} == disabled ]]
[[ ! -s $STATE_DIR/installed-packages.txt && ! -s $STATE_DIR/services.txt ]]
grep -Fqx shared-c "$STATE_DIR/existing-packages.txt"
[[ $(rollback_target_status "$TARGET_TRANSACTION") == rolled_back ]]
ROLLBACK_TRANSACTION=$TRANSACTION_ID
[[ $(rollback_target_status "$ROLLBACK_TRANSACTION") == committed ]]
awk -F '\t' -v id="$ROLLBACK_TRANSACTION" '$1==id && $4=="rollback" && $5=="committed" {ok=1} END {exit !ok}' "$STATE_DIR/runs.tsv"
[[ ! -e $STATE_DIR/.lock ]]
changes=$(list_changes)
[[ $changes == *'Current changes'* && $changes == *'History'* && $changes == *"transaction=$TARGET_TRANSACTION module=install status=rolled_back"* && $changes != *'  + app-a'* ]]

# A failed package preflight aborts before services or packages mutate.
setup_applied_install preflight
PREFLIGHT_FAIL=1
if rollback_run; then exit 1; fi
[[ $REMOVE_CALLS == 0 && $SERVICE_CHANGES == 0 && ${service_state[display.service]} == enabled ]]
[[ $(rollback_target_status "$TARGET_TRANSACTION") == committed ]]
[[ $(rollback_target_status "$TRANSACTION_ID") == aborted && ! -e $STATE_DIR/.lock ]]
[[ $(grep -c '^app-a$' "$STATE_DIR/installed-packages.txt") == 1 ]]

# A shared preexisting package in pacman's resolved set is rejected before mutation.
setup_applied_install shared
RESOLVE_SHARED=1
if rollback_run; then exit 1; fi
[[ $REMOVE_CALLS == 0 && $SERVICE_CHANGES == 0 && ${installed[shared-c]} == 1 ]]
[[ $(rollback_target_status "$TARGET_TRANSACTION") == committed ]]
[[ $(rollback_target_status "$TRANSACTION_ID") == aborted && ! -e $STATE_DIR/.lock ]]

# A package failure after service rollback is compensated.
setup_applied_install compensated
REMOVE_FAIL=1
if rollback_run; then exit 1; fi
[[ $REMOVE_CALLS == 1 && ${service_state[display.service]} == enabled ]]
[[ ${installed[app-a]} == 1 && ${installed[lib-b]} == 1 ]]
[[ $(rollback_target_status "$TARGET_TRANSACTION") == committed ]]
[[ $(rollback_target_status "$TRANSACTION_ID") == aborted && ! -e $STATE_DIR/.lock ]]
grep -Fqx 'display.service|disabled|enabled' "$STATE_DIR/services.txt"

# A failed compensation is explicit and current state mirrors the partial result.
setup_applied_install partial
REMOVE_FAIL=1; COMPENSATION_FAIL=1
if rollback_run; then exit 1; fi
[[ ${service_state[display.service]} == disabled ]]
[[ $(rollback_target_status "$TARGET_TRANSACTION") == partial ]]
[[ $(rollback_target_status "$TRANSACTION_ID") == rollback_failed && ! -e $STATE_DIR/.lock ]]
[[ ! -s $STATE_DIR/services.txt ]]
grep -Fqx 'status=rollback_failed' "$STATE_DIR/last-run"
grep -Fq '"status": "rollback_failed"' "$STATE_DIR/state.json"
partial_changes=$(list_changes)
[[ $partial_changes != *'display.service|disabled|enabled'* ]]

echo 'test_rollback_lifecycle: ok'
