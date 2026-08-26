#!/usr/bin/env bash
service_is_enabled() { [[ $(systemctl is-enabled "$1" 2>/dev/null || true) == enabled ]]; }
add_service() {
  local s=$1
  if service_is_enabled "$s"; then
    [[ " ${PLAN_SERVICES_CONFIGURED[*]} " == *" $s "* ]] || PLAN_SERVICES_CONFIGURED+=("$s")
    return 0
  fi
  [[ " ${PLAN_SERVICES_ENABLE[*]} " == *" $s "* ]] || PLAN_SERVICES_ENABLE+=("$s")
}
driver_packages() {
  plan_firmware
  if [[ ${HARDWARE[machine]:-} != VM && ${HARDWARE[virtualization]:-none} == none ]]; then
    if [[ ${HARDWARE[cpu_vendor]:-} == AMD ]]; then plan_package amd-ucode; fi
    if [[ ${HARDWARE[cpu_vendor]:-} == INTEL ]]; then plan_package intel-ucode; fi
  else
    PLAN_NOTES+=("[SKIP] Microcode do host não será instalado dentro de máquina virtual.")
  fi
  if [[ ${HARDWARE[gpu_amd]:-0} == 1 ]]; then plan_amd_driver; fi
  if [[ ${HARDWARE[gpu_intel]:-0} == 1 ]]; then plan_intel_driver; fi
  if [[ ${HARDWARE[gpu_nvidia]:-0} == 1 ]]; then plan_nvidia_driver; fi
}
build_plan() {
  local desktop=$1 usage_profile=$2
  PLAN_PACKAGES=(); PLAN_OPTIONAL_PACKAGES=(); PLAN_SERVICES_ENABLE=(); PLAN_SERVICES_CONFIGURED=(); PLAN_NOTES=(); PLAN_WARNINGS=(); PLAN_FILES=()
  USAGE_PROFILE=$usage_profile; PROFILE=$usage_profile
  resolve_hardware_profile
  hardware_profile_apply "$HARDWARE_PROFILE"
  usage_profile_apply "$USAGE_PROFILE"
  driver_packages; network_plan; audio_plan; bluetooth_plan
  if [[ $USAGE_PROFILE != minimal && $USAGE_PROFILE != server && $desktop != minimal ]]; then desktop_plan "$desktop"; fi
  guard_existing_display_manager
  if [[ ${HARDWARE[trim]:-0} == 1 ]]; then add_service fstrim.timer; fi
  PLAN_NOTES+=("Nenhuma operação de disco, formatação, partição, bootloader, overclock ou reboot será executada.")
}
guard_existing_display_manager() {
  local current=${HARDWARE[display_manager]:-none} planned current_name planned_name
  local -a retained=()
  [[ $current != none ]] || return 0
  for planned in "${PLAN_SERVICES_ENABLE[@]}"; do
    case "$planned" in gdm.service|sddm.service|lightdm.service)
      if [[ $planned != "$current" ]]; then
        current_name=${current%.service}; planned_name=${planned%.service}
        PLAN_WARNINGS+=("${current_name^^} está habilitado; ${planned_name^^} será instalado, mas não habilitado automaticamente.")
        continue
      fi
      ;;
    esac
    retained+=("$planned")
  done
  PLAN_SERVICES_ENABLE=("${retained[@]}")
}
show_plan() {
  local current_desktop
  current_desktop=$(normalize_desktop "${HARDWARE[desktop]:-none}")
  ui_header 'Plano de instalação'
  ui_key_value 'Hardware' "$(ui_title_case "${HARDWARE_PROFILE:-auto}")"
  ui_key_value 'Uso' "$(ui_title_case "${USAGE_PROFILE:-minimal}")"
  if [[ ${DESKTOP:-minimal} != minimal ]]; then
    if [[ $current_desktop == "$DESKTOP" ]]; then
      ui_key_value 'Desktop' "$(ui_title_case "$DESKTOP") (já detectado)"
    else
      ui_key_value 'Desktop' "$(ui_title_case "$DESKTOP")"
    fi
    ui_key_value 'Preset' "$(ui_title_case "${DESKTOP_PRESET:-minimal}")"
  fi
  ui_section 'Pacotes'
  ui_key_value 'Novos' "${#PLAN_PACKAGES_AVAILABLE[@]}"
  ui_key_value 'Já instalados' "${#PLAN_PACKAGES_INSTALLED[@]}"
  if ((${#PLAN_SERVICES_ENABLE[@]})); then ui_section 'Serviços'; printf '  + %s\n' "${PLAN_SERVICES_ENABLE[@]}"; fi
  if [[ $current_desktop != unknown && $current_desktop != minimal && $current_desktop != "$DESKTOP" && ${DESKTOP:-minimal} != minimal ]]; then
    ui_section 'Desktop existente'
    ui_key_value 'Instalado' "$(ui_title_case "$current_desktop")"
    ui_info "$(ui_title_case "$DESKTOP") será instalado ao lado dele; o desktop existente não será removido."
  fi
  local warning
  for warning in "${PLAN_WARNINGS[@]}"; do ui_warn "$warning"; done
  if (( VERBOSE || DRY_RUN )) || [[ ! -t 1 ]]; then show_plan_details; fi
}

show_plan_details() {
  ui_section 'Detalhes'
  ((${#PLAN_PACKAGES_INSTALLED[@]})) && { printf '  Já instalados:\n'; printf '    = %s\n' "${PLAN_PACKAGES_INSTALLED[@]}"; }
  ((${#PLAN_PACKAGES_AVAILABLE[@]})) && { printf '  Pacotes a instalar:\n'; printf '    + %s\n' "${PLAN_PACKAGES_AVAILABLE[@]}"; }
  ((${#PLAN_PACKAGES_UNAVAILABLE[@]})) && { printf '  Indisponíveis:\n'; printf '    ! %s\n' "${PLAN_PACKAGES_UNAVAILABLE[@]}"; }
  ((${#PLAN_PACKAGES_OPTIONAL_SKIPPED[@]})) && { printf '  Opcionais ignorados:\n'; printf '    - %s\n' "${PLAN_PACKAGES_OPTIONAL_SKIPPED[@]}"; }
  ((${#PLAN_SERVICES_ENABLE[@]})) && { printf '  Serviços a habilitar:\n'; printf '    + %s\n' "${PLAN_SERVICES_ENABLE[@]}"; }
  ((${#PLAN_SERVICES_CONFIGURED[@]})) && { printf '  Serviços já configurados:\n'; printf '    = %s\n' "${PLAN_SERVICES_CONFIGURED[@]}"; }
  if (( VERBOSE )) && ((${#PLAN_NOTES[@]})); then printf '  Notas:\n'; printf '    - %s\n' "${PLAN_NOTES[@]}"; fi
}
select_interactively_if_needed() {
  local answer
  if (( ! HARDWARE_PROFILE_EXPLICIT )) && [[ -t 0 ]]; then
    ui_section 'Perfil de hardware'
    ui_key_value 'Detectado' "$(ui_title_case "$HARDWARE_PROFILE_DETECTED")"
    printf 'Usar este perfil? [S/n] '; read -r answer
    if [[ $answer =~ ^[Nn]$ ]]; then printf 'Perfil [desktop/notebook/server/vm]: '; read -r HARDWARE_PROFILE; else HARDWARE_PROFILE=$HARDWARE_PROFILE_DETECTED; fi
  fi
  [[ $HARDWARE_PROFILE =~ ^(auto|desktop|notebook|server|vm)$ ]] || die "Hardware profile inválido: $HARDWARE_PROFILE"
  resolve_hardware_profile
  if [[ -z $USAGE_PROFILE && -t 0 ]]; then
    ui_section 'Perfil de uso'
    printf '  1) Minimal\n  2) Desktop\n  3) Gaming\n  4) Desenvolvimento\n  5) Servidor\n\nSelecione [2]: '
    read -r answer
    case "${answer:-2}" in 1|minimal) USAGE_PROFILE=minimal;; 2|desktop) USAGE_PROFILE=desktop;; 3|gaming) USAGE_PROFILE=gaming;; 4|development) USAGE_PROFILE=development;; 5|server) USAGE_PROFILE=server;; *) USAGE_PROFILE=$answer;; esac
  fi
  [[ ${USAGE_PROFILE:-minimal} =~ ^(minimal|desktop|gaming|development|server)$ ]] || die "Usage profile inválido: $USAGE_PROFILE"
  USAGE_PROFILE=${USAGE_PROFILE:-minimal}; PROFILE=$USAGE_PROFILE
  if [[ -z $DESKTOP && $USAGE_PROFILE != minimal && $USAGE_PROFILE != server && -t 0 ]]; then
    ui_section 'Desktop'
    printf '  1) GNOME\n  2) KDE Plasma\n  3) XFCE\n  4) Cinnamon\n  5) Hyprland\n  6) Nenhum\n\nSelecione [6]: '
    read -r answer
    case "${answer:-6}" in 1|gnome) DESKTOP=gnome;; 2|kde) DESKTOP=kde;; 3|xfce) DESKTOP=xfce;; 4|cinnamon) DESKTOP=cinnamon;; 5|hyprland) DESKTOP=hyprland;; 6|minimal|none) DESKTOP=minimal;; *) DESKTOP=$answer;; esac
  fi
  DESKTOP=${DESKTOP:-minimal}
  [[ $DESKTOP =~ ^(gnome|kde|xfce|cinnamon|hyprland|minimal)$ ]] || die "Desktop inválido: $DESKTOP"
  if [[ $DESKTOP != minimal ]]; then
    ui_section 'Desktop'
    ui_key_value 'Selecionado' "$(ui_title_case "$DESKTOP")"
  fi
}
confirm_plan() {
  (( ASSUME_YES )) && return 0
  local answer
  while true; do
    read -r -p 'Continuar? [s/N/d detalhes] ' answer
    case "$answer" in [SsYy]) return 0;; [Dd]) show_plan_details;; ''|[Nn]) return 1;; *) printf 'Use s, n ou d.\n';; esac
  done
}
