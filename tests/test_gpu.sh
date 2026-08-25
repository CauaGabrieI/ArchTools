#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd); PROJECT_DIR=$root
source "$root/lib/core.sh"; load_modules
run_case() {
  local name=$1 description=$2 expected_amd=$3 expected_intel=$4 expected_nvidia=$5 expected_vendor=$6
  declare -g SAMPLE_GPU="$description"; declare -gA HARDWARE=()
  HARDWARE[bluetooth]='não detectado'; HARDWARE[network_manager]=active; HARDWARE[audio]=ALSA; HARDWARE[display_manager]=none; HARDWARE[trim]=0
  cmd() { [[ $1 == lspci ]]; }; lspci() { printf '%s\n' "$SAMPLE_GPU"; }; detect_gpu
  [[ ${HARDWARE[gpu_amd]} == "$expected_amd" && ${HARDWARE[gpu_intel]} == "$expected_intel" && ${HARDWARE[gpu_nvidia]} == "$expected_nvidia" && ${HARDWARE[gpu_vendor]} == "$expected_vendor" ]]
  DESKTOP=minimal; PROFILE=minimal; build_plan "$DESKTOP" "$PROFILE"
  [[ $expected_amd == 1 ]] || ! [[ " ${PLAN_PACKAGES[*]} " == *' vulkan-radeon '* ]]
  [[ $expected_intel == 1 ]] || ! [[ " ${PLAN_PACKAGES[*]} " == *' vulkan-intel '* ]]
  [[ $expected_nvidia == 1 ]] || ! [[ " ${PLAN_PACKAGES[*]} " == *' nvidia-utils '* ]]
}
run_case amd '01:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Radeon' 1 0 0 detected
run_case intel '00:02.0 VGA compatible controller: Intel Corporation Graphics' 0 1 0 detected
run_case nvidia '01:00.0 VGA compatible controller: NVIDIA Corporation GPU' 0 0 1 detected
run_case amd_nvidia $'01:00.0 VGA compatible controller: AMD Radeon\n02:00.0 3D controller: NVIDIA GPU' 1 0 1 detected
run_case intel_nvidia $'00:02.0 VGA compatible controller: Intel Graphics\n01:00.0 3D controller: NVIDIA GPU' 0 1 1 detected
run_case amd_intel $'00:02.0 VGA compatible controller: Intel Graphics\n01:00.0 3D controller: AMD Radeon' 1 1 0 detected
run_case virtio '00:02.0 VGA compatible controller: Red Hat, Inc. Virtio GPU' 0 0 0 virtio
run_case unknown '00:02.0 VGA compatible controller: Example Devices Foo' 0 0 0 unknown
run_case none '' 0 0 0 unknown
echo 'test_gpu: ok'
