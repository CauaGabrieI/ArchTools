#!/usr/bin/env bash

DOCTOR_OK=0
DOCTOR_WARN=0
DOCTOR_FAIL=0
DOCTOR_VERBOSE=0

doctor_ok() { DOCTOR_OK=$((DOCTOR_OK + 1)); printf '[OK] %s\n' "$*"; }
doctor_warn() { DOCTOR_WARN=$((DOCTOR_WARN + 1)); printf '[WARN] %s\n' "$*"; }
doctor_fail() { DOCTOR_FAIL=$((DOCTOR_FAIL + 1)); printf '[FAIL] %s\n' "$*"; }
doctor_detail() { (( DOCTOR_VERBOSE )) && printf '       %s\n' "$*" || true; }

doctor_usage() {
  cat <<'EOF'
Uso: ./archtools doctor [--verbose|--help]

Executa verificações somente leitura. Exit codes: 0 sem FAIL, 1 com FAIL,
2 para opção ou uso inválido. WARN isolado mantém exit code 0.
EOF
}

doctor_check_system() {
  local os_release=${OS_RELEASE_FILE:-/etc/os-release} os_id='' os_like='' command_name architecture key value
  if [[ -r $os_release ]]; then
    while IFS='=' read -r key value; do
      value=${value%\"}; value=${value#\"}; value=${value,,}
      case "$key" in ID) os_id=$value;; ID_LIKE) os_like=$value;; esac
    done < "$os_release"
    if [[ $os_id == arch || " $os_like " == *' arch '* ]]; then doctor_ok "Sistema operacional: ${os_id:-Arch-compatible}"
    else doctor_fail "Sistema operacional não compatível: ${os_id:-desconhecido}"; fi
    doctor_detail "os-release: $os_release"
  else
    doctor_fail "Sistema operacional: arquivo ilegível ($os_release)"
  fi

  architecture=$(uname -m 2>/dev/null || true)
  [[ -n $architecture ]] && doctor_ok "Arquitetura: $architecture" || doctor_fail 'Arquitetura: não detectada'
  doctor_ok "Bash: ${BASH_VERSION%%(*}"
  for command_name in pacman sudo systemctl awk grep sed find mktemp date uname stat sort comm wc sha256sum; do
    if command -v "$command_name" >/dev/null 2>&1; then
      doctor_ok "$command_name: disponível"
      doctor_detail "$command_name: $(command -v "$command_name")"
    else doctor_fail "$command_name: ausente"; fi
  done
  for command_name in lspci lsblk findmnt; do
    command -v "$command_name" >/dev/null 2>&1 || doctor_warn "comando opcional ausente: $command_name"
  done
}

doctor_check_mode() {
  local path=$1 expected=$2 kind=$3 mode
  [[ -e $path ]] || return 0
  mode=$(stat -c '%a' "$path" 2>/dev/null || true)
  if [[ $mode == "$expected" ]]; then doctor_detail "$kind: $path ($mode)"
  else doctor_fail "$kind com permissão $mode; esperado $expected: $path"; fi
}

doctor_check_lock() {
  local lock="$STATE_DIR/.lock" pid=''
  if [[ ! -e $lock ]]; then doctor_ok 'Lock: nenhum'; return; fi
  if [[ ! -d $lock ]]; then doctor_fail "Lock inválido: $lock não é diretório"; return; fi
  if [[ -e $lock/pid && ! -r $lock/pid ]]; then doctor_fail "Arquivo de estado ilegível: $lock/pid"
  elif [[ -r $lock/pid ]]; then read -r pid < "$lock/pid" || true; fi
  doctor_detail "lock: $lock; PID: ${pid:-ausente}"
  if [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    doctor_warn "operação ArchTools aparentemente ativa (PID $pid)"
  else
    doctor_fail "stale/invalid lock detectado (PID ${pid:-ausente})"
  fi
}

doctor_check_transactions() {
  local ledger="$STATE_DIR/transactions.tsv" id status event_file pid active=0 committed=0 aborted=0 rolled_back=0 other=0 malformed=0
  local -A final_status=()
  [[ -e $ledger ]] || return 0
  [[ -r $ledger ]] || return 0
  while IFS=$'\t' read -r id _run status _module _date extra; do
    if [[ -z $id || -z $status || -n ${extra:-} ]]; then malformed=$((malformed + 1)); continue; fi
    case "$status" in active|committed|aborted|rolled_back|partial|rollback_failed) final_status[$id]=$status;; *) malformed=$((malformed + 1));; esac
  done < "$ledger"
  (( malformed == 0 )) && doctor_ok 'Registro de transações: formato válido' || doctor_fail "Registro de transações: $malformed linha(s) inválida(s)"

  for id in "${!final_status[@]}"; do
    case "${final_status[$id]}" in active) active=$((active + 1));; committed) committed=$((committed + 1));; aborted) aborted=$((aborted + 1));; rolled_back) rolled_back=$((rolled_back + 1));; *) other=$((other + 1));; esac
  done

  for id in "${!final_status[@]}"; do
    event_file="$STATE_DIR/transactions/$id.tsv"
    if [[ ! -e $event_file ]]; then doctor_fail "Transação sem event file: $id"; continue; fi
    if [[ ! -r $event_file ]]; then doctor_fail "Event file ilegível: $id"; continue; fi
    if ! awk -F '\t' 'NF && NF!=11 {bad=1} END {exit bad}' "$event_file"; then doctor_fail "Event file malformado: $id"; fi
    status=${final_status[$id]:-invalid}
    if [[ $status == active ]]; then
      pid=''; [[ -r $STATE_DIR/transactions/$id.pid ]] && read -r pid < "$STATE_DIR/transactions/$id.pid"
      if [[ ! $pid =~ ^[0-9]+$ ]] || ! kill -0 "$pid" 2>/dev/null; then
        doctor_fail "Transação active sem processo correspondente: $id"
      elif [[ ! -r $STATE_DIR/.lock/pid ]] || [[ $(< "$STATE_DIR/.lock/pid") != "$pid" ]]; then
        doctor_fail "Transação active sem lock correspondente: $id"
      fi
    fi
    doctor_detail "transação: $id; status: $status"
  done
  doctor_ok "Transações: active=$active committed=$committed aborted=$aborted rolled_back=$rolled_back other=$other"
}

doctor_check_backups() {
  local manifest="$STATE_DIR/backups/manifest.tsv" path backup hash timestamp module operation extra missing=0 malformed=0 entries=0
  [[ -e $manifest ]] || return 0
  [[ -r $manifest ]] || return 0
  while IFS=$'\t' read -r path backup hash timestamp module operation extra; do
    [[ -n $path ]] || continue
    entries=$((entries + 1))
    if [[ -n ${extra:-} || -z $backup || -z $hash || -z $timestamp || -z $module ]]; then malformed=$((malformed + 1)); continue; fi
    case "$operation" in
      modified)
        if [[ -r $backup ]]; then doctor_detail "payload: $backup (modo $(stat -c '%a' "$backup" 2>/dev/null || printf 'desconhecido'))"
        else missing=$((missing + 1)); doctor_detail "backup ausente ou ilegível: $backup para $path"; fi
        ;;
      created) ;;
      *) malformed=$((malformed + 1));;
    esac
  done < "$manifest"
  (( malformed == 0 )) || doctor_fail "Backups: $malformed entrada(s) malformada(s)"
  (( missing == 0 )) || doctor_fail "Backups: $missing arquivo(s) obrigatório(s) ausente(s)"
  (( malformed || missing )) || doctor_ok "Backups: íntegros ($entries entrada(s))"
}

doctor_check_packages() {
  local installed="$STATE_DIR/installed-packages.txt" existing="$STATE_DIR/existing-packages.txt" package missing=0 overlap=0 count=0
  [[ -e $installed && -r $installed ]] || return 0
  if [[ -e $existing && -r $existing ]]; then
    if ! overlap=$(comm -12 <(sort -u "$installed") <(sort -u "$existing") | sed '/^$/d' | wc -l); then
      doctor_fail 'Proveniência de pacotes: falha ao ler os registros'; return
    fi
    (( overlap == 0 )) || doctor_fail "Proveniência de pacotes: $overlap pacote(s) em ambas as categorias"
  fi
  if command -v pacman >/dev/null 2>&1; then
    while IFS= read -r package; do
      [[ -n $package ]] || continue; count=$((count + 1))
      if ! pacman -Q "$package" >/dev/null 2>&1; then missing=$((missing + 1)); doctor_detail "pacote gerenciado ausente: $package"; fi
    done < "$installed"
    (( missing == 0 )) && doctor_ok "Pacotes gerenciados: consistentes ($count)" || doctor_warn "Pacotes gerenciados ausentes: $missing de $count"
  else doctor_warn 'Pacotes gerenciados: não verificáveis sem pacman'; fi
}

doctor_check_services() {
  local file="$STATE_DIR/services.txt" service old expected extra current mismatched=0 malformed=0 count=0
  [[ -e $file && -r $file ]] || return 0
  while IFS='|' read -r service old expected extra; do
    [[ -n $service ]] || continue; count=$((count + 1))
    if [[ -n ${extra:-} || -z $old || -z $expected ]]; then malformed=$((malformed + 1)); continue; fi
    current=$(systemctl is-enabled "$service" 2>/dev/null || true)
    if [[ $current != "$expected" ]]; then mismatched=$((mismatched + 1)); doctor_detail "$service: atual=${current:-desconhecido}, esperado=$expected"; fi
  done < "$file"
  (( malformed == 0 )) || doctor_fail "Serviços gerenciados: $malformed entrada(s) malformada(s)"
  (( mismatched == 0 )) && doctor_ok "Serviços gerenciados: consistentes ($count)" || doctor_warn "Serviços gerenciados divergentes: $mismatched de $count"
}

doctor_check_inventory() {
  local dir="$STATE_DIR/inventory" hardware="$STATE_DIR/inventory/hardware.tsv" fingerprint="$STATE_DIR/inventory/fingerprint" file
  [[ -e $dir ]] || { doctor_ok 'Inventário: não presente (state legado compatível)'; return; }
  if [[ ! -d $dir ]]; then doctor_fail "Inventário inválido: não é diretório: $dir"; return; fi
  doctor_check_mode "$dir" 700 'Diretório de inventário'
  for file in "$hardware" "$fingerprint"; do
    if [[ ! -e $file ]]; then doctor_fail "Inventário incompleto: arquivo ausente: $file"; continue; fi
    doctor_check_mode "$file" 600 'Arquivo de inventário'
    [[ -r $file ]] || doctor_fail "Arquivo de inventário ilegível: $file"
  done
  if [[ -r $hardware ]]; then
    if awk -F '\t' 'NF!=2 || $1 !~ /^[a-z][a-z0-9_]*$/ {bad=1} END {exit bad}' "$hardware"; then doctor_ok 'Inventário: formato válido'
    else doctor_fail 'Inventário: hardware.tsv malformado'; fi
  fi
  if [[ -r $fingerprint ]]; then
    if grep -Eq '^[[:xdigit:]]{64}$' "$fingerprint" && [[ $(wc -l < "$fingerprint") == 1 ]]; then doctor_ok 'Inventário: fingerprint válido'
    else doctor_fail 'Inventário: fingerprint malformado'; fi
  fi
}

doctor_check_state() {
  local path file
  local -a required_dirs=(backups transactions)
  local -a required_files=(installed-packages.txt existing-packages.txt modified-files.txt services.txt runs.tsv transactions.tsv backups/manifest.tsv)
  if [[ ! -e $STATE_DIR ]]; then doctor_ok 'Estado: ainda não inicializado'; doctor_ok 'Lock: nenhum'; return; fi
  if [[ ! -d $STATE_DIR ]]; then doctor_fail "Estado não é diretório: $STATE_DIR"; return; fi
  doctor_ok 'Estado: diretório encontrado'
  doctor_detail "STATE_DIR: $STATE_DIR"
  doctor_check_mode "$STATE_DIR" 700 'Diretório de estado'
  if [[ ! -r $STATE_DIR || ! -x $STATE_DIR ]]; then doctor_fail "Diretório de estado ilegível: $STATE_DIR"; return; fi

  for path in "${required_dirs[@]}"; do
    if [[ ! -d $STATE_DIR/$path ]]; then doctor_fail "Estado incompleto: diretório obrigatório ausente: $STATE_DIR/$path"
    else
      doctor_check_mode "$STATE_DIR/$path" 700 'Diretório de estado'
      [[ -r $STATE_DIR/$path && -x $STATE_DIR/$path ]] || doctor_fail "Diretório de estado ilegível: $STATE_DIR/$path"
    fi
  done
  for file in "${required_files[@]}"; do
    path="$STATE_DIR/$file"
    if [[ ! -e $path ]]; then doctor_fail "Estado incompleto: arquivo obrigatório ausente: $path"; continue; fi
  done

  while IFS= read -r -d '' path; do
    doctor_check_mode "$path" 600 'Arquivo de controle'
    [[ -r $path ]] || doctor_fail "Arquivo de estado ilegível: $path"
  done < <(find "$STATE_DIR" -maxdepth 1 -type f -print0)

  if [[ -d $STATE_DIR/backups && -r $STATE_DIR/backups && -x $STATE_DIR/backups ]]; then
    while IFS= read -r -d '' path; do doctor_check_mode "$path" 700 'Diretório de estado'; done < <(find "$STATE_DIR/backups" -mindepth 1 -type d -print0)
    while IFS= read -r -d '' path; do
      if [[ ${path##*/} == original ]]; then doctor_detail "payload preservado: $path (modo $(stat -c '%a' "$path" 2>/dev/null || printf 'desconhecido'))"
      else doctor_check_mode "$path" 600 'Arquivo de controle'; [[ -r $path ]] || doctor_fail "Arquivo de estado ilegível: $path"; fi
    done < <(find "$STATE_DIR/backups" -type f -print0)
  fi
  if [[ -d $STATE_DIR/transactions && -r $STATE_DIR/transactions && -x $STATE_DIR/transactions ]]; then
    while IFS= read -r -d '' path; do doctor_check_mode "$path" 600 'Arquivo de controle'; [[ -r $path ]] || doctor_fail "Arquivo de estado ilegível: $path"; done < <(find "$STATE_DIR/transactions" -type f -print0)
  fi
  if [[ -d $STATE_DIR/.lock ]]; then doctor_check_mode "$STATE_DIR/.lock" 700 'Diretório de estado'; [[ -e $STATE_DIR/.lock/pid ]] && doctor_check_mode "$STATE_DIR/.lock/pid" 600 'Arquivo de controle'; fi
  doctor_check_lock
  doctor_check_transactions
  doctor_check_backups
  doctor_check_packages
  doctor_check_services
  doctor_check_inventory
}

doctor_run() {
  DOCTOR_OK=0; DOCTOR_WARN=0; DOCTOR_FAIL=0; DOCTOR_VERBOSE=0
  while (($#)); do
    case "$1" in
      --verbose) DOCTOR_VERBOSE=1; shift;;
      --help|-h) doctor_usage; return 0;;
      *) printf 'Opção inválida: %s\n' "$1" >&2; doctor_usage >&2; return 2;;
    esac
  done
  printf 'ArchTools Doctor\n\n'
  doctor_check_system
  doctor_check_state
  printf '\nResumo:\n  OK: %d\n  WARN: %d\n  FAIL: %d\n\n' "$DOCTOR_OK" "$DOCTOR_WARN" "$DOCTOR_FAIL"
  if (( DOCTOR_FAIL == 0 )); then printf 'Doctor: HEALTHY\n'; return 0; fi
  printf 'Doctor: ISSUES FOUND\n'; return 1
}
