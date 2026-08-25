#!/usr/bin/env bash
set -Eeuo pipefail
PLAN_PACKAGES=(); source "$(cd "$(dirname "$0")/.." && pwd)/lib/packages.sh"; plan_package mesa; plan_package mesa; [[ ${#PLAN_PACKAGES[@]} == 1 ]]; echo 'test_packages: ok'
