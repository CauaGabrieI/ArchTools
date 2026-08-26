#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$PROJECT_DIR/lib/core.sh"; load_modules; desktop_apps_cli_main "$@"
