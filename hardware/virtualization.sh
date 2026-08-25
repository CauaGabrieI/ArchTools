#!/usr/bin/env bash
detect_virtualization() { local v=none; cmd systemd-detect-virt && v=$(systemd-detect-virt 2>/dev/null || true); [[ $v != none && -n $v ]] && HARDWARE[machine]=VM; HARDWARE[virtualization]=$v; }
