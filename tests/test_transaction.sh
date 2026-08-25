#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
state=$(mktemp -d)
trap 'rm -rf "$state"' EXIT

STATE_DIR="$state/arch-smart-postinstall"
RUN_ID=run-transaction-test
DRY_RUN=0
source "$root/lib/transaction.sh"

begin_transaction gpu
first_id=$TRANSACTION_ID
[[ $TRANSACTION_STATUS == active && -e "$STATE_DIR/transactions.tsv" ]]
record_change gpu package mesa absent installed yes
[[ $(awk -F '\t' '$6 == "change" {count++} END {print count+0}' "$STATE_DIR/transactions/$first_id.tsv") == 1 ]]
if begin_transaction audio; then exit 1; fi
commit_transaction
[[ $TRANSACTION_STATUS == committed ]]

rollback_transaction
[[ $TRANSACTION_STATUS == rolled_back ]]
if rollback_transaction; then exit 1; fi

begin_transaction audio
second_id=$TRANSACTION_ID
[[ $first_id != "$second_id" ]]
record_change audio package pipewire absent installed yes
rollback_transaction
[[ $TRANSACTION_STATUS == rolled_back ]]
grep -q $'\trollback\tphysical\trollback\tnot_implemented\tmetadata_only\tyes$' "$STATE_DIR/transactions/$second_id.tsv"

begin_transaction network
third_id=$TRANSACTION_ID
record_change network service NetworkManager.disabled disabled enabled no
if rollback_transaction; then exit 1; fi
[[ $TRANSACTION_STATUS == active ]]
abort_transaction "falha simulada"
[[ $TRANSACTION_STATUS == aborted ]]
grep -q $'\tstatus\ttransaction\tstatus\tactive\tfalha simulada\tyes$' "$STATE_DIR/transactions/$third_id.tsv"
if rollback_transaction; then exit 1; fi
[[ $TRANSACTION_STATUS == aborted ]]

begin_transaction storage
fourth_id=$TRANSACTION_ID
record_change storage package fstrim.timer absent enabled yes
abort_transaction "cancelado"
rollback_transaction
[[ $TRANSACTION_STATUS == rolled_back && $fourth_id != "$third_id" ]]
if rollback_transaction; then exit 1; fi
[[ $(awk -F '\t' '$2 == "run-transaction-test" {count++} END {print count+0}' "$STATE_DIR/transactions.tsv") == 10 ]]

TRANSACTION_ID=""; TRANSACTION_STATUS=""; DRY_RUN=0
if record_change gpu package mesa absent installed yes; then exit 1; fi

dry_state=$(mktemp -d)
STATE_DIR="$dry_state/arch-smart-postinstall"
DRY_RUN=1
begin_transaction gpu
record_change gpu package mesa absent installed yes
commit_transaction
[[ $TRANSACTION_STATUS == committed && ! -e "$dry_state/arch-smart-postinstall" ]]
DRY_RUN=0
begin_transaction storage
[[ $TRANSACTION_STATUS == active && -e "$dry_state/arch-smart-postinstall/transactions.tsv" ]]
if record_change storage package $'bad\tresource' absent installed yes; then exit 1; fi
if record_change storage package disk $'bad\nstate' installed yes; then exit 1; fi
if record_change storage package disk absent "" yes; then exit 1; fi
abort_transaction "cleanup"
[[ $(awk -F '\t' '$2 == "run-transaction-test" {count++} END {print count+0}' "$STATE_DIR/transactions.tsv") == 2 ]]
rm -rf "$dry_state"
echo 'test_transaction: ok'