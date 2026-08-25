#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT

source "$root/lib/detect.sh"
source "$root/hardware/cpu.sh"
source "$root/hardware/memory.sh"
source "$root/hardware/storage.sh"
warn() { :; }

cat > "$task_tmp/cpuinfo" <<'EOF'
vendor_id : AuthenticAMD
model name : AMD Ryzen 7 5700X 8-Core Processor
EOF
declare -A HARDWARE=()
CPUINFO_FILE="$task_tmp/cpuinfo"
lscpu() { printf 'ID de fornecedor: AuthenticAMD\nNome do modelo: AMD incorreto se localizado\nCPU(s): 16\n'; }
detect_cpu
[[ ${HARDWARE[cpu_vendor]} == AMD && ${HARDWARE[cpu_model]} == 'AMD Ryzen 7 5700X 8-Core Processor' ]]

cat > "$task_tmp/meminfo" <<'EOF'
MemTotal:        1048576 kB
MemAvailable:     524288 kB
EOF
MEMINFO_FILE="$task_tmp/meminfo"
free() { printf 'Mem.: texto localizado que não deve ser usado\n'; }
detect_memory
[[ ${HARDWARE[ram_total]} == 1.0Gi && ${HARDWARE[ram_available]} == 0.5Gi ]]

lsblk() {
  if [[ $* == *'NAME,TYPE,TRAN,ROTA,MODEL'* ]]; then
    printf 'sda disk sata 1 Disk\nsr0 rom sata 1 CDROM\nloop0 loop - 0 Loop\nzram0 zram - 0 Zram\ndm-0 dm - 0 Mapper\n'
  else printf 'disk 1\nrom 1\nloop 0\n'; fi
}
findmnt() { [[ $* == *FSTYPE* ]] && printf 'ext4\n' || printf '/dev/sda1\n'; }
declare -A HARDWARE=()
detect_storage
[[ ${HARDWARE[storage_summary]} == *'sr0 (ROM, CDROM)'* ]]
[[ ${HARDWARE[storage_summary]} != *loop0* && ${HARDWARE[storage_summary]} != *zram0* && ${HARDWARE[storage_summary]} != *dm-0* ]]

source "$root/lib/packages.sh"
source "$root/lib/validator.sh"
PLAN_PACKAGES=(steam); PLAN_OPTIONAL_PACKAGES=(); PLAN_NOTES=(); PROFILE=gaming
is_package_installed() { return 1; }; package_available() { [[ $1 != missing ]]; }
printf '[core]\nInclude = /etc/pacman.d/mirrorlist\n#[multilib]\n' > "$task_tmp/pacman.conf"
PACMAN_CONF="$task_tmp/pacman.conf"
if validate_plan_pre_execution; then exit 1; fi
[[ ${PLAN_PACKAGES_UNAVAILABLE[*]} == steam && ${#PLAN_PACKAGES_AVAILABLE[@]} == 0 && ${PLAN_NOTES[*]} == *'multilib está desabilitado'* ]]

printf '[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' > "$task_tmp/pacman.conf"
package_available() { [[ $1 != steam && $1 != missing ]]; }
PLAN_PACKAGES=(steam); PLAN_NOTES=()
if validate_plan_pre_execution; then exit 1; fi
[[ ${PLAN_PACKAGES_UNAVAILABLE[*]} == steam && ${#PLAN_PACKAGES_AVAILABLE[@]} == 0 ]]

PLAN_PACKAGES=(missing); PLAN_NOTES=(); PROFILE=minimal
if validate_plan_pre_execution; then exit 1; fi
[[ ${PLAN_PACKAGES_UNAVAILABLE[*]} == missing ]]

source "$root/lib/logger.sh"
source "$root/lib/state.sh"
source "$root/lib/transaction.sh"
source "$root/lib/executor.sh"
STATE_DIR="$task_tmp/prevalidation-state"; RUN_ID=prevalidation; DRY_RUN=0; LOG_FILE=''; APP_ID=arch-smart-postinstall
PLAN_SERVICES_ENABLE=(); sudo_called=0
sudo() { sudo_called=1; return 0; }
if execute_plan; then exit 1; fi
[[ $sudo_called == 0 && ! -e $STATE_DIR/transactions.tsv ]]

source "$root/lib/planner.sh"
source "$root/drivers/firmware.sh"
plan_amd_driver() { :; }; plan_intel_driver() { :; }; plan_nvidia_driver() { :; }
PLAN_PACKAGES=(); PLAN_NOTES=(); PROFILE=minimal
declare -A HARDWARE=([cpu_vendor]=AMD [machine]=VM [virtualization]=kvm [gpu_amd]=0 [gpu_intel]=0 [gpu_nvidia]=0)
driver_packages
[[ " ${PLAN_PACKAGES[*]} " != *' amd-ucode '* ]]

source "$root/desktop/xfce.sh"
PLAN_PACKAGES=(); PLAN_SERVICES_ENABLE=()
add_service() { PLAN_SERVICES_ENABLE+=("$1"); }
desktop_xfce
[[ " ${PLAN_PACKAGES[*]} " != *' xfce4 '* && " ${PLAN_PACKAGES[*]} " != *' xfce4-goodies '* ]]
for package in "${PLAN_PACKAGES[@]}"; do [[ $package != missing ]]; done

cli_state="$task_tmp/cli-state"; mkdir -p "$cli_state"
if XDG_STATE_HOME="$cli_state" "$root/install.sh" --invalid-option >/dev/null 2>&1; then exit 1; fi
[[ ! -e $cli_state/arch-smart-postinstall ]]
before=$([[ -d $root/logs ]] && find "$root/logs" -maxdepth 1 -type f | wc -l || printf '0\n')
output=$(PATH="$root/tests/mock-bin:$PATH" XDG_STATE_HOME="$cli_state" OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" "$root/install.sh" --detect-only)
after=$([[ -d $root/logs ]] && find "$root/logs" -maxdepth 1 -type f | wc -l || printf '0\n')
[[ $(grep -c '^Hardware detectado$' <<< "$output") == 1 && $before == "$after" ]]

printf '# [multilib]\n' > "$task_tmp/disabled-multilib.conf"
set +e
invalid_plan=$(PATH="$root/tests/mock-bin:$PATH" XDG_STATE_HOME="$cli_state" OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" \
  PACMAN_CONF="$task_tmp/disabled-multilib.conf" "$root/install.sh" --desktop gnome --profile gaming --dry-run 2>&1)
invalid_rc=$?
set -e
[[ $invalid_rc == 1 && $invalid_plan == *'Plano inválido; nenhuma alteração foi executada.'* ]]
[[ $invalid_plan != *'Module: lib/core.sh'* && $invalid_plan != *'Falha na linha'* ]]
[[ ! -e $cli_state/arch-smart-postinstall ]]

echo 'test_audit_regressions: ok'
