#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT

STATE_DIR="$task_tmp/state"
source "$root/lib/state.sh"
source "$root/lib/packages.sh"
init_state

declare -A physical=([preexisting]=1)
is_package_installed() { [[ ${physical[$1]:-0} == 1 ]]; }
package_available() { return 0; }
log() { :; }
warn() { :; }
sudo() {
  [[ $1 == pacman && $2 == -S ]]
  shift 3
  local package
  for package in "$@"; do physical[$package]=1; done
}

install_packages managed preexisting
grep -Fqx managed "$STATE_DIR/installed-packages.txt"
! grep -Fqx managed "$STATE_DIR/existing-packages.txt"
grep -Fqx preexisting "$STATE_DIR/existing-packages.txt"
! grep -Fqx preexisting "$STATE_DIR/installed-packages.txt"

managed_hash=$(sha256sum "$STATE_DIR/installed-packages.txt")
existing_hash=$(sha256sum "$STATE_DIR/existing-packages.txt")
install_packages managed preexisting
[[ $(sha256sum "$STATE_DIR/installed-packages.txt") == "$managed_hash" ]]
[[ $(sha256sum "$STATE_DIR/existing-packages.txt") == "$existing_hash" ]]
[[ $(grep -Fxc managed "$STATE_DIR/installed-packages.txt") == 1 ]]
[[ $(grep -Fxc preexisting "$STATE_DIR/existing-packages.txt") == 1 ]]
! comm -12 <(sort "$STATE_DIR/installed-packages.txt") <(sort "$STATE_DIR/existing-packages.txt") | grep -q .

# Installed-by-ArchTools wins if an old corrupted intersection is encountered.
printf 'managed\n' >> "$STATE_DIR/existing-packages.txt"
install_packages managed
! grep -Fqx managed "$STATE_DIR/existing-packages.txt"

source "$root/lib/planner.sh"
PLAN_SERVICES_ENABLE=()
PLAN_SERVICES_CONFIGURED=()
systemctl() { [[ $1 == is-enabled && $2 == enabled.service ]] && printf 'enabled\n'; }
add_service enabled.service
add_service disabled.service
[[ ${PLAN_SERVICES_CONFIGURED[*]} == enabled.service ]]
[[ ${PLAN_SERVICES_ENABLE[*]} == disabled.service ]]

echo 'test_idempotency_provenance: ok'
