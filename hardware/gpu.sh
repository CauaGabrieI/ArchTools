#!/usr/bin/env bash
detect_gpu() {
  local lines=''; cmd lspci && lines=$(lspci -nnk 2>/dev/null | grep -Ei 'VGA compatible|3D controller|Display controller' || true)
  HARDWARE[gpus]=$(sed ':a;N;$!ba;s/\n/; /g' <<<"$lines"); [[ -n ${HARDWARE[gpus]} ]] || HARDWARE[gpus]="não detectada (lspci indisponível)"
  grep -Eqi 'Advanced Micro Devices|AMD/ATI|(^|[^[:alnum:]])AMD([^[:alnum:]]|$)' <<<"$lines" && HARDWARE[gpu_amd]=1 || HARDWARE[gpu_amd]=0
  grep -Eqi '(^|[^[:alnum:]])NVIDIA([^[:alnum:]]|$)' <<<"$lines" && HARDWARE[gpu_nvidia]=1 || HARDWARE[gpu_nvidia]=0
  grep -Eqi '(^|[^[:alnum:]])Intel([^[:alnum:]]|$)' <<<"$lines" && HARDWARE[gpu_intel]=1 || HARDWARE[gpu_intel]=0
  if grep -Eqi 'virtio|qxl|vmware|virtualbox' <<<"$lines"; then HARDWARE[gpu_vendor]=virtio
  elif (( HARDWARE[gpu_amd] + HARDWARE[gpu_intel] + HARDWARE[gpu_nvidia] == 0 )); then HARDWARE[gpu_vendor]=unknown
  else HARDWARE[gpu_vendor]=detected; fi
  HARDWARE[opengl]=$(cmd glxinfo && glxinfo -B 2>/dev/null | awk -F: '/OpenGL renderer/ {gsub(/^[[:space:]]+/,"",$2);print $2;exit}' || true)
  HARDWARE[vulkan]=$(cmd vulkaninfo && vulkaninfo --summary 2>/dev/null | grep -m1 'GPU' || true)
}
