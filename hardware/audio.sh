#!/usr/bin/env bash
detect_audio() { if systemctl --user is-active pipewire >/dev/null 2>&1; then HARDWARE[audio]=PipeWire; elif cmd pulseaudio; then HARDWARE[audio]=PulseAudio; else HARDWARE[audio]=ALSA/unknown; fi; }
