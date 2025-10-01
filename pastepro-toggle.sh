#!/bin/bash
# PastePro toggle script for Hyprland
# Sends SIGUSR1 signal to toggle the overlay

pkill -SIGUSR1 -f "pastepro" || true
