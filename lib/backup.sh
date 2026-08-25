#!/usr/bin/env bash
backup_file() {
  local target=$1 module=${2:-unknown} absolute hash operation id dir backup manifest
  absolute=$(readlink -f -- "$target" 2>/dev/null || printf '%s' "$target")
  manifest="$STATE_DIR/backups/manifest.tsv"
  if [[ -e $target ]]; then
    hash=$(sha256sum "$target" | awk '{print $1}'); operation=modified
  else hash=absent; operation=created; fi
  if awk -F '\t' -v path="$absolute" -v prior_hash="$hash" '$1 == path && $3 == prior_hash { found=1 } END { exit !found }' "$manifest" 2>/dev/null; then log INFO "[SKIP] Backup already exists: $absolute"; return 0; fi
  id=$(printf '%s\0%s\0%s' "$absolute" "$hash" "$operation" | sha256sum | awk '{print $1}'); dir="$STATE_DIR/backups/$id"; backup="$dir/original"
  mkdir -p "$dir"
  if [[ $operation == modified ]]; then cp -a -- "$target" "$backup"; else : > "$backup.created"; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$absolute" "$backup" "$hash" "$(date -Is)" "$module" "$operation" >> "$manifest"
  state_add_unique "$STATE_DIR/modified-files.txt" "$absolute"
  if [[ ${TRANSACTION_STATUS:-} == active ]] && declare -F record_change >/dev/null 2>&1; then
    record_change "$module" file "$absolute" "$backup" "$operation" yes
  fi
}
