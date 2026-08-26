#!/usr/bin/env bash

detect_hardware_profile() {
  local power_supply=${POWER_SUPPLY_DIR:-/sys/class/power_supply}
  local chassis_file=${CHASSIS_TYPE_FILE:-/sys/class/dmi/id/chassis_type} chassis=''
  [[ -r $chassis_file ]] && read -r chassis < "$chassis_file" || true
  if [[ ${HARDWARE[machine]:-} == VM || ( -n ${HARDWARE[virtualization]:-} && ${HARDWARE[virtualization]} != none ) ]]; then
    HARDWARE_PROFILE_DETECTED=vm
  elif [[ -d $power_supply ]] && find "$power_supply" -maxdepth 1 -name 'BAT*' -print -quit 2>/dev/null | grep -q .; then
    HARDWARE_PROFILE_DETECTED=notebook
  elif [[ $chassis =~ ^(8|9|10|11|14)$ ]]; then
    HARDWARE_PROFILE_DETECTED=notebook
  elif [[ $chassis =~ ^(17|23|28|29)$ ]]; then
    HARDWARE_PROFILE_DETECTED=server
  else
    HARDWARE_PROFILE_DETECTED=desktop
  fi
  HARDWARE[hardware_profile]=$HARDWARE_PROFILE_DETECTED
}

resolve_hardware_profile() {
  [[ -n ${HARDWARE_PROFILE_DETECTED:-} ]] || detect_hardware_profile
  if [[ -z ${HARDWARE_PROFILE:-} || $HARDWARE_PROFILE == auto ]]; then HARDWARE_PROFILE=$HARDWARE_PROFILE_DETECTED; fi
}

hardware_profile_apply() { "hardware_profile_$1"; }
usage_profile_apply() { "usage_profile_$1"; }
