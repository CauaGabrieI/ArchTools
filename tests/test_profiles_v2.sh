#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT
PROJECT_DIR=$root
source "$root/lib/core.sh"
load_modules

power="$task_tmp/power"; mkdir -p "$power"; chassis="$task_tmp/chassis"
POWER_SUPPLY_DIR=$power; CHASSIS_TYPE_FILE=$chassis

declare -gA HARDWARE=([machine]=VM [virtualization]=kvm)
detect_hardware_profile; [[ $HARDWARE_PROFILE_DETECTED == vm ]]
HARDWARE=([machine]=DESKTOP [virtualization]=none); : > "$power/BAT0"; printf '3\n' > "$chassis"
detect_hardware_profile; [[ $HARDWARE_PROFILE_DETECTED == notebook ]]; rm "$power/BAT0"
printf '23\n' > "$chassis"; detect_hardware_profile; [[ $HARDWARE_PROFILE_DETECTED == server ]]
printf '3\n' > "$chassis"; detect_hardware_profile; [[ $HARDWARE_PROFILE_DETECTED == desktop ]]

HARDWARE_PROFILE=notebook; HARDWARE_PROFILE_DETECTED=desktop; resolve_hardware_profile; [[ $HARDWARE_PROFILE == notebook ]]
HARDWARE_PROFILE=auto; resolve_hardware_profile; [[ $HARDWARE_PROFILE == desktop ]]

plan_firmware() { plan_package linux-firmware; }
PLAN_PACKAGES=(); usage_profile_minimal; [[ " ${PLAN_PACKAGES[*]} " == *' linux-firmware '* && " ${PLAN_PACKAGES[*]} " == *' networkmanager '* ]]
PLAN_PACKAGES=(); usage_profile_desktop; for p in linux-firmware networkmanager pipewire pipewire-audio pipewire-pulse wireplumber; do [[ " ${PLAN_PACKAGES[*]} " == *" $p "* ]]; done
PLAN_PACKAGES=(); usage_profile_gaming; for p in steam vulkan-tools pipewire; do [[ " ${PLAN_PACKAGES[*]} " == *" $p "* ]]; done
PLAN_PACKAGES=(); usage_profile_development; [[ " ${PLAN_PACKAGES[*]} " == *' base-devel '* && " ${PLAN_PACKAGES[*]} " == *' git '* ]]
PLAN_PACKAGES=(); PLAN_SERVICES_ENABLE=(); PLAN_NOTES=(); usage_profile_server; [[ " ${PLAN_PACKAGES[*]} " == *' openssh '* && " ${PLAN_SERVICES_ENABLE[*]} " != *' sshd.service '* ]]

reset_cli() { DESKTOP=''; PROFILE=''; USAGE_PROFILE=''; HARDWARE_PROFILE=auto; HARDWARE_PROFILE_EXPLICIT=0; DESKTOP_COMPONENTS_SPEC=''; ACTION=install; DRY_RUN=0; }
reset_cli; parse_cli --profile gaming --dry-run; [[ $USAGE_PROFILE == gaming && $PROFILE == gaming ]]
reset_cli; parse_cli --usage-profile gaming --dry-run; [[ $USAGE_PROFILE == gaming && $PROFILE == gaming ]]
reset_cli; parse_cli --hardware-profile vm --usage-profile development --dry-run; [[ $HARDWARE_PROFILE == vm && $HARDWARE_PROFILE_EXPLICIT == 1 ]]
(reset_cli; parse_cli --hardware-profile invalid --dry-run) >/dev/null 2>&1 && exit 1 || true
(reset_cli; parse_cli --usage-profile invalid --dry-run) >/dev/null 2>&1 && exit 1 || true

echo 'test_profiles_v2: ok'
