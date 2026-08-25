#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
state=$(mktemp -d)
trap 'rm -rf "$state"' EXIT

for tool in "$root"/tools/*.sh; do bash "$tool" --help >/dev/null; done
PATH="$root/tests/mock-bin:$PATH" XDG_STATE_HOME="$state" OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" \
  "$root/tools/gpu.sh" --dry-run >/dev/null
[[ ! -e "$state/arch-smart-postinstall" ]]

source "$root/lib/core.sh"
load_modules
declare -A HARDWARE=([gpu_vendor]=unknown [gpu_amd]=0 [gpu_intel]=0 [gpu_nvidia]=0)
PROFILE=minimal
archtools_build_module_plan gpu
[[ ${#PLAN_PACKAGES[@]} == 0 ]]
echo 'test_tools: ok'