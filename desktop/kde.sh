#!/usr/bin/env bash
desktop_kde() { for p in plasma-desktop sddm xdg-desktop-portal-kde; do plan_package "$p"; done; add_service sddm.service; }
