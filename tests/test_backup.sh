#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd); task_tmp=$(mktemp -d)
trap 'rm -rf -- "$task_tmp"' EXIT
PROJECT_DIR=$root; XDG_STATE_HOME="$task_tmp"; DRY_RUN=0; LOG_FILE=''; STATE_DIR="$task_tmp/state"
source "$root/lib/logger.sh"; source "$root/lib/state.sh"; source "$root/lib/backup.sh"
init_state; mkdir -p "$task_tmp/a" "$task_tmp/b"; touch "$task_tmp/a/app.conf" "$task_tmp/b/app.conf"
backup_file "$task_tmp/a/app.conf" test; backup_file "$task_tmp/b/app.conf" test; backup_file "$task_tmp/a/app.conf" test
[[ $(wc -l < "$STATE_DIR/backups/manifest.tsv") == 2 ]]
awk -F '\t' 'NR==1 {a=$2} NR==2 {b=$2} END {exit !(a != b)}' "$STATE_DIR/backups/manifest.tsv"
backup_file "$task_tmp/new.conf" test; grep -q $'\tcreated$' "$STATE_DIR/backups/manifest.tsv"
source "$root/lib/transaction.sh"
sudo() { "$@"; }
printf 'original\n' > "$task_tmp/reused.conf"
RUN_ID=backup-first
begin_transaction test
backup_file "$task_tmp/reused.conf" test
printf 'first change\n' > "$task_tmp/reused.conf"
rollback_transaction
[[ $(< "$task_tmp/reused.conf") == original ]]
RUN_ID=backup-second
begin_transaction test
backup_file "$task_tmp/reused.conf" test
awk -F '\t' -v path="$task_tmp/reused.conf" '$6=="change" && $7=="file" && $8==path {found=1} END {exit !found}' "$(transaction_event_file)"
printf 'second change\n' > "$task_tmp/reused.conf"
rollback_transaction
[[ $(< "$task_tmp/reused.conf") == original ]]
! grep -Fqx -- "$task_tmp/reused.conf" "$STATE_DIR/modified-files.txt"
echo 'test_backup: ok'
