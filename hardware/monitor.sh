#!/usr/bin/env bash
detect_monitors() { if [[ -d /sys/class/drm ]] && cmd find; then HARDWARE[monitors]=$(find /sys/class/drm -maxdepth 1 -name '*-*' -exec sh -c 'test -f "$1/status" && test "$(cat "$1/status")" = connected && basename "$1"' _ {} \; 2>/dev/null | paste -sd ',' || true); else HARDWARE[monitors]=''; warn 'Monitor detection limited: DRM/find unavailable'; fi; }
