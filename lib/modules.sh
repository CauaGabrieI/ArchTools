#!/usr/bin/env bash

declare -ga MODULE_ORDER=()
declare -gA MODULE_DESCRIPTION=() MODULE_CATEGORY=() MODULE_CAPABILITIES=() MODULE_FUNCTIONS=() MODULE_READ_ONLY=() MODULE_ROLLBACK=()

module_register() {
  local name=$1 description=$2 category=$3 capabilities=$4 functions=$5 read_only=$6 rollback=${7:-no}
  [[ $name =~ ^[a-z][a-z0-9_-]*$ ]] || die "Nome de módulo inválido: $name"
  if [[ -z ${MODULE_DESCRIPTION[$name]+x} ]]; then MODULE_ORDER+=("$name"); fi
  MODULE_DESCRIPTION[$name]=$description
  MODULE_CATEGORY[$name]=$category
  MODULE_CAPABILITIES[$name]=$capabilities
  MODULE_FUNCTIONS[$name]=$functions
  MODULE_READ_ONLY[$name]=$read_only
  MODULE_ROLLBACK[$name]=$rollback
}

module_registry_init() {
  [[ ${MODULE_REGISTRY_INITIALIZED:-0} == 1 ]] && return 0
  module_register hardware "Hardware detection and inspection" hardware detect "detect_all,show_hardware" yes no
  module_register diagnostics "System and dependency diagnostics" diagnostics detect "detect_all,command -v" yes no
  module_register drivers "Hardware driver planning and installation" hardware detect,plan,execute,validate "detect_cpu,detect_gpu,driver_packages,execute_plan,validate_plan" no yes
  module_register storage "Storage inspection and safe TRIM planning" hardware detect,plan "detect_storage,add_service" no no
  module_register network "Network interface inspection and service planning" network detect,plan "detect_network,network_plan" no no
  module_register bluetooth "Bluetooth inspection and service planning" hardware detect,plan "detect_bluetooth,bluetooth_plan" no no
  module_register audio "Audio stack inspection and planning" multimedia detect,plan "detect_audio,audio_plan" yes no
  module_register desktop "Desktop environment planning" desktop plan,execute,validate "desktop_gnome,desktop_kde,desktop_xfce,desktop_cinnamon,desktop_hyprland,desktop_minimal" no yes
  module_register desktop-apps "Optional desktop component detection and planning" desktop detect,plan,execute,validate "desktop_components_show_suggestions,desktop_components_plan,execute_plan,validate_plan" no yes
  module_register gaming "Gaming profile planning" profile plan,execute,validate "profile_gaming,driver_packages,execute_plan,validate_plan" no yes
  MODULE_REGISTRY_INITIALIZED=1
}

module_list() {
  module_registry_init
  printf 'NAME\tCATEGORY\tCAPABILITIES\n'
  local module
  for module in "${MODULE_ORDER[@]}"; do
    printf '%s\t%s\t%s\n' "$module" "${MODULE_CATEGORY[$module]}" "${MODULE_CAPABILITIES[$module]}"
  done
}

module_info() {
  local module=$1
  module_registry_init
  [[ -n ${MODULE_DESCRIPTION[$module]+x} ]] || die "Módulo inexistente: $module"
  printf 'Nome: %s\nDescrição: %s\nCategoria: %s\nCapacidades: %s\nFunções: %s\nSomente leitura: %s\nRollback: %s\n' \
    "$module" "${MODULE_DESCRIPTION[$module]}" "${MODULE_CATEGORY[$module]}" \
    "${MODULE_CAPABILITIES[$module]}" "${MODULE_FUNCTIONS[$module]}" \
    "${MODULE_READ_ONLY[$module]}" "${MODULE_ROLLBACK[$module]}"
}
