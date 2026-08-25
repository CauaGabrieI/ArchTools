#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd); task_tmp=$(mktemp -d)
PROJECT_DIR=$root; XDG_STATE_HOME="$task_tmp"; DRY_RUN=0; LOG_FILE=''; STATE_DIR="$task_tmp/state"
source "$root/lib/logger.sh"; source "$root/lib/state.sh"; source "$root/lib/backup.sh"
init_state; mkdir -p "$task_tmp/a" "$task_tmp/b"; touch "$task_tmp/a/app.conf" "$task_tmp/b/app.conf"
backup_file "$task_tmp/a/app.conf" test; backup_file "$task_tmp/b/app.conf" test; backup_file "$task_tmp/a/app.conf" test
[[ $(wc -l < "$STATE_DIR/backups/manifest.tsv") == 2 ]]
awk -F '\t' 'NR==1 {a=$2} NR==2 {b=$2} END {exit !(a != b)}' "$STATE_DIR/backups/manifest.tsv"
backup_file "$task_tmp/new.conf" test; grep -q $'\tcreated$' "$STATE_DIR/backups/manifest.tsv"
echo 'test_backup: ok'
