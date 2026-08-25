#!/usr/bin/env bash
bluetooth_plan() { if [[ ${HARDWARE[bluetooth]:-} == detectado ]]; then plan_bluetooth_driver; else PLAN_NOTES+=("[SKIP] Bluetooth não detectado."); fi; }
