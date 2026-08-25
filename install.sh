#!/usr/bin/env bash
# Arch Linux Smart Post-Install — safe entry point.
set -Eeuo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/core.sh
source "$PROJECT_DIR/lib/core.sh"
load_modules
main "$@"
