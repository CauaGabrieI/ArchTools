#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
state=$(mktemp -d)
trap 'rm -rf "$state"' EXIT

list=$(XDG_STATE_HOME="$state" "$root/archtools" module list)
[[ $list == *$'hardware\thardware\tdetect'* ]]
[[ $list == *$'drivers\thardware\tdetect,plan,execute,validate'* ]]
[[ $list != *'install'* ]] || exit 1
[[ ! -e "$state/arch-smart-postinstall" ]]

info=$(XDG_STATE_HOME="$state" "$root/archtools" module info hardware)
[[ $info == *'Somente leitura: yes'* && $info == *'Funções: detect_all,show_hardware'* ]]
drivers_info=$(XDG_STATE_HOME="$state" "$root/archtools" module info drivers)
[[ $drivers_info == *'Somente leitura: no'* && $drivers_info == *'Rollback: yes'* ]]
[[ ! -e "$state/arch-smart-postinstall" ]]

if XDG_STATE_HOME="$state" "$root/archtools" module info inexistente >/dev/null 2>&1; then exit 1; fi
echo 'test_modules: ok'