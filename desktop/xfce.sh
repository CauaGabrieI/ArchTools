#!/usr/bin/env bash
desktop_xfce() { for p in xfce4-session xfce4-panel xfdesktop thunar xfce4-settings xfwm4 xfce4-terminal tumbler lightdm lightdm-gtk-greeter; do plan_package "$p"; done; add_service lightdm.service; }
