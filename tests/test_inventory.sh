#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT

PROJECT_DIR=$root
XDG_STATE_HOME="$task_tmp/state"
source "$root/lib/core.sh"
load_modules
declare -gA HARDWARE=(
  [arch]=x86_64 [machine]=VM [cpu_vendor]=AMD [cpu_model]='Test CPU'
  [cpu_cores]=8 [cpu_threads]=16 [gpus]='Virtual GPU' [gpu_amd]=0 [gpu_intel]=0
  [gpu_nvidia]=0 [virtualization]=kvm [ram_total]=16Gi [storage_summary]='vda (SSD)'
  [root_device]=/dev/vda1 [root_fs]=ext4 [trim]=1 [network]='eth0'
  [bluetooth_hardware]=false [audio]=PipeWire [desktop]=none [display_manager]=none
)
HARDWARE_PROFILE_DETECTED=vm
ACTION=install; DRY_RUN=0
inventory_save
inventory_dir="$STATE_DIR/inventory"
[[ -d $inventory_dir && -f $inventory_dir/hardware.tsv && -f $inventory_dir/fingerprint ]]
[[ $(stat -c '%a' "$inventory_dir") == 700 ]]
[[ $(stat -c '%a' "$inventory_dir/hardware.tsv") == 600 && $(stat -c '%a' "$inventory_dir/fingerprint") == 600 ]]
grep -Fqx $'cpu_model\tTest CPU' "$inventory_dir/hardware.tsv"
grep -Fqx $'hardware_profile_detected\tvm' "$inventory_dir/hardware.tsv"
! grep -Eqi 'mac|ip_address|hostname|username|disk_serial|motherboard|uuid' "$inventory_dir/hardware.tsv"

fingerprint_one=$(< "$inventory_dir/fingerprint")
inode_one=$(stat -c '%i' "$inventory_dir/hardware.tsv")
inventory_save
fingerprint_two=$(< "$inventory_dir/fingerprint")
inode_two=$(stat -c '%i' "$inventory_dir/hardware.tsv")
[[ $fingerprint_one == "$fingerprint_two" && $inode_one != "$inode_two" ]]
[[ $(find "$STATE_DIR" -name '.atomic.*' | wc -l) == 0 ]]
HARDWARE[cpu_model]='Changed CPU'
inventory_save
[[ $(< "$inventory_dir/fingerprint") != "$fingerprint_one" ]]

for action in dry-run detect-only doctor suggest; do
  readonly_home="$task_tmp/$action"; mkdir -p "$readonly_home"
  case "$action" in
    dry-run) PATH="$root/tests/mock-bin:$PATH" XDG_STATE_HOME="$readonly_home" OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" "$root/install.sh" --hardware-profile auto --usage-profile minimal --desktop minimal --dry-run >/dev/null;;
    detect-only) PATH="$root/tests/mock-bin:$PATH" XDG_STATE_HOME="$readonly_home" OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" "$root/install.sh" --detect-only >/dev/null;;
    doctor) PATH="$root/tests/mock-bin:$PATH" XDG_STATE_HOME="$readonly_home" OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" "$root/archtools" doctor >/dev/null;;
    suggest) PATH="$root/tests/mock-bin:$PATH" XDG_STATE_HOME="$readonly_home" OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" "$root/archtools" desktop-apps suggest --desktop gnome >/dev/null;;
  esac
  [[ ! -e $readonly_home/arch-smart-postinstall/inventory ]]
done

legacy_home="$task_tmp/legacy"; STATE_DIR="$legacy_home/arch-smart-postinstall"; init_state
legacy_output=$(PATH="$root/tests/mock-bin:$PATH" XDG_STATE_HOME="$legacy_home" OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" "$root/archtools" doctor)
[[ $legacy_output == *'state legado compatível'* && $legacy_output == *'Doctor: HEALTHY'* ]]
mkdir -p "$STATE_DIR/inventory"; chmod 755 "$STATE_DIR/inventory"; printf 'bad\n' > "$STATE_DIR/inventory/hardware.tsv"; printf 'bad\n' > "$STATE_DIR/inventory/fingerprint"; chmod 600 "$STATE_DIR/inventory"/*
if invalid_output=$(PATH="$root/tests/mock-bin:$PATH" XDG_STATE_HOME="$legacy_home" OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" "$root/archtools" doctor); then invalid_rc=0; else invalid_rc=$?; fi
[[ $invalid_rc == 1 && $invalid_output == *'Diretório de inventário com permissão 755; esperado 700'* ]]

echo 'test_inventory: ok'
