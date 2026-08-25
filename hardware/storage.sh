#!/usr/bin/env bash
detect_storage() {
  HARDWARE[storage_detection]=complete; HARDWARE[storage_summary]=''; HARDWARE[trim]=0
  if cmd lsblk; then
    HARDWARE[storage_summary]=$(lsblk -dno TRAN,ROTA,MODEL 2>/dev/null | sed '/^$/d' | paste -sd '; ' - || true)
    if lsblk -dno ROTA 2>/dev/null | grep -qx '0'; then HARDWARE[trim]=1; fi
  else
    HARDWARE[storage_detection]=limited; warn 'lsblk not available; storage detection is limited'
  fi
  HARDWARE[root_device]=$(findmnt -no SOURCE / 2>/dev/null || true); HARDWARE[root_fs]=$(findmnt -no FSTYPE / 2>/dev/null || true)
}
