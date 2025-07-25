#!/usr/local/bin/bash

# === Function to load main configuration ===
load_config() {
  if [ -f "$MAIN_CONFIG_FILE" ]; then
      # shellcheck disable=SC1090
    . "$MAIN_CONFIG_FILE"
  fi
  # Set default log file if not set in config
  GLOBAL_LOG_FILE="${GLOBAL_LOG_FILE:-/var/log/bhyve-cli.log}"
  VM_CONFIG_BASE_DIR="${VM_CONFIG_BASE_DIR:-$CONFIG_DIR/vm.d}" # Ensure default if not in config
}

# === Function to check if the script has been initialized ===
check_initialization() {
  if [ "$1" != "init" ] && [ ! -f "$MAIN_CONFIG_FILE" ]; then
    echo_message "
[ERROR] bhyve-cli has not been initialized."
    echo_message "Please run the command '$0 init' to generate the required configuration files."
    exit 1
  fi
}


# === Function to load VM configuration ===
load_vm_config() {
  VMNAME="$1"
  VM_DIR="$VM_CONFIG_BASE_DIR/$VMNAME"
  CONF_FILE="$VM_DIR/vm.conf"

  if [ ! -f "$CONF_FILE" ]; then
    display_and_log "ERROR" "VM configuration '$VMNAME' not found: $CONF_FILE"
    exit 1
  fi
    # shellcheck disable=SC1090
  . "$CONF_FILE"
  LOG_FILE="$VM_DIR/vm.log" # Set LOG_FILE after loading config
  BOOTLOADER_TYPE="${BOOTLOADER_TYPE:-bhyveload}" # Default to bhyveload if not set
}
