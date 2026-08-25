#!/usr/bin/env bash
detect_network() { HARDWARE[network]=$(ip -br link 2>/dev/null | awk '$1!="lo" {printf "%s ",$1}' || true); [[ -n ${HARDWARE[network]} ]] || HARDWARE[network]=nenhuma; }
