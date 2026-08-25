#!/usr/bin/env bash
profile_desktop() { profile_minimal; for p in pipewire pipewire-audio pipewire-pulse wireplumber; do plan_package "$p"; done; }
