#!/usr/bin/env bash
detect_wifi() { HARDWARE[wifi]=0; cmd iw && iw dev 2>/dev/null | grep -q '^Interface' && HARDWARE[wifi]=1 || true; [[ ${HARDWARE[wifi]} == 0 ]] && cmd lspci && lspci | grep -Eqi 'network controller|wireless' && HARDWARE[wifi]=1 || true; }
