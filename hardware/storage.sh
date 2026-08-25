#!/usr/bin/env bash
detect_storage() {
  HARDWARE[storage_detection]=complete; HARDWARE[storage_summary]=''; HARDWARE[trim]=0
  if cmd lsblk; then
    HARDWARE[storage_summary]=$(LC_ALL=C lsblk -dn -o NAME,TYPE,TRAN,ROTA,MODEL 2>/dev/null | awk '
      $2 == "rom" { printf "%s (ROM, %s); ", $1, $5; next }
      $2 == "loop" || $2 == "zram" || $2 == "lvm" || $2 == "dm" { next }
      $2 == "disk" { media=(($3 == "nvme" || $1 ~ /^nvme/) ? "NVMe" : ($4 == "1" ? "HDD" : "SSD")); printf "%s (%s, %s); ", $1, media, $5 }
    ' | sed 's/; $//' || true)
    if LC_ALL=C lsblk -dn -o TYPE,ROTA 2>/dev/null | awk '$1=="disk" && $2=="0" {found=1} END {exit !found}'; then HARDWARE[trim]=1; fi
  else
    HARDWARE[storage_detection]=limited; warn 'lsblk not available; storage detection is limited'
  fi
  HARDWARE[root_device]=$(findmnt -no SOURCE / 2>/dev/null || true); HARDWARE[root_fs]=$(findmnt -no FSTYPE / 2>/dev/null || true)
}
