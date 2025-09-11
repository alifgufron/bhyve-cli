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

# Tries to detect the vm-bhyve directory from /etc/rc.conf
# and validates its structure.
#
# Returns:
#   The path to the vm-bhyve directory if found and valid, otherwise empty.
get_vm_bhyve_dir() {
    local vm_dir_line
    local vm_dir_path

    # Check if /etc/rc.conf contains vm_dir
    vm_dir_line=$(grep '^vm_dir=' /etc/rc.conf 2>/dev/null)

    if [ -n "$vm_dir_line" ]; then
        # Extract the path, removing quotes
        vm_dir_path=$(echo "$vm_dir_line" | cut -d'=' -f2 | tr -d '"')

        # Check if the path is a directory and contains a .config subdir
        if [ -d "$vm_dir_path" ] && [ -d "$vm_dir_path/.config" ]; then
            echo "$vm_dir_path"
            return 0
        fi
    fi

    echo ""
    return 1
}
