#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd); source "$root/lib/detect.sh"; warn() { :; }; source "$root/hardware/storage.sh"
declare -A HARDWARE=(); detect_storage; [[ -n ${HARDWARE[root_fs]:-} ]]
cmd() { return 1; }; declare -A HARDWARE=(); detect_storage; [[ ${HARDWARE[storage_detection]} == limited && ${HARDWARE[trim]} == 0 ]]
echo 'test_storage: ok'
