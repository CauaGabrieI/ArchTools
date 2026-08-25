#!/usr/bin/env bash
plan_amd_driver() { plan_package mesa; plan_package vulkan-radeon; plan_package libva-mesa-driver; if [[ $PROFILE == gaming ]]; then plan_package lib32-mesa; plan_package lib32-vulkan-radeon; fi; }
