#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT

(
  PROJECT_DIR=$root; XDG_STATE_HOME="$task_tmp/fail"; source "$root/lib/core.sh"; load_modules
  order=(); package_mutations=0; service_mutations=0
  doctor_run() { order+=(doctor); DOCTOR_WARN=0; return 1; }
  archtools_detect_module() { order+=(detect); }
  detect_hardware_profile() { order+=(profile); HARDWARE_PROFILE_DETECTED=desktop; }
  inventory_save() { order+=(inventory); }
  startup_prepare >/dev/null 2>&1 && exit 1 || true
  [[ ${order[*]} == doctor && ! -e $STATE_DIR && $package_mutations == 0 && $service_mutations == 0 ]]
  [[ -z ${TRANSACTION_ID:-} && ! -e $STATE_DIR/.lock ]]
)

(
  PROJECT_DIR=$root; XDG_STATE_HOME="$task_tmp/warn"; source "$root/lib/core.sh"; load_modules
  order=(); detection_count=0; DRY_RUN=0; ACTION=install
  doctor_run() { order+=(doctor); DOCTOR_WARN=1; return 0; }
  archtools_detect_module() { order+=(detect); detection_count=$((detection_count + 1)); HARDWARE[machine]=VM; HARDWARE[virtualization]=kvm; }
  detect_hardware_profile() { order+=(profile); HARDWARE_PROFILE_DETECTED=vm; }
  inventory_save() { order+=(inventory); }
  startup_prepare > "$task_tmp/startup-warn.out"
  output=$(< "$task_tmp/startup-warn.out")
  [[ $output == *'[WARN] Doctor'* && ${order[*]} == 'doctor detect profile inventory' && $detection_count == 1 ]]
)

(
  PROJECT_DIR=$root; XDG_STATE_HOME="$task_tmp/dry"; source "$root/lib/core.sh"; load_modules
  order=(); DRY_RUN=1; ACTION=install
  doctor_run() { order+=(doctor); DOCTOR_WARN=0; return 0; }
  archtools_detect_module() { order+=(detect); HARDWARE[machine]=DESKTOP; HARDWARE[virtualization]=none; }
  detect_hardware_profile() { order+=(profile); HARDWARE_PROFILE_DETECTED=desktop; }
  inventory_save() { order+=(inventory); }
  startup_prepare >/dev/null
  [[ ${order[*]} == 'doctor detect profile' && ! -e $STATE_DIR ]]
)

(
  PROJECT_DIR=$root; XDG_STATE_HOME="$task_tmp/normal"; source "$root/lib/core.sh"; load_modules
  DRY_RUN=0; ACTION=install
  doctor_run() { DOCTOR_WARN=0; return 0; }
  archtools_detect_module() {
    HARDWARE=([machine]=VM [virtualization]=kvm [arch]=x86_64 [cpu_vendor]=OTHER [cpu_model]='Startup CPU'
      [cpu_cores]=2 [cpu_threads]=2 [gpus]='Virtual GPU' [gpu_amd]=0 [gpu_intel]=0 [gpu_nvidia]=0
      [ram_total]=2Gi [storage_summary]='vda (SSD)' [root_device]=/dev/vda1 [root_fs]=ext4 [trim]=1
      [network]=eth0 [bluetooth_hardware]=false [audio]=PipeWire [desktop]=none [display_manager]=none)
  }
  startup_prepare >/dev/null
  [[ -f $STATE_DIR/inventory/hardware.tsv && -f $STATE_DIR/inventory/fingerprint ]]
  grep -Fqx $'cpu_model\tStartup CPU' "$STATE_DIR/inventory/hardware.tsv"

  hardware_before=$(sha256sum "$STATE_DIR/inventory/hardware.tsv")
  fingerprint_before=$(sha256sum "$STATE_DIR/inventory/fingerprint")
  if doctor_output=$(PATH="$root/tests/mock-bin:$PATH" \
    XDG_STATE_HOME="$XDG_STATE_HOME" \
    OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" \
    "$root/archtools" doctor); then
    doctor_rc=0
  else
    doctor_rc=$?
  fi
  [[ $doctor_rc == 0 && $doctor_output == *'Doctor: HEALTHY'* ]]
  [[ -f $STATE_DIR/inventory/hardware.tsv && -f $STATE_DIR/inventory/fingerprint ]]
  [[ $(sha256sum "$STATE_DIR/inventory/hardware.tsv") == "$hardware_before" ]]
  [[ $(sha256sum "$STATE_DIR/inventory/fingerprint") == "$fingerprint_before" ]]
  [[ ! -e $STATE_DIR/.lock ]]
  ! awk -F '\t' '$3 == "active" { found=1 } END { exit found ? 0 : 1 }' "$STATE_DIR/transactions.tsv"
  [[ ! -s $STATE_DIR/installed-packages.txt && ! -s $STATE_DIR/services.txt ]]
)

echo 'test_startup_flow: ok'
