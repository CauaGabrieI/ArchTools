#!/usr/bin/env bash
# Disposable Arch Linux test environment for ArchTools (sourced only by unit tests).
set -Eeuo pipefail

MACHINES=/var/lib/machines
BASE=$MACHINES/archtools-base
TEST=$MACHINES/archtools-test
UNIT=archtools-nspawn-test.service
REPO=$(realpath -e -- "$(dirname -- "${BASH_SOURCE[0]}")/../..")
MARKER=.archtools-nspawn-owner
READY=.archtools-nspawn-ready
DRY_RUN=0
VERBOSE=0
WRITABLE=0

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
info() { printf '[ArchTools Test Environment] %s\n' "$*"; }
quote_command() { printf '  +'; printf ' %q' "$@"; printf '\n'; }
plan_note() { printf '  # %s\n' "$*"; }
run() {
  if (( DRY_RUN || VERBOSE )); then quote_command "$@"; fi
  (( DRY_RUN )) || "$@"
}
as_root() {
  if (( EUID == 0 )); then run "$@"; else run sudo -- "$@"; fi
}
root_check() {
  if (( EUID == 0 )); then "$@"; else sudo -- "$@"; fi
}
on_error() {
  local code=$? line=$1
  trap - ERR
  printf '[FAIL] Linha %s; exit code %s. Ambiente existente foi preservado para inspeção.\n' "$line" "$code" >&2
  exit "$code"
}
trap 'on_error "$LINENO"' ERR

usage() {
  cat <<'EOF'
Uso: ./tools/testing/nspawn.sh <comando> [opções]
  setup                 Cria archtools-base e archtools-test (nunca sobrescreve)
  start | stop          Inicia/para somente archtools-test
  shell [--writable]    Shell no container; --writable usa cópia interna
  run [--writable] '<comando>'
  test [quick|integration [minimal|desktop|development|server|gaming-dry-run]|idempotency|rollback]
  reset                 Restaura archtools-test a partir da base
  destroy               Remove somente os dois ambientes identificados
  status                Mostra host, filesystem e estado dos ambientes

Opções: --dry-run (somente plano do ambiente), --verbose, --help
O comando de run deve ser uma string entre aspas ou vir após --.
EOF
}

# These guards are deliberately independent of caller-supplied paths.
safe_target() {
  case "${1:-}" in "$BASE"|"$TEST") ;;
    *) printf '[FAIL] Caminho fora da lista permitida: %s\n' "${1:-<vazio>}" >&2; return 1;;
  esac
  [[ ! -L $MACHINES ]] || { printf '[FAIL] Symlink proibido: %s\n' "$MACHINES" >&2; return 1; }
  if [[ -e $MACHINES ]]; then
    [[ $(realpath -e -- "$MACHINES") == "$MACHINES" ]] || { printf '[FAIL] Diretório de máquinas redirecionado\n' >&2; return 1; }
  fi
  if (( DRY_RUN )) && [[ -L $1 ]]; then
    printf '[FAIL] Symlink proibido: %s\n' "$1" >&2; return 1
  fi
  # /var/lib/machines is normally root-only. An unprivileged -L check on a
  # child silently reports false even when that child is a symlink.
  if (( ! DRY_RUN )); then
    root_check test ! -L "$1" || { printf '[FAIL] Symlink proibido ou caminho inacessível: %s\n' "$1" >&2; return 1; }
  fi
}
path_exists() { root_check test -e "$1"; }
owned() {
  local target=$1 kind=$2 value
  safe_target "$target" || return 1
  root_check test ! -L "$target/$MARKER-$kind" || return 1
  path_exists "$target/$MARKER-$kind" || return 1
  value=$(root_check cat -- "$target/$MARKER-$kind") || return 1
  [[ $value == "archtools-nspawn-v1:$kind" ]]
}
ready() { owned "$1" "$2" && path_exists "$1/$READY-$2"; }
assert_owned() { owned "$1" "$2" || fail "Ambiente não identificado em $1; não será alterado."; }
assert_ready() { ready "$1" "$2" || fail "Ambiente ausente/incompleto em $1. Use setup ou destroy explicitamente."; }
assert_host() {
  local os_id='' os_like='' key value
  [[ -r /etc/os-release ]] || fail '/etc/os-release indisponível no host.'
  while IFS='=' read -r key value; do
    value=${value#\"}; value=${value%\"}; value=${value,,}
    case $key in ID) os_id=$value;; ID_LIKE) os_like=$value;; esac
  done < /etc/os-release
  [[ $os_id == arch || " $os_like " == *' arch '* ]] || fail "Host não é Arch/CachyOS compatível: $os_id"
  command -v pacman >/dev/null || fail 'pacman ausente no host.'
}
dependencies() {
  local phase=${1:-setup}
  local missing=() cmd package label=FAIL
  if (( DRY_RUN )); then label=MISSING; fi
  local required=(systemd-nspawn machinectl systemd-run systemctl findmnt mountpoint realpath cp truncate)
  if [[ $phase == setup ]]; then required+=(pacstrap git); fi
  for cmd in "${required[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 && continue
    case $cmd in
      pacstrap) package=arch-install-scripts;;
      git) package=git;;
      findmnt|mountpoint) package=util-linux;;
      realpath|cp|truncate) package=coreutils;;
      *) package=systemd;;
    esac
    printf '[%s] %s ausente (pacote Arch: %s).\n' "$label" "$cmd" "$package" >&2
    missing+=("$package")
  done
  if (( EUID != 0 )) && ! command -v sudo >/dev/null 2>&1; then
    printf '[%s] sudo ausente (pacote Arch: sudo).\n' "$label" >&2
    missing+=(sudo)
  fi
  if ((${#missing[@]})); then
    printf 'Instale explicitamente: sudo pacman -S --needed' >&2
    printf ' %s' "$(printf '%s\n' "${missing[@]}" | sort -u | tr '\n' ' ')" >&2
    printf '\n' >&2
    return 1
  fi
}
filesystem() {
  if [[ -d $MACHINES ]]; then findmnt -T "$MACHINES" -n -o FSTYPE
  else findmnt -T /var/lib -n -o FSTYPE; fi
}
backend() {
  if [[ $(filesystem) == btrfs ]]; then printf 'btrfs-snapshot'; else printf 'reflink-auto/copy'; fi
}
is_running() { root_check systemctl is-active --quiet "$UNIT"; }
assert_unit_owned() {
  local exec_start
  is_running || return 0
  exec_start=$(root_check systemctl show "$UNIT" --property=ExecStart --value) || fail "Não foi possível inspecionar $UNIT."
  [[ $exec_start == *'--machine=archtools-test'* && $exec_start == *'--directory=/var/lib/machines/archtools-test'* ]] ||
    fail "$UNIT está ativo, mas não pertence ao ArchTools."
}
assert_not_foreign_running() {
  # A name collision must never lead to commands in an unrelated machine.
  assert_unit_owned
  if root_check machinectl show archtools-test --property=Name --value 2>/dev/null | grep -Fxq archtools-test; then
    is_running || fail 'archtools-test já está ativo fora da unidade controlada; abortando.'
  fi
}
validate_btrfs_children() {
  local target=$1 root_path=$2 listing=$3 entry child
  safe_target "$target" || return 1
  while IFS= read -r entry; do
    [[ -n $entry ]] || continue
    [[ $entry == *' path '* ]] || { printf '[FAIL] Lista Btrfs inválida: %s\n' "$entry" >&2; return 1; }
    child=${entry##* path }
    case $child in
      "$root_path/var/lib/machines"|"$root_path/var/lib/portables") ;;
      *) printf '[FAIL] Subvolume interno inesperado: %s\n' "$child" >&2; return 1;;
    esac
  done <<< "$listing"
}
remove_target() {
  local target=$1 kind=$2 listing show root_path nested ro_state restore_ro=0
  safe_target "$target" || return 1
  command -v mountpoint >/dev/null && command -v findmnt >/dev/null ||
    fail 'mountpoint/findmnt são necessários para verificar mounts antes da remoção.'
  path_exists "$target" || return 0
  assert_owned "$target" "$kind"
  if root_check mountpoint -q -- "$target"; then fail "Mountpoint ativo em $target; abortando."; fi
  if root_check findmnt -R -n -o TARGET "$target" 2>/dev/null | grep -q .; then
    fail "Mountpoint aninhado em $target; abortando."
  fi
  if [[ $(filesystem) == btrfs ]]; then
    show=$(root_check btrfs subvolume show "$target") || fail "Btrfs esperado, mas $target não é subvolume."
    root_path=${show%%$'\n'*}
    listing=$(root_check btrfs subvolume list -o "$target") || fail "Não foi possível listar subvolumes dentro de $target."
    validate_btrfs_children "$target" "$root_path" "$listing" || fail "Subvolumes internos não autorizados em $target."
    if [[ -n $listing ]]; then
      root_check test ! -L "$target/var" && root_check test ! -L "$target/var/lib" || fail "Symlink em $target/var/lib; abortando."
      for nested in "$target/var/lib/machines" "$target/var/lib/portables"; do
        if root_check btrfs subvolume show "$nested" >/dev/null 2>&1; then
          root_check test ! -L "$nested" && [[ $(root_check realpath -e -- "$nested") == "$nested" ]] ||
            fail "Subvolume interno redirecionado: $nested"
        fi
      done
      ro_state=$(root_check btrfs property get -ts "$target" ro) || fail "Não foi possível inspecionar a propriedade ro de $target."
      if [[ $ro_state == ro=true ]]; then
        as_root btrfs property set -ts "$target" ro false
        restore_ro=1
      fi
      for nested in "$target/var/lib/machines" "$target/var/lib/portables"; do
        if root_check btrfs subvolume show "$nested" >/dev/null 2>&1; then
          if ! as_root btrfs subvolume delete "$nested"; then
            (( restore_ro )) && as_root btrfs property set -ts "$target" ro true
            fail "Não foi possível remover $nested."
          fi
        fi
      done
    fi
    if ! as_root btrfs subvolume delete "$target"; then
      (( restore_ro )) && as_root btrfs property set -ts "$target" ro true
      fail "Não foi possível remover $target."
    fi
  else
    as_root rm -rf --one-file-system -- "$target"
  fi
}
write_marker() {
  local target=$1 kind=$2
  safe_target "$target" || return 1
  if (( DRY_RUN )); then plan_note "Criar $target/$MARKER-$kind com archtools-nspawn-v1:$kind"; return; fi
  printf 'archtools-nspawn-v1:%s\n' "$kind" | root_check tee "$target/$MARKER-$kind" >/dev/null
}
write_guest_marker() {
  safe_target "$TEST" || return 1
  if (( DRY_RUN )); then plan_note "Criar $TEST/etc/archtools-nspawn-test com archtools-nspawn-v1:test"; return; fi
  root_check test -d "$TEST/etc" || fail 'etc ausente no teste recém-criado.'
  root_check test ! -L "$TEST/etc" || fail 'etc do teste é symlink.'
  root_check test ! -L "$TEST/etc/archtools-nspawn-test" || fail 'Marcador do guest é symlink.'
  printf 'archtools-nspawn-v1:test\n' | root_check tee "$TEST/etc/archtools-nspawn-test" >/dev/null
}
write_pacman_conf() {
  local target=$1
  safe_target "$target" || return 1
  if (( DRY_RUN )); then plan_note "Gravar $target/etc/pacman.conf com core, extra e multilib oficiais Arch"; return; fi
  root_check mkdir -p -- "$target/etc"
  root_check tee "$target/etc/pacman.conf" >/dev/null <<'EOF'
[options]
Architecture = auto
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch

[extra]
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch

[multilib]
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
EOF
}
create_test() {
  local fs
  safe_target "$TEST" || return 1
  if (( ! DRY_RUN )); then
    assert_ready "$BASE" base
    path_exists "$TEST" && fail "$TEST já existe; use reset ou destroy explicitamente."
  fi
  fs=$(filesystem)
  if [[ $fs == btrfs ]]; then
    as_root btrfs subvolume snapshot "$BASE" "$TEST"
  else
    as_root mkdir -- "$TEST"
    write_marker "$TEST" test
    as_root cp -a --reflink=auto -- "$BASE/." "$TEST/"
  fi
  write_marker "$TEST" test
  write_guest_marker
  as_root touch -- "$TEST/$READY-test"
  if (( DRY_RUN )); then info "Ambiente de teste planejado: $TEST ($fs)."
  else info "Ambiente de teste criado: $TEST ($fs)."; fi
}
setup() {
  assert_host
  safe_target "$BASE"; safe_target "$TEST"
  if (( DRY_RUN )); then
    plan_note "Verificar que $BASE e $TEST não existem; abortar se existirem."
  else
    path_exists "$BASE" && fail "$BASE já existe; não será sobrescrito. Use status/destroy explicitamente."
    path_exists "$TEST" && fail "$TEST já existe; não será sobrescrito. Use status/destroy explicitamente."
  fi
  if (( DRY_RUN )); then dependencies setup || true; else dependencies setup || return 1; fi
  local fs
  fs=$(filesystem)
  as_root mkdir -p -- "$MACHINES"
  if [[ $fs == btrfs ]]; then
    command -v btrfs >/dev/null || fail 'btrfs-progs ausente. Instale: sudo pacman -S btrfs-progs'
    as_root btrfs subvolume create "$BASE"
  else
    as_root mkdir -- "$BASE"
  fi
  write_marker "$BASE" base
  write_pacman_conf "$BASE"
  # -K creates a fresh keyring; -M avoids copying CachyOS mirrorlists.
  as_root pacstrap -K -M -C "$BASE/etc/pacman.conf" "$BASE" base sudo dbus diffutils
  write_pacman_conf "$BASE"
  as_root truncate -s 0 -- "$BASE/etc/machine-id"
  as_root touch -- "$BASE/$READY-base"
  if [[ $fs == btrfs ]]; then as_root btrfs property set -ts "$BASE" ro true; fi
  create_test
  if (( DRY_RUN )); then
    plan_note 'Iniciar archtools-test; verificar pacman -Syy, pacman -Si e systemd dentro dele.'
    plan_note 'Parar archtools-test e restaurá-lo novamente da base limpa.'
  else
    prepare_guest_marker
    if ! guest 'pacman -Q base >/dev/null && pacman -Syy --noconfirm >/dev/null && pacman -Si base >/dev/null && test -d /run/systemd/system'; then
      stop || true
      fail 'Verificação de pacman/systemd falhou no container; base preservada para inspeção.'
    fi
    stop
    reset
    info 'Base Arch pronta; pacman, rede e systemd verificados no teste descartável.'
  fi
}
start() {
  assert_host; dependencies runtime || return 1
  assert_ready "$TEST" test
  [[ -d $REPO && -f $REPO/archtools ]] || fail "Checkout indisponível: $REPO"
  assert_not_foreign_running
  if is_running; then info 'archtools-test já está ativo.'; return 0; fi
  as_root systemd-run --unit="$UNIT" --collect --service-type=exec \
    --property=Description='ArchTools disposable nspawn test' \
    -- systemd-nspawn --settings=no --machine=archtools-test --directory="$TEST" \
    --boot --register=yes --keep-unit --private-users=pick --private-users-ownership=map \
    --drop-capability=CAP_NET_ADMIN,CAP_NET_RAW --resolv-conf=copy-host \
    --link-journal=no \
    --bind-ro="$REPO:/opt/ArchTools"
  (( DRY_RUN )) && return 0
  local i
  for ((i=0; i<30; i++)); do
    if root_check systemd-run --machine=archtools-test --wait --collect --pipe --quiet -- /usr/bin/true >/dev/null 2>&1; then
      info 'archtools-test iniciado.'
      return 0
    fi
    sleep 1
  done
  fail 'Container não ficou pronto em 30s; verifique journalctl -u archtools-nspawn-test.service.'
}
stop() {
  command -v systemctl >/dev/null && command -v machinectl >/dev/null ||
    fail 'systemctl/machinectl são necessários para confirmar o estado do container.'
  assert_not_foreign_running
  if is_running; then
    as_root systemctl stop "$UNIT"
    is_running && fail "$UNIT ainda está ativo; não é seguro remover o teste."
    info 'archtools-test parado.'
  else info 'archtools-test já está parado.'; fi
}
reset() {
  if (( DRY_RUN )); then
    plan_note "Validar base pronta e test identificado; abortar se algum caminho for estranho."
    plan_note "Se a unidade estiver ativa:"
    as_root systemctl stop "$UNIT"
    plan_note "Se o teste existir e não houver mountpoints ativos:"
    if [[ $(filesystem) == btrfs ]]; then
      plan_note "Validar todos os filhos Btrfs; se presentes, remover somente $TEST/var/lib/machines e $TEST/var/lib/portables."
      as_root btrfs subvolume delete "$TEST"
      as_root btrfs subvolume snapshot "$BASE" "$TEST"
    else
      as_root rm -rf --one-file-system -- "$TEST"
      as_root mkdir -- "$TEST"
      as_root cp -a --reflink=auto -- "$BASE/." "$TEST/"
    fi
    write_marker "$TEST" test
    write_guest_marker
    as_root touch -- "$TEST/$READY-test"
    return 0
  fi
  assert_ready "$BASE" base
  stop
  remove_target "$TEST" test
  create_test
}
destroy() {
  if (( DRY_RUN )); then
    plan_note 'Validar propriedade dos ambientes presentes e ausência de mountpoints ativos.'
    plan_note 'Se a unidade estiver ativa:'
    as_root systemctl stop "$UNIT"
    plan_note 'Se o teste existir:'
    if [[ $(filesystem) == btrfs ]]; then
      plan_note "Validar todos os filhos Btrfs; se presentes, remover somente $TEST/var/lib/machines e $TEST/var/lib/portables."
      as_root btrfs subvolume delete "$TEST"
    else as_root rm -rf --one-file-system -- "$TEST"; fi
    plan_note 'Se a base existir:'
    if [[ $(filesystem) == btrfs ]]; then
      plan_note "Se houver filhos Btrfs internos esperados, tornar $BASE gravável temporariamente e removê-los."
      as_root btrfs subvolume delete "$BASE/var/lib/machines"
      as_root btrfs subvolume delete "$BASE/var/lib/portables"
      as_root btrfs subvolume delete "$BASE"
    else as_root rm -rf --one-file-system -- "$BASE"; fi
    return 0
  fi
  stop
  remove_target "$TEST" test
  remove_target "$BASE" base
  info 'Ambientes ArchTools removidos.'
}
guest() {
  local command=$1
  start
  as_root systemd-run --machine=archtools-test --setenv=HOME=/root --setenv=LOGNAME=root \
    --wait --collect --pipe --quiet \
    --working-directory=/opt/ArchTools -- /usr/bin/bash -lc \
    "test \"\$(cat /etc/archtools-nspawn-test 2>/dev/null)\" = archtools-nspawn-v1:test && $command" </dev/null
}
prepare_guest_marker() {
  local value
  assert_ready "$TEST" test
  root_check test ! -L "$TEST/etc" || fail 'etc do teste é symlink; abortando.'
  root_check test ! -L "$TEST/etc/archtools-nspawn-test" || fail 'Marcador do guest é symlink; abortando.'
  value=$(root_check cat -- "$TEST/etc/archtools-nspawn-test") || fail 'Marcador do guest ausente.'
  [[ $value == 'archtools-nspawn-v1:test' ]] || fail 'Marcador do guest inválido.'
}
do_run() {
  local command=$1
  [[ -n $command ]] || fail 'run requer um comando.'
  if (( DRY_RUN )); then
    plan_note "Validar $TEST e executar somente dentro de archtools-test."
    plan_note "Comando no container: $command"
    return 0
  fi
  prepare_guest_marker
  if (( WRITABLE )); then
    guest "mkdir -p /root/ArchTools-work && cp -a --reflink=auto /opt/ArchTools/. /root/ArchTools-work/ && cd /root/ArchTools-work && $command"
  else guest "cd /opt/ArchTools && $command"; fi
}
do_shell() {
  if (( DRY_RUN )); then
    plan_note "Validar $TEST e abrir shell em archtools-test."
    (( WRITABLE )) && plan_note 'Criar cópia gravável em /root/ArchTools-work.'
    return 0
  fi
  prepare_guest_marker; start
  if (( WRITABLE )); then
    guest 'mkdir -p /root/ArchTools-work && cp -a --reflink=auto /opt/ArchTools/. /root/ArchTools-work/'
    as_root machinectl shell root@archtools-test /usr/bin/bash -lc 'cd /root/ArchTools-work && exec bash'
  else
    as_root machinectl shell root@archtools-test /usr/bin/bash -lc 'cd /opt/ArchTools && exec bash'
  fi
}
do_test() {
  local mode=${1:-quick} scenario=${2:-minimal} rc=0
  case $mode in
    integration) [[ $scenario =~ ^(minimal|desktop|development|server|gaming-dry-run)$ ]] || fail "Cenário inválido: $scenario" ;;
    quick|idempotency|rollback) ;;
    failure) fail 'test failure ainda não implementado; nenhum fault injection é executado.' ;;
    *) fail "Modo de teste inválido: $mode" ;;
  esac
  if (( DRY_RUN )); then
    if [[ $mode != quick ]]; then reset; fi
    plan_note "Validar $TEST, gravar marcador somente nele e iniciar $UNIT se necessário."
    plan_note "Executar dentro de archtools-test: ./tools/testing/guest.sh $mode $scenario"
    return
  fi
  if [[ $mode != quick ]]; then reset; fi
  prepare_guest_marker
  guest "./tools/testing/guest.sh $mode $scenario" || rc=$?
  if (( rc == 0 )); then
    if [[ $mode == integration ]]; then info "PASS: $mode $scenario"; else info "PASS: $mode"; fi
  else info "FAIL: $mode (exit $rc)"; fi
  return "$rc"
}
status() {
  local name path kind state os fs
  if (( EUID != 0 )); then
    root_check true || fail 'Não foi possível obter privilégios para inspecionar /var/lib/machines.'
  fi
  os=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | tr -d '"' | head -1)
  fs=$(filesystem)
  printf '[ArchTools Test Environment]\n\nHost: %s\nFilesystem: %s\nBackend: systemd-nspawn (%s)\n\n' "$os" "$fs" "$(backend)"
  for name in base test; do
    if [[ $name == base ]]; then path=$BASE; kind=base; else path=$TEST; kind=test; fi
    if ready "$path" "$kind"; then state=READY
    elif path_exists "$path"; then state=FOREIGN_OR_INCOMPLETE
    else state=ABSENT; fi
    printf '%-20s %s\n' "archtools-$name" "$state"
  done
  if is_running; then printf 'Runtime: RUNNING\n'; else printf 'Runtime: STOPPED\n'; fi
  printf 'Repository: /opt/ArchTools (read-only; source: %s)\n' "$REPO"
}

main() {
  local action='' mode='' scenario='' command=''
  while (($#)); do
    case $1 in
      --help|-h) usage; return 0;;
      --dry-run) DRY_RUN=1;;
      --verbose) VERBOSE=1;;
      --writable) WRITABLE=1;;
      --) [[ $action == run ]] || fail '-- só é aceito em run.'
          shift; command="$*"; break;;
      setup|start|stop|shell|run|test|reset|destroy|status)
        [[ -z $action ]] || fail "Comando inesperado: $1"
        action=$1;;
      quick|integration|idempotency|rollback|failure)
        [[ $action == test && -z $mode ]] || fail "Argumento inesperado: $1"
        mode=$1;;
      minimal|desktop|development|server|gaming-dry-run)
        [[ $action == test && $mode == integration && -z $scenario ]] || fail "Argumento inesperado: $1"
        scenario=$1;;
      *)
        if [[ $action == run && -z $command ]]; then command=$1
        else fail "Argumento inválido: $1"; fi;;
    esac
    shift
  done
  [[ -n $action ]] || { usage; return 2; }
  if (( WRITABLE )) && [[ $action != run && $action != shell ]]; then fail '--writable só é aceito em run/shell.'; fi
  case $action in
    setup) setup;;
    start) if (( DRY_RUN )); then plan_note "Validar $TEST e iniciar $UNIT via systemd-run.";
      else prepare_guest_marker; start; fi;;
    stop) if (( DRY_RUN )); then plan_note "Se $UNIT estiver ativo, validar origem e pará-lo."; as_root systemctl stop "$UNIT";
      else stop; fi;;
    shell) do_shell;; run) do_run "$command";;
    test) do_test "${mode:-quick}" "${scenario:-minimal}";;
    reset) reset;; destroy) destroy;; status) status;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
