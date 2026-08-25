#!/usr/bin/env bash
plan_nvidia_driver() {
  # Do not select a legacy branch by vendor alone. pacman availability is rechecked before execution.
  plan_package nvidia-utils; if [[ $PROFILE == gaming ]]; then plan_package lib32-nvidia-utils; fi
  PLAN_NOTES+=("NVIDIA detectada: confirme compatibilidade do pacote 'nvidia' com o kernel atual antes de instalar o módulo; este projeto não força um driver de kernel automaticamente.")
}
