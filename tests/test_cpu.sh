#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/hardware/cpu.sh"
declare -A HARDWARE=(); lscpu() { printf 'Vendor ID: AuthenticAMD\nModel name: Test CPU\n'; }; detect_cpu
[[ ${HARDWARE[cpu_vendor]} == AMD && ${HARDWARE[cpu_model]} == 'Test CPU' ]]; echo 'test_cpu: ok'
