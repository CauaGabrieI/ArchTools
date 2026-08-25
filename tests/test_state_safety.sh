#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT
STATE_DIR="$task_tmp/state"; RUN_ID=state-safety; APP_ID=arch-smart-postinstall; LOG_FILE=''; TRANSACTION_ID=test-transaction
source "$root/lib/state.sh"
init_state
[[ $(stat -c %a "$STATE_DIR") == 700 && $(stat -c %a "$STATE_DIR/transactions.tsv") == 600 ]]

mv_marker="$task_tmp/mv-called"
mv() { : > "$mv_marker"; command mv "$@"; }
printf 'atomic-content\n' | atomic_write "$STATE_DIR/atomic.txt"
[[ -e $mv_marker && $(< "$STATE_DIR/atomic.txt") == atomic-content && $(stat -c %a "$STATE_DIR/atomic.txt") == 600 ]]
! find "$STATE_DIR" -maxdepth 1 -name '.atomic.*' | grep -q .
unset -f mv

acquire_state_lock
if (source "$root/lib/state.sh"; STATE_DIR="$STATE_DIR"; acquire_state_lock); then exit 1; fi
release_state_lock

signal_state="$task_tmp/signal-state"
env TEST_ROOT="$root" TEST_STATE="$signal_state" bash -c '
  STATE_DIR=$TEST_STATE
  source "$TEST_ROOT/lib/state.sh"
  acquire_state_lock
  : > "$TEST_STATE/ready"
  while :; do sleep 1; done
' &
signal_pid=$!
for _ in 1 2 3 4 5; do [[ -e $signal_state/ready ]] && break; sleep 1; done
[[ -e $signal_state/.lock/pid ]]
kill -TERM "$signal_pid"
set +e; wait "$signal_pid"; signal_rc=$?; set -e
[[ $signal_rc == 143 && ! -e $signal_state/.lock ]]

DRY_RUN=0
source "$root/lib/transaction.sh"
printf 'orphan\told-run\tactive\tinstall\tdate\n' >> "$STATE_DIR/transactions.tsv"
: > "$STATE_DIR/transactions/orphan.tsv"
printf '99999999\n' > "$STATE_DIR/transactions/orphan.pid"
begin_transaction install
awk -F '\t' '$1=="orphan" && $3=="rolled_back" {found=1} END {exit !found}' "$STATE_DIR/transactions.tsv"
abort_transaction cleanup
rollback_transaction

echo 'test_state_safety: ok'
