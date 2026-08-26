#!/usr/bin/env bash
usage_profile_desktop() { usage_profile_minimal; for p in pipewire pipewire-audio pipewire-pulse wireplumber; do plan_package "$p"; done; }
