#!/usr/bin/env bash
audio_plan() { if [[ ${HARDWARE[audio]:-} == PipeWire ]]; then PLAN_NOTES+=("PipeWire já está funcional; nenhuma substituição de pilha de áudio será feita."); fi; }
