#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT

PLAN_PACKAGES=()
source "$root/lib/packages.sh"
source "$root/lib/desktop-components.sh"

[[ $(normalize_desktop GNOME) == gnome ]]
[[ $(normalize_desktop 'GNOME:GNOME-Classic') == gnome ]]
[[ $(normalize_desktop KDE) == kde ]]
[[ $(normalize_desktop 'KDE Plasma') == kde ]]
[[ $(normalize_desktop XFCE) == xfce ]]
[[ $(normalize_desktop X-Cinnamon) == cinnamon ]]
[[ $(normalize_desktop Hyprland) == hyprland ]]
[[ $(normalize_desktop mystery) == unknown ]]
[[ $(detect_current_desktop kde) == kde ]]
XDG_CURRENT_DESKTOP=GNOME
[[ $(detect_current_desktop) == gnome ]]

parse_desktop_components terminal
[[ ${DESKTOP_COMPONENTS_SELECTED[*]} == terminal ]]
parse_desktop_components terminal,browser,store
[[ ${DESKTOP_COMPONENTS_SELECTED[*]} == 'terminal browser store' ]]
parse_desktop_components terminal,terminal,browser
[[ ${DESKTOP_COMPONENTS_SELECTED[*]} == 'terminal browser' ]]
parse_desktop_components all
[[ ${#DESKTOP_COMPONENTS_SELECTED[@]} == 6 ]]
parse_desktop_components none
[[ ${#DESKTOP_COMPONENTS_SELECTED[@]} == 0 ]]
if parse_desktop_components invalid >/dev/null 2>&1; then exit 1; fi
if parse_desktop_components all,terminal >/dev/null 2>&1; then exit 1; fi

declare -A expected=(
  [gnome]='gnome-console epiphany gnome-software nautilus gnome-text-editor file-roller'
  [kde]='konsole falkon discover dolphin kate ark'
  [xfce]='xfce4-terminal firefox gnome-software thunar mousepad file-roller'
  [cinnamon]='gnome-terminal firefox gnome-software nemo xed file-roller'
  [hyprland]='foot firefox gnome-software thunar mousepad file-roller'
)
for desktop in gnome kde xfce cinnamon hyprland; do
  actual=''
  for component in "${DESKTOP_COMPONENT_CATEGORIES[@]}"; do actual+="$(desktop_component_package "$desktop" "$component") "; done
  [[ ${actual% } == "${expected[$desktop]}" ]]
done
[[ -z $(desktop_component_package minimal terminal) ]]

plan_package() { [[ " ${PLAN_PACKAGES[*]} " == *" $1 "* ]] || PLAN_PACKAGES+=("$1"); }
PLAN_PACKAGES=(); desktop_components_plan kde terminal,files
[[ ${PLAN_PACKAGES[*]} == 'konsole dolphin' ]]
PLAN_PACKAGES=(); desktop_components_plan gnome none
[[ ${#PLAN_PACKAGES[@]} == 0 ]]
if desktop_components_plan minimal terminal >/dev/null 2>&1; then exit 1; fi
if desktop_components_plan unknown terminal >/dev/null 2>&1; then exit 1; fi

# Suggest is read-only and reports unavailable packages without failing.
is_package_installed() { [[ $1 == nautilus ]]; }
package_available() { [[ $1 != gnome-software ]]; }
suggestions=$(desktop_components_show_suggestions gnome)
[[ $suggestions == *'= files'* && $suggestions == *'! store'* && $suggestions == *'+ terminal'* ]]

cli_state="$task_tmp/cli-state"
mkdir -p "$cli_state"
suggest_output=$(PATH="$root/tests/mock-bin:$PATH" XDG_STATE_HOME="$cli_state" OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" \
  "$root/archtools" desktop-apps suggest --desktop gnome)
[[ $suggest_output == *'Desktop detectado: gnome'* ]]
[[ ! -e $cli_state/arch-smart-postinstall ]]

PATH="$root/tests/mock-bin:$PATH" XDG_STATE_HOME="$cli_state" OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" \
  "$root/archtools" desktop-apps install none --desktop gnome --yes >/dev/null
[[ ! -e $cli_state/arch-smart-postinstall ]]

dry_output=$(PATH="$root/tests/mock-bin:$PATH" XDG_STATE_HOME="$cli_state" OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" \
  "$root/archtools" desktop-apps install terminal --desktop gnome --dry-run)
[[ $dry_output == *'gnome-console'* && $dry_output != *'epiphany'* ]]
[[ ! -e $cli_state/arch-smart-postinstall ]]

if env -u XDG_CURRENT_DESKTOP -u DESKTOP_SESSION PATH="$root/tests/mock-bin:$PATH" XDG_STATE_HOME="$cli_state" \
  OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" "$root/archtools" desktop-apps install terminal --dry-run >/dev/null 2>&1; then exit 1; fi

if command -v script >/dev/null 2>&1; then
  interactive=$(printf 'terminal\n' | script -qec "env PATH='$root/tests/mock-bin':\$PATH XDG_STATE_HOME='$cli_state' OS_RELEASE_FILE='$root/tests/fixtures/os-release-arch' '$root/install.sh' --hardware-profile auto --desktop gnome --profile desktop --dry-run" /dev/null)
  [[ $interactive == *'Componentes ['* && $interactive == *'gnome-console'* ]]
fi

if PATH="$root/tests/mock-bin:$PATH" XDG_STATE_HOME="$cli_state" OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" \
  "$root/archtools" desktop-apps install invalid --desktop gnome --dry-run >/dev/null 2>&1; then exit 1; fi
[[ ! -e $cli_state/arch-smart-postinstall ]]

# --yes confirms only an explicit selection; it never selects suggestions.
yes_output=$(PATH="$root/tests/mock-bin:$PATH" XDG_STATE_HOME="$cli_state" OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" \
  "$root/install.sh" --desktop gnome --profile desktop --yes --dry-run)
for optional in gnome-console epiphany gnome-software gnome-text-editor file-roller; do
  [[ $yes_output != *"    + $optional"* ]]
done

# Provenance/idempotency and generic transaction rollback apply unchanged to components.
STATE_DIR="$task_tmp/provenance"; RUN_ID=component-run; DRY_RUN=0; LOG_FILE=''; APP_ID=arch-smart-postinstall
DESKTOP=gnome; PROFILE=desktop
source "$root/lib/logger.sh"
source "$root/lib/state.sh"
source "$root/lib/transaction.sh"
init_state
declare -A physical=([pre-browser]=1 [component-terminal]=0)
is_package_installed() { [[ ${physical[$1]:-0} == 1 ]]; }
package_available() { return 0; }
sudo() {
  if [[ $1 == pacman && $2 == -S ]]; then PACMAN_INSTALL_ARGS="$*"; physical[component-terminal]=1; return 0; fi
  if [[ $1 == pacman && $2 == -R ]]; then physical[${@: -1}]=0; return 0; fi
  return 1
}
begin_transaction desktop-apps
ASSUME_YES=1
install_packages component-terminal pre-browser
[[ $PACMAN_INSTALL_ARGS == *' --noconfirm '* ]]
commit_transaction
grep -Fqx component-terminal "$STATE_DIR/installed-packages.txt"
grep -Fqx pre-browser "$STATE_DIR/existing-packages.txt"
! grep -Fqx component-terminal "$STATE_DIR/existing-packages.txt"
installed_hash=$(sha256sum "$STATE_DIR/installed-packages.txt")
existing_hash=$(sha256sum "$STATE_DIR/existing-packages.txt")
install_packages component-terminal pre-browser
[[ $(sha256sum "$STATE_DIR/installed-packages.txt") == "$installed_hash" ]]
[[ $(sha256sum "$STATE_DIR/existing-packages.txt") == "$existing_hash" ]]

RUN_ID=component-failure; TRANSACTION_ID=''; TRANSACTION_STATUS=''; TRANSACTION_MODULE=''
begin_transaction desktop-apps
record_change desktop-apps package component-terminal absent installed yes
abort_transaction simulated
rollback_transaction
[[ ${physical[component-terminal]} == 0 && ${physical[pre-browser]} == 1 ]]
[[ ! -e $STATE_DIR/.lock ]]

echo 'test_desktop_components: ok'
