#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$PROJECT_DIR/lib/core.sh"; load_modules; choice=""
if [[ ${1:-} != --* && ${1:-} != -h ]]; then choice=$1; shift; fi
archtools_tool_main desktop "$choice" "$@"