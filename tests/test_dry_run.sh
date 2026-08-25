#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
state=$(mktemp -d)
PATH="$root/tests/mock-bin:$PATH" XDG_STATE_HOME="$state" OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" "$root/install.sh" --desktop minimal --profile minimal --dry-run >/dev/null
[[ ! -e "$state/arch-smart-postinstall" ]]
echo 'test_dry_run: ok'
