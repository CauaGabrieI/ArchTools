#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT
export PATH="$root/tests/mock-bin:$PATH"
export OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch"

declare -A terminal=([gnome]=gnome-console [kde]=konsole [xfce]=xfce4-terminal [cinnamon]=gnome-terminal [hyprland]=foot)
declare -A browser=([gnome]=epiphany [kde]=falkon [xfce]=firefox [cinnamon]=firefox [hyprland]=firefox)
declare -A files=([gnome]=nautilus [kde]=dolphin [xfce]=thunar [cinnamon]=nemo [hyprland]=thunar)
declare -A all_packages=(
  [gnome]='gnome-console epiphany gnome-software nautilus gnome-text-editor file-roller'
  [kde]='konsole falkon discover dolphin kate ark'
  [xfce]='xfce4-terminal firefox gnome-software thunar mousepad file-roller'
  [cinnamon]='gnome-terminal firefox gnome-software nemo xed file-roller'
  [hyprland]='foot firefox gnome-software thunar mousepad file-roller'
)

for desktop in gnome kde xfce cinnamon hyprland; do
  state="$task_tmp/$desktop"; mkdir -p "$state"
  no_selection=$(XDG_STATE_HOME="$state" "$root/install.sh" --desktop "$desktop" --profile desktop --dry-run)
  [[ $no_selection != *"    + ${terminal[$desktop]}"* ]]

  selected=$(XDG_STATE_HOME="$state" "$root/install.sh" --desktop "$desktop" --profile desktop --desktop-components terminal --dry-run)
  [[ $selected == *"    + ${terminal[$desktop]}"* ]]
  for other in gnome kde xfce cinnamon hyprland; do
    [[ $other == "$desktop" || ${terminal[$other]} == ${terminal[$desktop]} ]] && continue
    [[ $selected != *"    + ${terminal[$other]}"* ]]
  done

  multiple=$(XDG_STATE_HOME="$state" "$root/install.sh" --desktop "$desktop" --profile desktop --desktop-components browser,files --dry-run)
  [[ $multiple == *"    + ${browser[$desktop]}"* && $multiple == *"    + ${files[$desktop]}"* ]]

  everything=$(XDG_STATE_HOME="$state" "$root/install.sh" --desktop "$desktop" --profile desktop --desktop-components all --dry-run)
  for package in ${all_packages[$desktop]}; do [[ $everything == *"    + $package"* ]]; done

  none=$(XDG_STATE_HOME="$state" "$root/install.sh" --desktop "$desktop" --profile desktop --desktop-components none --dry-run)
  [[ $none != *"    + ${terminal[$desktop]}"* ]]
  [[ ! -e $state/arch-smart-postinstall ]]
done

minimal_state="$task_tmp/minimal"; mkdir -p "$minimal_state"
XDG_STATE_HOME="$minimal_state" "$root/install.sh" --desktop minimal --profile minimal --dry-run >/dev/null
XDG_STATE_HOME="$minimal_state" "$root/install.sh" --desktop minimal --profile minimal --desktop-components none --dry-run >/dev/null
if XDG_STATE_HOME="$minimal_state" "$root/install.sh" --desktop minimal --profile minimal --desktop-components terminal --dry-run >/dev/null 2>&1; then exit 1; fi
[[ ! -e $minimal_state/arch-smart-postinstall ]]

echo 'test_desktop_components_matrix: ok'
