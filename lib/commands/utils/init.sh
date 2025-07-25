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
    mkdir -p "$VM_CONFIG_BASE_DIR"

    read -rp "Enter the full path for storing ISO images [/var/bhyve/iso]: " iso_path
    ISO_DIR=${iso_path:-/var/bhyve/iso}
    mkdir -p "$ISO_DIR"
    display_and_log "INFO" "ISO directory set to: $ISO_DIR"

    read -rp "Enter the full path for storing VM configurations and disks [/usr/local/etc/bhyve-cli/vm.d]: " vm_config_path
    local NEW_VM_CONFIG_BASE_DIR=${vm_config_path:-$CONFIG_DIR/vm.d}

    if [ "$NEW_VM_CONFIG_BASE_DIR" != "$CONFIG_DIR/vm.d" ]; then
        if [ -d "$CONFIG_DIR/vm.d" ] && [ "$(find "$CONFIG_DIR/vm.d" -mindepth 1 -print -quit 2>/dev/null)" ]; then
            display_and_log "ERROR" "Default VM config directory '$CONFIG_DIR/vm.d' is not empty. Please move its contents manually or choose the default path."
            exit 1
        fi
        display_and_log "INFO" "Creating VM config base directory: $NEW_VM_CONFIG_BASE_DIR"
        mkdir -p "$NEW_VM_CONFIG_BASE_DIR" || { display_and_log "ERROR" "Failed to create VM config base directory '$NEW_VM_CONFIG_BASE_DIR'."; exit 1; }
        
        display_and_log "INFO" "Removing default VM config directory '$CONFIG_DIR/vm.d' and creating symlink."
        rmdir "$CONFIG_DIR/vm.d" 2>/dev/null # Remove if empty
        ln -s "$NEW_VM_CONFIG_BASE_DIR" "$CONFIG_DIR/vm.d" || { display_and_log "ERROR" "Failed to create symlink for vm.d."; exit 1; }
        VM_CONFIG_BASE_DIR="$NEW_VM_CONFIG_BASE_DIR"
    else
        display_and_log "INFO" "Using default VM config base directory: $CONFIG_DIR/vm.d"
        mkdir -p "$CONFIG_DIR/vm.d"
        VM_CONFIG_BASE_DIR="$CONFIG_DIR/vm.d"
    fi

    UEFI_FIRMWARE_PATH="$CONFIG_DIR/firmware"
    mkdir -p "$UEFI_FIRMWARE_PATH"
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
