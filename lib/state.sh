#!/usr/bin/env bash
init_state() { mkdir -p "$STATE_DIR/backups"; touch "$STATE_DIR"/{installed-packages.txt,existing-packages.txt,modified-files.txt,services.txt}; touch "$STATE_DIR/backups/manifest.tsv"; }
state_add_unique() { local file=$1 value=$2; grep -Fqx -- "$value" "$file" 2>/dev/null || printf '%s\n' "$value" >> "$file"; }
save_last_run() { printf 'date=%s\ndesktop=%s\nprofile=%s\nlog=%s\n' "$(date -Is)" "$1" "$2" "$LOG_FILE" > "$STATE_DIR/last-run"; write_state_json; }
write_state_json() { printf '{\n  "application": "%s",\n  "last_run": "%s"\n}\n' "$APP_ID" "$(date -Is)" > "$STATE_DIR/state.json"; }
list_changes() { printf 'Packages installed by this project:\n'; sed 's/^/  + /' "$STATE_DIR/installed-packages.txt"; printf '\nPre-existing packages:\n'; sed 's/^/  = /' "$STATE_DIR/existing-packages.txt"; printf '\nFiles modified:\n'; sed 's/^/  ~ /' "$STATE_DIR/modified-files.txt"; printf '\nServices changed:\n'; sed 's/^/  * /' "$STATE_DIR/services.txt"; printf '\nBackups:\n'; find "$STATE_DIR/backups" -maxdepth 2 -type f -name manifest.tsv -print 2>/dev/null || true; }
