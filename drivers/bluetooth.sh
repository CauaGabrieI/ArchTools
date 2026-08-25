#!/usr/bin/env bash
plan_bluetooth_driver() { plan_package bluez; plan_package bluez-utils; add_service bluetooth.service; }
