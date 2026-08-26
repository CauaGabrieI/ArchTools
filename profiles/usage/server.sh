#!/usr/bin/env bash
usage_profile_server() { usage_profile_minimal; plan_package openssh; PLAN_NOTES+=("sshd não será habilitado automaticamente."); }
