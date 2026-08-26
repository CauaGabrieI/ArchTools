#!/usr/bin/env bash
desktop_gnome() { for p in gnome-shell gnome-control-center gdm xdg-desktop-portal-gnome; do plan_package "$p"; done; add_service gdm.service; }
