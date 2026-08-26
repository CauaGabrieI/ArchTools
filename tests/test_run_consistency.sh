#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT

STATE_DIR="$task_tmp/state"; RUN_ID=success-source-run; DRY_RUN=0; LOG_FILE=''; APP_ID=arch-smart-postinstall
DESKTOP=minimal; PROFILE=minimal
source "$root/lib/logger.sh"
source "$root/lib/state.sh"
source "$root/lib/transaction.sh"
source "$root/lib/packages.sh"

declare -A installed=([good]=0 [failed]=1)
is_package_installed() { [[ ${installed[$1]:-0} == 1 ]]; }
sudo() { if [[ $1 == pacman && $2 == -R ]]; then installed[${@: -1}]=0; return 0; fi; return 1; }

begin_transaction install
success_transaction=$TRANSACTION_ID
installed[good]=1
record_change packages package good absent installed yes
state_add_unique "$STATE_DIR/installed-packages.txt" good
commit_transaction

[[ $TRANSACTION_STATUS == committed ]]
[[ $(awk -F '\t' -v id="$success_transaction" '$1==id {count++} END {print count+0}' "$STATE_DIR/runs.tsv") == 1 ]]
awk -F '\t' -v id="$success_transaction" '$1==id && $2==id && $3=="success-source-run" && $4=="install" && $5=="committed" {found=1} END {exit !found}' "$STATE_DIR/runs.tsv"
grep -Fqx "transaction=$success_transaction" "$STATE_DIR/last-run"
grep -Fqx 'status=committed' "$STATE_DIR/last-run"
grep -Fq '"status": "committed"' "$STATE_DIR/state.json"
grep -Fq "\"transaction\": \"$success_transaction\"" "$STATE_DIR/state.json"
awk -F '\t' -v id="$success_transaction" '$1==id {status=$3} END {exit !(status=="committed")}' "$STATE_DIR/transactions.tsv"

acquire_state_lock
save_run_result committed
release_state_lock
[[ $(awk -F '\t' -v id="$success_transaction" '$1==id {count++} END {print count+0}' "$STATE_DIR/runs.tsv") == 1 ]]

RUN_ID=failure-source-run; TRANSACTION_ID=''; TRANSACTION_STATUS=''; TRANSACTION_MODULE=''
begin_transaction install
failure_transaction=$TRANSACTION_ID
record_change packages package failed absent installed yes
state_add_unique "$STATE_DIR/installed-packages.txt" failed
abort_transaction simulated
rollback_transaction

[[ $TRANSACTION_STATUS == rolled_back && ${installed[failed]} == 0 ]]
[[ $(awk -F '\t' -v id="$failure_transaction" '$1==id {count++} END {print count+0}' "$STATE_DIR/runs.tsv") == 1 ]]
awk -F '\t' -v id="$failure_transaction" '$1==id && $2==id && $3=="failure-source-run" && $5=="rolled_back" {found=1} END {exit !found}' "$STATE_DIR/runs.tsv"
awk -F '\t' -v id="$failure_transaction" '$1==id {status=$3} END {exit !(status=="rolled_back")}' "$STATE_DIR/transactions.tsv"
! awk -F '\t' -v id="$failure_transaction" '$1==id && $3=="committed" {found=1} END {exit !found}' "$STATE_DIR/transactions.tsv"
grep -Fqx "transaction=$failure_transaction" "$STATE_DIR/last-run"
grep -Fqx 'status=rolled_back' "$STATE_DIR/last-run"
grep -Fq '"status": "rolled_back"' "$STATE_DIR/state.json"
[[ ! -e $STATE_DIR/.lock ]]
[[ $(find "$STATE_DIR" -name '.runs.*' -o -name '.atomic.*' -o -name '.state.*' | wc -l) == 0 ]]

echo 'test_run_consistency: ok'
