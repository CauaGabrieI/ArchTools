#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT

PROJECT_DIR=$root
XDG_STATE_HOME="$task_tmp/state"
source "$root/lib/core.sh"
load_modules

reset_desktop_selection() {
  DESKTOP=kde; USAGE_PROFILE=desktop; PROFILE=desktop
  DESKTOP_PRESET=''; DESKTOP_PRESET_EXPLICIT=0
  DESKTOP_COMPONENTS_SPEC=''; DESKTOP_COMPONENTS_EXPLICIT=0
  PLAN_PACKAGES=(); DESKTOP_COMPONENTS_SELECTED=()
}

# Preset minimal contains only desktop core; recommended reuses all registry
# categories; custom keeps only the explicit selection.
reset_desktop_selection
DESKTOP_PRESET=minimal; desktop_preset_resolve; desktop_components_plan kde "$DESKTOP_COMPONENTS_SPEC"
[[ $DESKTOP_COMPONENTS_SPEC == none && ${#PLAN_PACKAGES[@]} == 0 ]]

reset_desktop_selection
DESKTOP_PRESET=recommended; desktop_preset_resolve; desktop_components_plan kde "$DESKTOP_COMPONENTS_SPEC"
[[ $DESKTOP_COMPONENTS_SPEC == all && ${PLAN_PACKAGES[*]} == 'konsole falkon discover dolphin kate ark' ]]

reset_desktop_selection
DESKTOP_PRESET=custom; DESKTOP_COMPONENTS_SPEC=terminal,files,editor
desktop_preset_resolve; desktop_components_plan kde "$DESKTOP_COMPONENTS_SPEC"
[[ ${PLAN_PACKAGES[*]} == 'konsole dolphin kate' ]]

# Non-TTY/default resolution is the same as the interactive default.
reset_desktop_selection
parse_cli --usage-profile desktop --desktop kde
desktop_preset_resolve
[[ $DESKTOP_PRESET == recommended && $DESKTOP_COMPONENTS_SPEC == all ]]

# Validate the final composed plan, not only the component registry.
prepare_final_kde_plan() {
  reset_desktop_selection
  DESKTOP_PRESET=$1; DESKTOP_COMPONENTS_SPEC=${2:-}
  HARDWARE_PROFILE=vm; HARDWARE_PROFILE_DETECTED=vm
  HARDWARE=([machine]=VM [virtualization]=kvm [cpu_vendor]=OTHER [gpu_amd]=0 [gpu_intel]=0 [gpu_nvidia]=0 [trim]=0 [display_manager]=none [desktop]=none)
  desktop_preset_resolve
  build_plan kde desktop
  desktop_components_plan kde "$DESKTOP_COMPONENTS_SPEC"
}
assert_plan_has() { local package; for package in "$@"; do [[ " ${PLAN_PACKAGES[*]} " == *" $package "* ]]; done; }
assert_plan_lacks() { local package; for package in "$@"; do [[ " ${PLAN_PACKAGES[*]} " != *" $package "* ]]; done; }

prepare_final_kde_plan minimal
assert_plan_has plasma-desktop sddm xdg-desktop-portal-kde
assert_plan_lacks konsole falkon discover dolphin kate ark

prepare_final_kde_plan recommended
assert_plan_has plasma-desktop sddm xdg-desktop-portal-kde konsole falkon discover dolphin kate ark

prepare_final_kde_plan custom terminal,files
assert_plan_has plasma-desktop sddm xdg-desktop-portal-kde konsole dolphin
assert_plan_lacks falkon discover kate ark

# Legacy desktop-components selects custom automatically; conflicts are rejected.
reset_desktop_selection
parse_cli --desktop kde --usage-profile desktop --desktop-components terminal,files --dry-run
[[ $DESKTOP_PRESET == custom && $DESKTOP_COMPONENTS_SPEC == terminal,files ]]
if ( reset_desktop_selection; parse_cli --desktop kde --usage-profile desktop --desktop-preset minimal --desktop-components terminal ); then exit 1; fi
if ( reset_desktop_selection; parse_cli --desktop kde --usage-profile desktop --desktop-preset recommended --desktop-components terminal ); then exit 1; fi
for usage in minimal server; do
  if invalid_usage_output=$(reset_desktop_selection; parse_cli --usage-profile "$usage" --desktop kde --desktop-preset minimal 2>&1); then exit 1; fi
  [[ $invalid_usage_output == *"Usage profile $usage não instala ambiente gráfico"* ]]
done

# Minimal/server without a desktop do not enter preset selection.
for usage in minimal server; do
  reset_desktop_selection; DESKTOP=minimal; USAGE_PROFILE=$usage
  desktop_preset_interactive_select "$DESKTOP"
  [[ -z $DESKTOP_PRESET ]]
done

# A different existing desktop is retained and its display manager guards the
# new one. The same desktop is presented as already detected.
PLAN_PACKAGES_INSTALLED=(); PLAN_PACKAGES_AVAILABLE=(plasma-desktop); PLAN_PACKAGES_UNAVAILABLE=(); PLAN_PACKAGES_OPTIONAL_SKIPPED=()
PLAN_SERVICES_ENABLE=(sddm.service); PLAN_SERVICES_CONFIGURED=(); PLAN_NOTES=(); PLAN_WARNINGS=()
HARDWARE_PROFILE=vm; USAGE_PROFILE=desktop; DESKTOP=kde; DESKTOP_PRESET=recommended
HARDWARE[desktop]=GNOME; HARDWARE[display_manager]=gdm.service
guard_existing_display_manager
[[ ${#PLAN_SERVICES_ENABLE[@]} == 0 && ${#PLAN_WARNINGS[@]} == 1 && ${#PLAN_SERVICES_DISABLE[@]} == 0 ]]
different_output=$(show_plan)
[[ $different_output == *'Desktop existente'* && $different_output == *'GNOME'* ]]
[[ $different_output == *'não será removido'* && $different_output == *'não habilitado automaticamente'* ]]

HARDWARE[desktop]='KDE Plasma'; PLAN_WARNINGS=()
same_output=$(show_plan)
[[ $same_output == *'KDE Plasma (já detectado)'* && $same_output != *'Desktop existente'* ]]

# Normal output has no timestamp/ANSI or empty sections. Details retain exact
# packages, and verbose includes technical notes.
LOG_FILE="$task_tmp/install.log"; VERBOSE=0
normal_log=$(log INFO 'mensagem normal')
[[ $normal_log == *'mensagem normal'* && ! $normal_log =~ \[[0-9]{4}-[0-9]{2}-[0-9]{2} ]]
grep -Eq '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8}\] \[INFO\] mensagem normal$' "$LOG_FILE"

PLAN_PACKAGES_INSTALLED=(); PLAN_PACKAGES_AVAILABLE=(plasma-desktop konsole); PLAN_PACKAGES_UNAVAILABLE=(); PLAN_PACKAGES_OPTIONAL_SKIPPED=()
PLAN_SERVICES_ENABLE=(sddm.service); PLAN_SERVICES_CONFIGURED=(); PLAN_NOTES=('technical note'); PLAN_WARNINGS=()
HARDWARE[desktop]=none
plan_output=$(show_plan)
[[ $plan_output == *'Pacotes a instalar:'* && $plan_output == *'plasma-desktop'* && $plan_output == *'konsole'* ]]
[[ $plan_output != *'(nenhum)'* && $plan_output != *'Indisponíveis:'* && $plan_output != *'technical note'* ]]
VERBOSE=1; verbose_output=$(show_plan); [[ $verbose_output == *'technical note'* ]]

NO_COLOR=1 colorless=$(ui_header ArchTools)
[[ $colorless != *$'\033['* ]]
unset NO_COLOR
non_tty=$(ui_ok 'System check')
[[ $non_tty != *$'\033['* ]]

# Compact GPU labels never expose PCI/class/vendor IDs; raw detection remains unchanged.
raw_vm='00:02.0 VGA compatible controller [0300]: VMware SVGA II Adapter [15ad:0405]'
raw_amd='08:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 23 [Radeon RX 6600] [1002:73ff] (rev c7)'
raw_intel='00:02.0 VGA compatible controller [0300]: Intel Corporation UHD Graphics 770 [8086:4680] (rev 0c)'
raw_nvidia='01:00.0 3D controller [0302]: NVIDIA Corporation AD107M [GeForce RTX 4060] [10de:28a0] (rev a1)'
vm_gpu=$(summarize_gpus "$raw_vm"); [[ $vm_gpu == 'VMware SVGA II Adapter' ]]
multi_gpu=$(summarize_gpus "$raw_amd; $raw_intel; $raw_nvidia")
[[ $multi_gpu == *'AMD Radeon RX 6600'* && $multi_gpu == *'Intel UHD Graphics 770'* && $multi_gpu == *'NVIDIA'* ]]
[[ $multi_gpu != *'VGA compatible controller'* && $multi_gpu != *'[0300]'* && $multi_gpu != *'[1002:73ff]'* ]]
HARDWARE[gpus]=$raw_vm; summary_output=$(show_hardware_summary)
[[ $summary_output == *'VMware SVGA II Adapter'* && $summary_output != *'00:02.0'* && ${HARDWARE[gpus]} == "$raw_vm" ]]

# Simulated VM + Desktop + KDE + Recommended flow remains read-only in dry-run.
ux_state="$task_tmp/ux-state"; mkdir -p "$ux_state"
ux_output=$(env -u XDG_CURRENT_DESKTOP -u DESKTOP_SESSION NO_COLOR=1 \
  PATH="$root/tests/mock-bin:$PATH" XDG_STATE_HOME="$ux_state" \
  OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" \
  "$root/install.sh" --hardware-profile vm --usage-profile desktop --desktop kde \
  --desktop-preset recommended --dry-run)
[[ $ux_output == *'ArchTools'* && $ux_output == *'Verificação do sistema'* && $ux_output == *'Hardware detectado'* ]]
[[ $ux_output == *'Hardware'*'VM'* && $ux_output == *'Uso'*'Desktop'* ]]
[[ $ux_output == *'KDE Plasma'* && $ux_output == *'Recomendado'* && $ux_output == *'Plano de instalação'* ]]
[[ $ux_output == *'konsole'* && $ux_output == *'sddm.service'* ]]
[[ $ux_output != *$'\033['* && ! $ux_output =~ \[[0-9]{4}-[0-9]{2}-[0-9]{2} ]]
[[ $ux_output != *'Kernel:'* && $ux_output != *'Arquitetura:'* ]]
[[ ! -e $ux_state/arch-smart-postinstall ]]

verbose_output=$(env -u XDG_CURRENT_DESKTOP -u DESKTOP_SESSION NO_COLOR=1 \
  PATH="$root/tests/mock-bin:$PATH" XDG_STATE_HOME="$ux_state" \
  OS_RELEASE_FILE="$root/tests/fixtures/os-release-arch" \
  "$root/install.sh" --hardware-profile vm --usage-profile desktop --desktop kde \
  --desktop-preset minimal --verbose --dry-run)
[[ $verbose_output == *'Hardware detectado'* && $verbose_output == *'Kernel:'* && $verbose_output == *'Arquitetura:'* ]]
[[ ! -e $ux_state/arch-smart-postinstall ]]

echo 'test_ux_presets: ok'
