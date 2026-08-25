#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
state=$(mktemp -d)
trap 'rm -rf "$state"' EXIT

"$root/archtools" --help >/dev/null
PATH="$root/tests/mock-bin:$PATH" XDG_STATE_HOME="$state" OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" \
  "$root/archtools" hardware detect >/dev/null
drivers_output=$(PATH="$root/tests/mock-bin:$PATH" XDG_STATE_HOME="$state" OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" \
  "$root/archtools" drivers detect)
[[ $drivers_output != *"Plano da ferramenta"* ]]
PATH="$root/tests/mock-bin:$PATH" XDG_STATE_HOME="$state" OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" \
  "$root/archtools" drivers install --dry-run >/dev/null
[[ ! -e "$state/arch-smart-postinstall" ]]

if "$root/archtools" unknown >/dev/null 2>&1; then exit 1; fi
echo 'test_cli: ok'
