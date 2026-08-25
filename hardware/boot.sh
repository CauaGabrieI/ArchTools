#!/usr/bin/env bash
detect_boot() { [[ -d /sys/firmware/efi ]] && HARDWARE[boot]=UEFI || HARDWARE[boot]=BIOS/Legacy; }
