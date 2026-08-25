#!/usr/bin/env bash
detect_bluetooth() {
  HARDWARE[bluetooth]='não detectado'; HARDWARE[bluetooth_hardware]=false; HARDWARE[bluetooth_software]=false
  cmd bluetoothctl && HARDWARE[bluetooth_software]=true || true
  if { cmd lsusb && lsusb | grep -qi bluetooth; } || { cmd lspci && lspci | grep -qi bluetooth; } || find /sys/class/bluetooth -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
    HARDWARE[bluetooth]=detectado; HARDWARE[bluetooth_hardware]=true
  fi
}
