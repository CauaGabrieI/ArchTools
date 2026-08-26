#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT
mock_bin="$task_tmp/bin"
mkdir -p "$mock_bin"

cat > "$mock_bin/pacman" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == -Q && ${2:-} == managed && ${MOCK_PACKAGE_MISSING:-0} == 0 ]]
EOF
cat > "$mock_bin/sudo" <<'EOF'
#!/usr/bin/env bash
echo 'doctor must not invoke sudo' >&2
exit 99
EOF
cat > "$mock_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == is-enabled ]] || { echo 'doctor attempted a systemctl mutation' >&2; exit 99; }
printf '%s\n' "${MOCK_SERVICE_STATE:-enabled}"
[[ ${MOCK_SERVICE_STATE:-enabled} == enabled ]]
EOF
chmod +x "$mock_bin"/*
doctor_env=(env PATH="$mock_bin:$PATH" OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch")

make_state() {
  local base=$1 state file
  state="$base/arch-smart-postinstall"
  mkdir -p "$state/backups" "$state/transactions"
  chmod 700 "$state" "$state/backups" "$state/transactions"
  for file in installed-packages.txt existing-packages.txt modified-files.txt services.txt runs.tsv transactions.tsv; do : > "$state/$file"; chmod 600 "$state/$file"; done
  : > "$state/backups/manifest.tsv"; chmod 600 "$state/backups/manifest.tsv"
  printf 'managed\n' > "$state/installed-packages.txt"
  printf 'test.service|disabled|enabled\n' > "$state/services.txt"
  printf 'txn-healthy\trun-healthy\tcommitted\tinstall\tdate\n' > "$state/transactions.tsv"
  printf 'txn-healthy\trun-healthy\tactive\tinstall\tdate\tchange\tpackage\tmanaged\tabsent\tinstalled\tyes\n' > "$state/transactions/txn-healthy.tsv"
  chmod 600 "$state/transactions/txn-healthy.tsv"
}

add_realistic_backup() {
  local base=$1 state="$1/arch-smart-postinstall" payload
  payload="$state/backups/backup-id/original"
  mkdir -p "$state/backups/backup-id"
  chmod 700 "$state/backups/backup-id"
  printf 'original payload\n' > "$payload"
  chmod 644 "$payload"
  printf '/etc/example\t%s\thash\tdate\ttest\tmodified\n' "$payload" > "$state/backups/manifest.tsv"
  chmod 600 "$state/backups/manifest.tsv"
}

"$root/archtools" doctor --help | grep -Fq 'Exit codes'

empty_home="$task_tmp/empty"
mkdir -p "$empty_home"
logs_before=$(find "$root/logs" -type f 2>/dev/null | sort || true)
empty_output=$("${doctor_env[@]}" XDG_STATE_HOME="$empty_home" "$root/archtools" doctor)
[[ $empty_output == *'Estado: ainda não inicializado'* && $empty_output == *'Doctor: HEALTHY'* ]]
[[ ! -e $empty_home/arch-smart-postinstall ]]
logs_after=$(find "$root/logs" -type f 2>/dev/null | sort || true)
[[ $logs_before == "$logs_after" ]]

healthy_home="$task_tmp/healthy"; make_state "$healthy_home"
healthy_output=$("${doctor_env[@]}" XDG_STATE_HOME="$healthy_home" "$root/archtools" doctor --verbose)
[[ $healthy_output == *'Doctor: HEALTHY'* && $healthy_output == *'txn-healthy'* ]]

permission_home="$task_tmp/permission"; make_state "$permission_home"; chmod 644 "$permission_home/arch-smart-postinstall/installed-packages.txt"
set +e; permission_output=$("${doctor_env[@]}" XDG_STATE_HOME="$permission_home" "$root/archtools" doctor); permission_rc=$?; set -e
[[ $permission_rc == 1 && $permission_output == *'permissão 644; esperado 600'* ]]

stale_home="$task_tmp/stale"; make_state "$stale_home"; mkdir "$stale_home/arch-smart-postinstall/.lock"; printf '99999999\n' > "$stale_home/arch-smart-postinstall/.lock/pid"; chmod 700 "$stale_home/arch-smart-postinstall/.lock"; chmod 600 "$stale_home/arch-smart-postinstall/.lock/pid"
set +e; stale_output=$("${doctor_env[@]}" XDG_STATE_HOME="$stale_home" "$root/archtools" doctor); stale_rc=$?; set -e
[[ $stale_rc == 1 && $stale_output == *'stale/invalid lock'* && -d $stale_home/arch-smart-postinstall/.lock ]]

live_home="$task_tmp/live"; make_state "$live_home"; mkdir "$live_home/arch-smart-postinstall/.lock"; printf '%s\n' "$$" > "$live_home/arch-smart-postinstall/.lock/pid"; chmod 700 "$live_home/arch-smart-postinstall/.lock"; chmod 600 "$live_home/arch-smart-postinstall/.lock/pid"
live_output=$("${doctor_env[@]}" XDG_STATE_HOME="$live_home" "$root/archtools" doctor)
[[ $live_output == *"aparentemente ativa (PID $$)"* && $live_output == *'Doctor: HEALTHY'* ]]

active_home="$task_tmp/active"; make_state "$active_home"; state="$active_home/arch-smart-postinstall"
printf 'txn-active\trun-active\tactive\tinstall\tdate\n' >> "$state/transactions.tsv"
printf 'txn-active\trun-active\tactive\tinstall\tdate\tchange\tpackage\tmanaged\tabsent\tinstalled\tyes\n' > "$state/transactions/txn-active.tsv"; chmod 600 "$state/transactions/txn-active.tsv"
printf '99999999\n' > "$state/transactions/txn-active.pid"; chmod 600 "$state/transactions/txn-active.pid"
set +e; active_output=$("${doctor_env[@]}" XDG_STATE_HOME="$active_home" "$root/archtools" doctor --verbose); active_rc=$?; set -e
[[ $active_rc == 1 && $active_output == *'active sem processo correspondente: txn-active'* ]]

backup_home="$task_tmp/backup"; make_state "$backup_home"; state="$backup_home/arch-smart-postinstall"
printf '/etc/example\t%s\thash\tdate\ttest\tmodified\n' "$state/backups/missing/original" > "$state/backups/manifest.tsv"
set +e; backup_output=$("${doctor_env[@]}" XDG_STATE_HOME="$backup_home" "$root/archtools" doctor --verbose); backup_rc=$?; set -e
[[ $backup_rc == 1 && $backup_output == *'arquivo(s) obrigatório(s) ausente(s)'* ]]

payload_home="$task_tmp/payload"; make_state "$payload_home"; add_realistic_backup "$payload_home"
payload="$payload_home/arch-smart-postinstall/backups/backup-id/original"
payload_output=$("${doctor_env[@]}" XDG_STATE_HOME="$payload_home" "$root/archtools" doctor --verbose)
[[ $payload_output == *'Doctor: HEALTHY'* && $payload_output == *'modo 644'* ]]
[[ $(stat -c '%a' "$payload") == 644 ]]

incomplete_home="$task_tmp/incomplete"; make_state "$incomplete_home"; rm "$incomplete_home/arch-smart-postinstall/transactions.tsv"
set +e; incomplete_output=$("${doctor_env[@]}" XDG_STATE_HOME="$incomplete_home" "$root/archtools" doctor); incomplete_rc=$?; set -e
[[ $incomplete_rc == 1 && $incomplete_output == *'Estado incompleto: arquivo obrigatório ausente'* ]]
[[ ! -e $incomplete_home/arch-smart-postinstall/transactions.tsv ]]

unreadable_home="$task_tmp/unreadable"; make_state "$unreadable_home"; unreadable="$unreadable_home/arch-smart-postinstall/transactions.tsv"; chmod 000 "$unreadable"
set +e; unreadable_output=$("${doctor_env[@]}" XDG_STATE_HOME="$unreadable_home" "$root/archtools" doctor); unreadable_rc=$?; set -e
[[ $unreadable_rc == 1 && $unreadable_output == *'Arquivo de estado ilegível:'* && $unreadable_output == *'Resumo:'* && $unreadable_output == *'Doctor: ISSUES FOUND'* ]]
[[ $(stat -c '%a' "$unreadable") == 0 ]]
chmod 600 "$unreadable"

missing_home="$task_tmp/missing"; make_state "$missing_home"
missing_output=$("${doctor_env[@]}" MOCK_PACKAGE_MISSING=1 XDG_STATE_HOME="$missing_home" "$root/archtools" doctor --verbose)
[[ $missing_output == *'Pacotes gerenciados ausentes: 1 de 1'* && $missing_output == *'Doctor: HEALTHY'* ]]

service_home="$task_tmp/service"; make_state "$service_home"
service_output=$("${doctor_env[@]}" MOCK_SERVICE_STATE=disabled XDG_STATE_HOME="$service_home" "$root/archtools" doctor --verbose)
[[ $service_output == *'Serviços gerenciados divergentes: 1 de 1'* && $service_output == *'Doctor: HEALTHY'* ]]

nonarch="$task_tmp/nonarch"; printf 'ID=ubuntu\n' > "$nonarch"
set +e; nonarch_output=$(env PATH="$mock_bin:$PATH" OS_RELEASE_FILE="$nonarch" XDG_STATE_HOME="$empty_home" "$root/archtools" doctor); nonarch_rc=$?; set -e
[[ $nonarch_rc == 1 && $nonarch_output == *'Sistema operacional não compatível: ubuntu'* ]]

set +e; "$root/archtools" doctor --invalid >/dev/null 2>&1; invalid_rc=$?; set -e
[[ $invalid_rc == 2 ]]

readonly_home="$task_tmp/readonly"; make_state "$readonly_home"; add_realistic_backup "$readonly_home"; state="$readonly_home/arch-smart-postinstall"
find "$state" -printf '%m\t%y\t%p\n' | sort > "$task_tmp/before.metadata"
find "$state" -type f -print0 | sort -z | xargs -0 sha256sum > "$task_tmp/before.hashes"
"${doctor_env[@]}" XDG_STATE_HOME="$readonly_home" "$root/archtools" doctor >/dev/null
find "$state" -printf '%m\t%y\t%p\n' | sort > "$task_tmp/after.metadata"
find "$state" -type f -print0 | sort -z | xargs -0 sha256sum > "$task_tmp/after.hashes"
cmp -s "$task_tmp/before.metadata" "$task_tmp/after.metadata"
cmp -s "$task_tmp/before.hashes" "$task_tmp/after.hashes"
[[ ! -e $state/.lock ]]
[[ $(stat -c '%a' "$state/backups/backup-id/original") == 644 ]]
[[ $(find "$root/logs" -type f 2>/dev/null | sort || true) == "$logs_before" ]]

echo 'test_doctor: ok'
