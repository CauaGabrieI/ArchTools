#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
script=$root/tools/testing/nspawn.sh
source "$script"

for bad in '' / /home /var /var/lib /var/lib/machines /var/lib/machines/archtools-test/.. \
  /var/lib/machines/archtools-test/other /tmp/archtools-test; do
  if safe_target "$bad" >/dev/null 2>&1; then
    printf 'Unsafe path accepted: %s\n' "$bad" >&2; exit 1
  fi
done
DRY_RUN=1
safe_target "$BASE"
safe_target "$TEST"
base_rel='@/var/lib/machines/archtools-base'
valid_children=$(printf 'ID 373 gen 1 top level 372 path %s/var/lib/machines\nID 374 gen 1 top level 372 path %s/var/lib/portables' "$base_rel" "$base_rel")
validate_btrfs_children "$BASE" "$base_rel" "$valid_children"
if validate_btrfs_children "$BASE" "$base_rel" "ID 375 gen 1 top level 372 path $base_rel/home" >/dev/null 2>&1; then
  printf 'Unexpected nested Btrfs subvolume accepted\n' >&2; exit 1
fi
(
  # Root-only /var/lib/machines prevents the caller from detecting child
  # symlinks. The privileged check must be required before any real action.
  root_check() {
    if [[ $1 == test && $2 == '!' && $3 == -L && $4 == "$TEST" ]]; then return 1; fi
    return 0
  }
  DRY_RUN=0
  if safe_target "$TEST" >/dev/null 2>&1; then
    printf 'Privileged symlink check was skipped\n' >&2; exit 1
  fi
  DRY_RUN=1
  safe_target "$TEST"
)
(
  task_tmp=$(mktemp -d)
  trap 'rm -f -- "$task_tmp/link"; rmdir -- "$task_tmp"' EXIT
  ln -s /var/lib/machines "$task_tmp/link"
  MACHINES=$task_tmp/link
  BASE=$MACHINES/archtools-base
  TEST=$MACHINES/archtools-test
  if safe_target "$BASE" >/dev/null 2>&1; then exit 1; fi
)

# Every destructive command must refuse paths outside the two fixed names.
(
  as_root() { printf 'MUTATION %s\n' "$*" >&2; return 99; }
  for bad in '' / /home /var /var/lib /tmp/archtools-test; do
    if remove_target "$bad" test >/dev/null 2>&1; then exit 1; fi
  done
)

findmnt() { printf 'btrfs\n'; }
[[ $(filesystem) == btrfs ]]
unset -f findmnt
filesystem() { printf 'btrfs\n'; }
DRY_RUN=1
btrfs_plan=$(create_test)
[[ $btrfs_plan == *'btrfs subvolume snapshot'* ]]
filesystem() { printf 'ext4\n'; }
copy_plan=$(create_test)
[[ $copy_plan == *'cp -a --reflink=auto'* ]]
[[ $copy_plan != *'btrfs subvolume snapshot'* ]]

reset_plan=$(bash "$script" reset --dry-run)
[[ $reset_plan == *"$BASE"* && $reset_plan == *"$TEST"* ]]
case $(bash -c 'source "$1"; backend' _ "$script") in
  btrfs-snapshot) [[ $reset_plan == *'btrfs subvolume snapshot'* ]];;
  reflink-auto/copy) [[ $reset_plan == *'cp -a --reflink=auto'* ]];;
  *) printf 'Unknown filesystem backend in reset plan\n' >&2; exit 1;;
esac

failure_plan=$(bash "$script" test failure --dry-run)
[[ $failure_plan == *'./tools/testing/guest.sh failure begin'* &&
   $failure_plan == *'./tools/testing/guest.sh failure package'* &&
   $failure_plan == *'./tools/testing/guest.sh failure service'* &&
   $failure_plan == *'./tools/testing/guest.sh failure commit'* &&
   $failure_plan == *'./tools/testing/guest.sh failure files'* ]]
files_plan=$(bash "$script" test failure files --dry-run)
[[ $files_plan == *'./tools/testing/guest.sh failure files'* &&
   $files_plan != *'./tools/testing/guest.sh failure begin'* ]]

for args in 'invalid' 'test bogus' 'test integration bogus' 'test failure bogus' 'reset --writable' 'reset -- bogus' 'run'; do
  # Split only fixed test literals; never pass untrusted text through eval.
  read -r -a words <<< "$args"
  if bash "$script" "${words[@]}" >/dev/null 2>&1; then
    printf 'Invalid command accepted: %s\n' "$args" >&2; exit 1
  fi
done

# A missing guest must fail before any write to its filesystem.
root_check() { return 1; }
if (DRY_RUN=0; prepare_guest_marker) >/dev/null 2>&1; then exit 1; fi

# systemd-run --machine omits HOME, which makes ArchTools fail under set -u.
(
  start() { :; }
  as_root() {
    if IFS= read -r input; then printf 'INHERITED_STDIN=%s\n' "$input"; fi
    printf '%s\n' "$*"
  }
  command_line=$(printf 'sentinel\n' | guest 'true')
  [[ $command_line == *'--setenv=HOME=/root'* ]]
  [[ $command_line == *'--setenv=LOGNAME=root'* ]]
  [[ $command_line != *INHERITED_STDIN* ]]
)

echo 'test_nspawn: ok'
