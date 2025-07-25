#!/usr/local/bin/bash

# === Prerequisite Checks ===
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo_message "ERROR This script must be run with superuser (root) privileges."
    exit 1
  fi
}

check_kld() {
  if ! kldstat -q -m "$1"; then
    display_and_log "ERROR" "Kernel module '$1.ko' is not loaded. Please run 'kldload $1'."
    exit 1
  fi
}
