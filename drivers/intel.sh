#!/usr/bin/env bash
plan_intel_driver() { plan_package mesa; plan_package vulkan-intel; plan_package intel-media-driver; if [[ $PROFILE == gaming ]]; then plan_package lib32-mesa; plan_package lib32-vulkan-intel; fi; }
