#!/usr/bin/env bash
network_plan() { if [[ ${HARDWARE[network_manager]:-} != active ]]; then add_service NetworkManager.service; fi; }
