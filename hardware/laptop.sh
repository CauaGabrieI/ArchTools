#!/usr/bin/env bash
detect_machine() { if [[ -d /sys/class/power_supply ]] && find /sys/class/power_supply -maxdepth 1 -name 'BAT*' | grep -q .; then HARDWARE[machine]=LAPTOP; else HARDWARE[machine]=DESKTOP; fi; }
