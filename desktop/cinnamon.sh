#!/usr/bin/env bash
desktop_cinnamon() { for p in cinnamon lightdm lightdm-gtk-greeter; do plan_package "$p"; done; add_service lightdm.service; }
