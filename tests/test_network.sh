#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/hardware/network.sh"; declare -A HARDWARE=(); detect_network; [[ -n ${HARDWARE[network]} ]]; echo 'test_network: ok'
