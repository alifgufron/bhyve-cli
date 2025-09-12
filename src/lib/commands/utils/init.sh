#!/usr/local/bin/bash

# === Subcommand: init ===
cmd_init() {
    GLOBAL_LOG_FILE="/var/log/bhyve-cli.log"
    touch "$GLOBAL_LOG_FILE" || { echo_message "[ERROR] Could not create log file at $GLOBAL_LOG_FILE. Please check permissions."; exit 1; }

    if [ -f "$MAIN_CONFIG_FILE" ]; then
        read -rp "Configuration file already exists. Overwrite? (y/n): " choice
        if [[ "$choice" != "y" ]]; then
            exit 0
        fi
    fi

    display_and_log "INFO" "Initializing bhyve-cli..."

    mkdir -p "$CONFIG_DIR"

    # Copy rc.d script
    

    

    # Prompt for ISO directory
    read -rp "Enter the full path for storing ISO images [/var/bhyve/iso]: " iso_path_input
    local USER_ISO_DIR=${iso_path_input:-/var/bhyve/iso}
    mkdir -p "$USER_ISO_DIR" || { display_and_log "ERROR" "Failed to create ISO directory '$USER_ISO_DIR'."; exit 1; }

    # Create symlink for ISO directory if not default
    local DEFAULT_ISO_DIR="$CONFIG_DIR/.iso"
    if [ "$USER_ISO_DIR" != "$DEFAULT_ISO_DIR" ]; then
        if [ -d "$DEFAULT_ISO_DIR" ] && [ "$(find "$DEFAULT_ISO_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]; then
            display_and_log "ERROR" "Default ISO directory '$DEFAULT_ISO_DIR' is not empty. Please move its contents manually or choose the default path."
            exit 1
        fi
        display_and_log "INFO" "Removing default ISO directory '$DEFAULT_ISO_DIR' and creating symlink."
        rmdir "$DEFAULT_ISO_DIR" 2>/dev/null # Remove if empty
        ln -s "$USER_ISO_DIR" "$DEFAULT_ISO_DIR" || { display_and_log "ERROR" "Failed to create symlink for ISO directory."; exit 1; }
        ISO_DIR="$DEFAULT_ISO_DIR"
    else
        display_and_log "INFO" "Using default ISO directory: $DEFAULT_ISO_DIR"
        mkdir -p "$DEFAULT_ISO_DIR"
        ISO_DIR="$DEFAULT_ISO_DIR"
    fi

    # Prompt for VM config and disk directory
    read -rp "Enter the full path for storing VM configurations and disks [/var/bhyve/vm.d]: " vm_path_input
    local USER_VM_CONFIG_BASE_DIR=${vm_path_input:-/var/bhyve/vm.d}
    mkdir -p "$USER_VM_CONFIG_BASE_DIR" || { display_and_log "ERROR" "Failed to create VM config base directory '$USER_VM_CONFIG_BASE_DIR'."; exit 1; }

    # Create symlink for VM config directory if not default
    local DEFAULT_VM_CONFIG_BASE_DIR="$CONFIG_DIR/vm.d"
    if [ "$USER_VM_CONFIG_BASE_DIR" != "$DEFAULT_VM_CONFIG_BASE_DIR" ]; then
        if [ -d "$DEFAULT_VM_CONFIG_BASE_DIR" ] && [ "$(find "$DEFAULT_VM_CONFIG_BASE_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]; then
            display_and_log "ERROR" "Default VM config directory '$DEFAULT_VM_CONFIG_BASE_DIR' is not empty. Please move its contents manually or choose the default path."
            exit 1
        fi
        display_and_log "INFO" "Removing default VM config directory '$DEFAULT_VM_CONFIG_BASE_DIR' and creating symlink."
        rmdir "$DEFAULT_VM_CONFIG_BASE_DIR" 2>/dev/null # Remove if empty
        ln -s "$USER_VM_CONFIG_BASE_DIR" "$DEFAULT_VM_CONFIG_BASE_DIR" || { display_and_log "ERROR" "Failed to create symlink for vm.d."; exit 1; }
        VM_CONFIG_BASE_DIR="$DEFAULT_VM_CONFIG_BASE_DIR"
    else
        display_and_log "INFO" "Using default VM config base directory: $DEFAULT_VM_CONFIG_BASE_DIR"
        mkdir -p "$DEFAULT_VM_CONFIG_BASE_DIR"
        VM_CONFIG_BASE_DIR="$DEFAULT_VM_CONFIG_BASE_DIR"
    fi

    # Create templates directory inside the chosen VM config base directory
    mkdir -p "$VM_CONFIG_BASE_DIR/templates" || { display_and_log "ERROR" "Failed to create templates directory."; exit 1; }
    display_and_log "INFO" "Templates directory created at: $VM_CONFIG_BASE_DIR/templates"

    UEFI_FIRMWARE_PATH="$CONFIG_DIR/firmware"
    display_and_log "INFO" "UEFI firmware path set to: $UEFI_FIRMWARE_PATH"

    echo "ISO_DIR="$ISO_DIR"" > "$MAIN_CONFIG_FILE"
    echo "UEFI_FIRMWARE_PATH="$UEFI_FIRMWARE_PATH"" >> "$MAIN_CONFIG_FILE"
    echo "GLOBAL_LOG_FILE="$GLOBAL_LOG_FILE"" >> "$MAIN_CONFIG_FILE"
    echo "VM_CONFIG_BASE_DIR="$VM_CONFIG_BASE_DIR"" >> "$MAIN_CONFIG_FILE"

    display_and_log "INFO" "bhyve-cli initialized."
    display_and_log "INFO" "Configuration file created at: $MAIN_CONFIG_FILE"
    echo_message "bhyve-cli initialized successfully."
    echo_message "Configuration file created at: $MAIN_CONFIG_FILE"
}
