#!/usr/bin/env bash
detect_memory() { HARDWARE[ram_total]=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}') || true; HARDWARE[ram_available]=$(free -h 2>/dev/null | awk '/^Mem:/ {print $7}') || true; }
