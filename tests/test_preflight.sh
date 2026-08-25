#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
state=$(mktemp -d)
trap 'rm -rf "$state"' EXIT

common_env=(PATH="$root/tests/mock-bin:$PATH" XDG_STATE_HOME="$state" OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch")
normal=$(env "${common_env[@]}" "$root/archtools" preflight)
verbose=$(env "${common_env[@]}" "$root/archtools" preflight --verbose)
[[ $normal == *'Preflight: OK'* ]]
[[ $verbose == *'caminho:'* && $verbose == *'nenhum pacote, serviço ou arquivo será alterado'* ]]
[[ ! -e "$state/arch-smart-postinstall" ]]

if env "${common_env[@]}" OS_RELEASE_FILE="$state/missing-os-release" "$root/archtools" preflight >/dev/null 2>&1; then
  exit 1
fi
[[ ! -e "$state/arch-smart-postinstall" ]]

cd /tmp
external=$(env "${common_env[@]}" "$root/archtools" preflight)
[[ $external == *'Preflight: OK'* ]]
echo 'test_preflight: ok'