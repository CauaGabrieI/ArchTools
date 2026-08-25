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
profile_packages() { "profile_$1"; }
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
  local desktop=$1 profile=$2
  PLAN_PACKAGES=(); PLAN_OPTIONAL_PACKAGES=(); PLAN_SERVICES_ENABLE=(); PLAN_SERVICES_CONFIGURED=(); PLAN_NOTES=(); PLAN_FILES=()
  profile_packages "$profile"; driver_packages; network_plan; audio_plan; bluetooth_plan
  if [[ $profile != minimal && $desktop != minimal ]]; then desktop_plan "$desktop"; fi
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
Desktop: ${DESKTOP:-minimal}    Perfil: ${PROFILE:-minimal}
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
  if [[ -z $DESKTOP && -t 0 ]]; then printf 'Desktop [gnome/kde/xfce/cinnamon/hyprland/minimal] (minimal): '; read -r DESKTOP; DESKTOP=${DESKTOP:-minimal}; fi
  if [[ -z $PROFILE && -t 0 ]]; then printf 'Perfil [minimal/desktop/gaming] (desktop): '; read -r PROFILE; PROFILE=${PROFILE:-desktop}; fi
  DESKTOP=${DESKTOP:-minimal}; PROFILE=${PROFILE:-minimal}
}
confirm_plan() { (( ASSUME_YES )) && return 0; local answer; read -r -p 'Continuar? [y/N] ' answer; [[ $answer =~ ^[Yy]$ ]]; }
