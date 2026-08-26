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
  PLAN_PACKAGES=(); PLAN_OPTIONAL_PACKAGES=(); PLAN_SERVICES_ENABLE=(); PLAN_SERVICES_CONFIGURED=(); PLAN_NOTES=(); PLAN_FILES=()
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
  local current=${HARDWARE[display_manager]:-none} planned
  local -a retained=()
  [[ $current != none ]] || return 0
  for planned in "${PLAN_SERVICES_ENABLE[@]}"; do
    case "$planned" in gdm.service|sddm.service|lightdm.service)
      if [[ $planned != "$current" ]]; then
        PLAN_NOTES+=("Display manager atual: $current. $planned não será habilitado automaticamente; mantenha-o ou escolha uma troca explicitamente em uma extensão futura.")
        continue
      fi
      ;;
    esac
    retained+=("$planned")
  done
  PLAN_SERVICES_ENABLE=("${retained[@]}")
}
show_plan() {
  cat <<EOF

================= PLANO DE INSTALAÇÃO =================
Desktop: ${DESKTOP:-minimal}    Hardware profile: ${HARDWARE_PROFILE:-auto}    Usage profile: ${USAGE_PROFILE:-minimal}
Pacotes:
EOF
  printf '  Já instalados:\n'; ((${#PLAN_PACKAGES_INSTALLED[@]})) && printf '    = %s\n' "${PLAN_PACKAGES_INSTALLED[@]}" || printf '    (nenhum)\n'
  printf '  Disponíveis para instalação:\n'; ((${#PLAN_PACKAGES_AVAILABLE[@]})) && printf '    + %s\n' "${PLAN_PACKAGES_AVAILABLE[@]}" || printf '    (nenhum)\n'
  printf '  Indisponíveis:\n'; ((${#PLAN_PACKAGES_UNAVAILABLE[@]})) && printf '    ! %s\n' "${PLAN_PACKAGES_UNAVAILABLE[@]}" || printf '    (nenhum)\n'
  printf '  Opcionais ignorados:\n'; ((${#PLAN_PACKAGES_OPTIONAL_SKIPPED[@]})) && printf '    - %s\n' "${PLAN_PACKAGES_OPTIONAL_SKIPPED[@]}" || printf '    (nenhum)\n'
  printf 'Serviços a habilitar:\n'; ((${#PLAN_SERVICES_ENABLE[@]})) && printf '  + %s\n' "${PLAN_SERVICES_ENABLE[@]}" || printf '  (nenhum)\n'
  printf 'Serviços já configurados:\n'; ((${#PLAN_SERVICES_CONFIGURED[@]})) && printf '  = %s\n' "${PLAN_SERVICES_CONFIGURED[@]}" || printf '  (nenhum)\n'
  printf 'Não será instalado:\n  - Drivers para GPUs não detectadas\n  - Bibliotecas 32-bit, exceto no perfil gaming\n'
  printf 'Garantias:\n'; printf '  - %s\n' "${PLAN_NOTES[@]}"
}
select_interactively_if_needed() {
  local answer
  if (( ! HARDWARE_PROFILE_EXPLICIT )) && [[ -t 0 ]]; then
    printf 'Hardware profile detectado: %s. Usar este perfil? [Y/n] ' "$HARDWARE_PROFILE_DETECTED"; read -r answer
    if [[ $answer =~ ^[Nn]$ ]]; then printf 'Hardware profile [desktop/notebook/server/vm]: '; read -r HARDWARE_PROFILE; else HARDWARE_PROFILE=$HARDWARE_PROFILE_DETECTED; fi
  fi
  [[ $HARDWARE_PROFILE =~ ^(auto|desktop|notebook|server|vm)$ ]] || die "Hardware profile inválido: $HARDWARE_PROFILE"
  resolve_hardware_profile
  if [[ -z $USAGE_PROFILE && -t 0 ]]; then printf 'Usage profile [minimal/desktop/gaming/development/server] (desktop): '; read -r USAGE_PROFILE; USAGE_PROFILE=${USAGE_PROFILE:-desktop}; fi
  [[ ${USAGE_PROFILE:-minimal} =~ ^(minimal|desktop|gaming|development|server)$ ]] || die "Usage profile inválido: $USAGE_PROFILE"
  USAGE_PROFILE=${USAGE_PROFILE:-minimal}; PROFILE=$USAGE_PROFILE
  if [[ -z $DESKTOP && $USAGE_PROFILE != minimal && $USAGE_PROFILE != server && -t 0 ]]; then printf 'Desktop [gnome/kde/xfce/cinnamon/hyprland/minimal] (minimal): '; read -r DESKTOP; DESKTOP=${DESKTOP:-minimal}; fi
  DESKTOP=${DESKTOP:-minimal}
  [[ $DESKTOP =~ ^(gnome|kde|xfce|cinnamon|hyprland|minimal)$ ]] || die "Desktop inválido: $DESKTOP"
}
confirm_plan() { (( ASSUME_YES )) && return 0; local answer; read -r -p 'Continuar? [y/N] ' answer; [[ $answer =~ ^[Yy]$ ]]; }
