#!/usr/bin/env bash
desktop_xfce() { for p in xfce4 xfce4-goodies lightdm lightdm-gtk-greeter; do plan_package "$p"; done; add_service lightdm.service; }
