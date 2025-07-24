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

# === Subcommand: console ===
cmd_console() {
  
  if [ -z "$1" ]; then
    cmd_console_usage
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  if ! is_vm_running "$VMNAME"; then
    display_and_log "ERROR" "VM '$VMNAME' is not running."
    exit 1
  fi

  echo_message ">>> Connecting to console for VM '$VMNAME'. Type ~. to exit."
  cu -l /dev/"${CONSOLE}B" -s 115200
  
}

# === Subcommand: logs ===
cmd_logs() {
  if [ -z "$1" ]; then
    cmd_logs_usage
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  if [ ! -f "$LOG_FILE" ]; then
    display_and_log "ERROR" "Log file for VM '$VMNAME' not found."
    exit 1
  fi

  tail -f "$LOG_FILE"
}

# === Subcommand: autostart ===
cmd_autostart() {
  if [ -z "$2" ]; then
    cmd_autostart_usage
    exit 1
  fi

  VMNAME="$1"
  ACTION="$2"
  CONF_FILE="$VM_CONFIG_BASE_DIR/$VMNAME/vm.conf"

  if [ ! -f "$CONF_FILE" ]; then
    display_and_log "ERROR" "VM configuration '$VMNAME' not found."
    exit 1
  fi

  case "$ACTION" in
    enable)
      sed -i '' 's/^AUTOSTART=.*/AUTOSTART=yes/' "$CONF_FILE"
      display_and_log "INFO" "Autostart enabled for VM '$VMNAME'."
      ;;
    disable)
      sed -i '' 's/^AUTOSTART=.*/AUTOSTART=no/' "$CONF_FILE"
      display_and_log "INFO" "Autostart disabled for VM '$VMNAME'."
      ;;
    *)
      cmd_autostart_usage
      exit 1
      ;;
  esac
}

# === Subcommand: info ===
cmd_info() {
  if [ -z "$1" ]; then
    cmd_info_usage
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  local STATUS_STR="Stopped"
  if is_vm_running "$VMNAME"; then
    local PID=$(get_vm_pid "$VMNAME")
    STATUS_STR="Running [$PID]"
  fi

  echo_message "----------------------------------------"
  echo_message "VM Information for '$VMNAME':"
  echo_message "----------------------------------------"
  printf "%-15s : %s\n" "Name" "$VMNAME"
  printf "%-15s : %s\n" "Status" "$STATUS_STR"
  printf "%-15s : %s\n" "CPUs" "$CPUS"
  printf "%-15s : %s\n" "Memory" "$MEMORY"
  printf "%-15s : %s\n" "Bootloader" "$BOOTLOADER_TYPE"
  printf "%-15s : %s\n" "Autostart" "$AUTOSTART"
  printf "%-15s : %s\n" "Console" "/dev/${CONSOLE}B"
  printf "%-15s : %s\n" "Log File" "$LOG_FILE"

  local NIC_IDX=0
  while true; do
    local CURRENT_TAP_VAR="TAP_${NIC_IDX}"
    local CURRENT_MAC_VAR="MAC_${NIC_IDX}"
    local CURRENT_BRIDGE_VAR="BRIDGE_${NIC_IDX}"
    local CURRENT_NIC_TYPE_VAR="NIC_${NIC_IDX}_TYPE"

    local CURRENT_TAP="${!CURRENT_TAP_VAR}"
    local CURRENT_MAC="${!CURRENT_MAC_VAR}"
    local CURRENT_BRIDGE="${!CURRENT_BRIDGE_VAR}"
    local CURRENT_NIC_TYPE="${!CURRENT_NIC_TYPE_VAR}"

    if [ -z "$CURRENT_TAP" ]; then
      break
    fi

    echo_message "Interface ${NIC_IDX} :"
    printf "    %-10s: %s\n" "TAP" "$CURRENT_TAP"
    printf "    %-10s: %s\n" "MAC" "$CURRENT_MAC"
    printf "    %-10s: %s\n" "Bridge" "$CURRENT_BRIDGE"
    printf "    %-10s: %s\n" "Type" "${CURRENT_NIC_TYPE:-virtio-net}"
    NIC_IDX=$((NIC_IDX + 1))
  done

  local DISK_IDX=0
  while true; do
    local CURRENT_DISK_VAR="DISK"
    if [ "$DISK_IDX" -gt 0 ]; then
      CURRENT_DISK_VAR="DISK_${DISK_IDX}"
    fi
    local CURRENT_DISK_FILENAME="${!CURRENT_DISK_VAR}"
    local CURRENT_DISK_TYPE_VAR="DISK_${DISK_IDX}_TYPE"
    local DISK_TYPE="${!CURRENT_DISK_TYPE_VAR:-virtio-blk}"

    if [ -z "$CURRENT_DISK_FILENAME" ]; then
      break
    fi
    
    local DISK_PATH="$VM_DIR/$CURRENT_DISK_FILENAME"

    echo_message "Disk :"
    printf "    %-10s: %s\n" "Path" "$DISK_PATH"
    
    local DISK_SIZE_BYTES=$(stat -f %z "$DISK_PATH")
    local DISK_SIZE_HUMAN=$(format_bytes "$DISK_SIZE_BYTES")
    printf "    %-10s: %s\n" "Set" "$DISK_SIZE_HUMAN"

    local ACTUAL_DISK_USAGE_KILOBYTES=$(du -k "$DISK_PATH" 2>/dev/null | awk '{print $1}')
    local ACTUAL_DISK_USAGE_BYTES=$((ACTUAL_DISK_USAGE_KILOBYTES * 1024))
    local ACTUAL_DISK_USAGE_HUMAN=$(format_bytes "$ACTUAL_DISK_USAGE_BYTES")
    printf "    %-10s: %s\n" "Used" "$ACTUAL_DISK_USAGE_HUMAN"
    printf "    %-10s: %s\n" "Type" "$DISK_TYPE"
    DISK_IDX=$((DISK_IDX + 1))
  done
  echo_message "----------------------------------------"
}


# === Subcommand: export ===
cmd_export() {
  if [ -z "$2" ]; then
    cmd_export_usage
    exit 1
  fi

  local VMNAME="$1"
  local DEST_PATH="$2"

  load_vm_config "$VMNAME"

  start_spinner "Exporting VM '$VMNAME' to '$DEST_PATH'..."

  tar -czf "$DEST_PATH" -C "$VM_CONFIG_BASE_DIR" "$VMNAME"

  stop_spinner
  display_and_log "INFO" "VM '$VMNAME' exported successfully to '$DEST_PATH'."
}

# === Subcommand: import ===
cmd_import() {
  if [ -z "$1" ]; then
    cmd_import_usage
    exit 1
  fi

  local ARCHIVE_PATH="$1"

  start_spinner "Importing VM from '$ARCHIVE_PATH'..."

  tar -xzf "$ARCHIVE_PATH" -C "$VM_CONFIG_BASE_DIR"

  stop_spinner
  display_and_log "INFO" "VM imported successfully."
}

# === Subcommand: list ===
cmd_list() {
  

  if [ ! -d "$VM_CONFIG_BASE_DIR" ] || [ -z "$(ls -A "$VM_CONFIG_BASE_DIR")" ]; then
    display_and_log "INFO" "No virtual machines configured."
    exit 0
  fi

  printf "%-20s %-38s %-12s %-10s %-8s %-10s\n" "VM NAME" "UUID" "BOOTLOADER" "AUTOSTART" "CPUS" "MEMORY"
  echo_message "-----------------------------------------------------------------------------------------------------------"

  for VM_DIR_PATH in "$VM_CONFIG_BASE_DIR"/*/; do
    if [ -d "$VM_DIR_PATH" ]; then
      local VMNAME=$(basename "$VM_DIR_PATH")
      local CONF_FILE="$VM_DIR_PATH/vm.conf"
      
      if [ -f "$CONF_FILE" ]; then
        # Source the config in a subshell to avoid polluting the main script's scope
        (
          . "$CONF_FILE"
          printf "%-20s %-38s %-12s %-10s %-8s %-10s\n" \
            "$VMNAME" \
            "${UUID:-N/A}" \
            "${BOOTLOADER_TYPE:-bhyveload}" \
            "${AUTOSTART:-no}" \
            "${CPUS:-N/A}" \
            "${MEMORY:-N/A}"
        )
      fi
    fi
  done
  echo_message "-----------------------------------------------------------------------------------------------------------"
  
}

# === Subcommand: status ===
cmd_status() {
  

  # Check if the VM directory exists and is not empty
  if [ ! -d "$VM_CONFIG_BASE_DIR" ] || [ -z "$(ls -A "$VM_CONFIG_BASE_DIR")" ]; then
    display_and_log "INFO" "No virtual machines configured."
    exit 0
  fi

  echo_message "------------------------------------------------------------------------------------"
  printf "%-20s %-10s %-15s %-10s %-10s %-12s\n" "VM NAME" "STATUS" "PID" "CPU%" "MEM%" "UPTIME"
  echo_message "------------------------------------------------------------------------------------"

  for VM_DIR_PATH in "$VM_CONFIG_BASE_DIR"/*/; do
    if [ -d "$VM_DIR_PATH" ]; then
      local VMNAME=$(basename "$VM_DIR_PATH")
      local STATUS="stopped"
      local PID="-"
      local CPU_USAGE="-"
      local MEM_USAGE="-"
      local UPTIME="-"
      
      if is_vm_running "$VMNAME"; then
        STATUS="running"
        PID=$(get_vm_pid "$VMNAME")
        # Get stats using ps
        STATS=$(ps -o %cpu,%mem,etime -p "$PID" | tail -n 1)
        CPU_USAGE=$(echo "$STATS" | awk '{print $1}')
        MEM_USAGE=$(echo "$STATS" | awk '{print $2}')
        
        # Format uptime
        local ETIME=$(echo "$STATS" | awk '{print $3}')
        UPTIME=$(format_etime "$ETIME")
      fi
      
      printf "%-20s %-10s %-15s %-10s %-10s %-12s\n" "$VMNAME" "$STATUS" "$PID" "$CPU_USAGE" "$MEM_USAGE" "$UPTIME"
    fi
  done
  echo_message "------------------------------------------------------------------------------------"
  
}

# === Subcommand: vnc ===
cmd_vnc() {
  
  if [ -z "$1" ]; then
    cmd_vnc_usage
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  if [ -z "$VNC_PORT" ]; then
    display_and_log "ERROR" "VNC is not configured for VM '$VMNAME'. Please use 'create --vnc-port <port>' or 'modify --vnc-port <port>'."
    exit 1
  fi

  if ! is_vm_running "$VMNAME"; then
    display_and_log "ERROR" "VM '$VMNAME' is not running. Please start the VM first."
    exit 1
  fi

  echo_message "Connecting to VNC console for VM '$VMNAME'."
  echo_message "Please ensure you have a VNC client installed (e.g., \`vncviewer\`)."
  echo_message "You can connect to: localhost:$VNC_PORT"

  # Attempt to launch vncviewer if available
  if command -v vncviewer >/dev/null 2>&1; then
    display_and_log "INFO" "Launching vncviewer..."
    vncviewer "localhost::$VNC_PORT" &
  else
    display_and_log "WARNING" "vncviewer not found. Please connect manually to localhost:$VNC_PORT with your VNC client."
  fi
  
}

# === Subcommand: snapshot ===
cmd_snapshot() {
  if [ -z "$1" ]; then
    cmd_snapshot_usage
    exit 1
  fi

  local SUBCOMMAND="$1"
  shift

  case "$SUBCOMMAND" in
    create)
      cmd_snapshot_create "$@"
      ;;
    list)
      cmd_snapshot_list "$@"
      ;;
    revert)
      cmd_snapshot_revert "$@"
      ;;
    delete)
      cmd_snapshot_delete "$@"
      ;;
    --help|help)
      cmd_snapshot_usage
      ;;
    *)
      display_and_log "ERROR" "Invalid subcommand for 'snapshot': $SUBCOMMAND"
      cmd_snapshot_usage
      exit 1
      ;;
  esac
}

# === Subcommand: snapshot create ===
cmd_snapshot_create() {
  if [ -z "$2" ]; then
    cmd_snapshot_usage
    exit 1
  fi

  local VMNAME="$1"
  local SNAPSHOT_NAME="$2"
  load_vm_config "$VMNAME"

  local VM_DISK_PATH="$VM_DIR/$DISK"
  local SNAPSHOT_DIR="$VM_DIR/snapshots"
  local SNAPSHOT_PATH="$SNAPSHOT_DIR/$SNAPSHOT_NAME"

  mkdir -p "$SNAPSHOT_DIR" || { display_and_log "ERROR" "Failed to create snapshot directory '$SNAPSHOT_DIR'."; exit 1; }

  if [ -d "$SNAPSHOT_PATH" ]; then
    display_and_log "ERROR" "Snapshot '$SNAPSHOT_NAME' already exists for VM '$VMNAME'."
    exit 1
  fi

  mkdir -p "$SNAPSHOT_PATH" || { display_and_log "ERROR" "Failed to create snapshot directory '$SNAPSHOT_PATH'."; exit 1; }

  display_and_log "INFO" "Creating snapshot '$SNAPSHOT_NAME' for VM '$VMNAME'..."

  if is_vm_running "$VMNAME"; then
    display_and_log "INFO" "VM '$VMNAME' is running. Pausing VM for consistent snapshot..."
    if ! $BHYVECTL --vm="$VMNAME" --pause; then
      display_and_log "ERROR" "Failed to pause VM '$VMNAME'. Aborting snapshot."
      exit 1
    fi
    log "VM '$VMNAME' paused."
  fi

  start_spinner "Copying disk image for snapshot..."
  if ! cp "$VM_DISK_PATH" "$SNAPSHOT_PATH/disk.img"; then
    stop_spinner
    display_and_log "ERROR" "Failed to copy disk image for snapshot. Aborting."
    if is_vm_running "$VMNAME"; then
      $BHYVECTL --vm="$VMNAME" --resume
      log "VM '$VMNAME' resumed after snapshot failure."
    fi
    exit 1
  fi
  stop_spinner
  log "Disk image copied."

  # Copy vm.conf for consistency
  cp "$VM_DIR/vm.conf" "$SNAPSHOT_PATH/vm.conf"
  log "VM configuration copied."

  if is_vm_running "$VMNAME"; then
    display_and_log "INFO" "Resuming VM '$VMNAME' ..."
    if ! $BHYVECTL --vm="$VMNAME" --resume; then
      display_and_log "ERROR" "Failed to resume VM '$VMNAME'. Manual intervention may be required."
      exit 1
    fi
    log "VM '$VMNAME' resumed."
  fi

  display_and_log "INFO" "Snapshot '$SNAPSHOT_NAME' created successfully for VM '$VMNAME'."
}

# === Subcommand: snapshot list ===
cmd_snapshot_list() {
  if [ -z "$1" ]; then
    cmd_snapshot_usage
    exit 1
  fi

  local VMNAME="$1"
  local SNAPSHOT_DIR="$VM_CONFIG_BASE_DIR/$VMNAME/snapshots"

  if [ ! -d "$SNAPSHOT_DIR" ] || [ -z "$(ls -A "$SNAPSHOT_DIR")" ]; then
    display_and_log "INFO" "No snapshots found for VM '$VMNAME'."
    exit 0
  fi

  echo_message "Snapshots for VM '$VMNAME':"
  echo_message "---------------------------------"
  local count=0
  for SNAPSHOT_PATH in "$SNAPSHOT_DIR"/*/; do
    if [ -d "$SNAPSHOT_PATH" ]; then
      local SNAPSHOT_NAME=$(basename "$SNAPSHOT_PATH")
      echo_message "- $SNAPSHOT_NAME"
      count=$((count + 1))
    fi
  done

  if [ "$count" -eq 0 ]; then
    display_and_log "INFO" "No snapshots found for VM '$VMNAME'."
  fi
  echo_message "---------------------------------"
}

# === Subcommand: snapshot revert ===
cmd_snapshot_revert() {
  if [ -z "$2" ]; then
    cmd_snapshot_usage
    exit 1
  fi

  local VMNAME="$1"
  local SNAPSHOT_NAME="$2"
  load_vm_config "$VMNAME"

  local VM_DISK_PATH="$VM_DIR/$DISK"
  local SNAPSHOT_PATH="$VM_DIR/snapshots/$SNAPSHOT_NAME"

  if ! is_vm_running "$VMNAME"; then
    display_and_log "INFO" "VM '$VMNAME' is not running. Proceeding with revert."
  else
    display_and_log "ERROR" "VM '$VMNAME' is running. Please stop the VM before reverting to a snapshot."
    exit 1
  fi

  if [ ! -d "$SNAPSHOT_PATH" ]; then
    display_and_log "ERROR" "Snapshot '$SNAPSHOT_NAME' not found for VM '$VMNAME'."
    exit 1
  fi

  display_and_log "INFO" "Reverting VM '$VMNAME' to snapshot '$SNAPSHOT_NAME'..."
  start_spinner "Copying snapshot disk image..."
  if ! cp "$SNAPSHOT_PATH/disk.img" "$VM_DISK_PATH"; then
    stop_spinner
    display_and_log "ERROR" "Failed to revert disk image from snapshot. Aborting."
    exit 1
  fi
  stop_spinner
  log "Disk image reverted."

  # Revert vm.conf as well
  cp "$SNAPSHOT_PATH/vm.conf" "$VM_DIR/vm.conf"
  log "VM configuration reverted."

  display_and_log "INFO" "VM '$VMNAME' successfully reverted to snapshot '$SNAPSHOT_NAME'."
}

# === Subcommand: snapshot delete ===
cmd_snapshot_delete() {
  if [ -z "$2" ]; then
    cmd_snapshot_usage
    exit 1
  fi

  local VMNAME="$1"
  local SNAPSHOT_NAME="$2"
  load_vm_config "$VMNAME"

  local SNAPSHOT_PATH="$VM_DIR/snapshots/$SNAPSHOT_NAME"

  if [ ! -d "$SNAPSHOT_PATH" ]; then
    display_and_log "ERROR" "Snapshot '$SNAPSHOT_NAME' not found for VM '$VMNAME'."
    exit 1
  fi

  read -rp "Are you sure you want to delete snapshot '$SNAPSHOT_NAME' for VM '$VMNAME'? (y/n): " CONFIRM_DELETE
  if ! [[ "$CONFIRM_DELETE" =~ ^[Yy]$ ]]; then
    echo_message "Snapshot deletion cancelled."
    exit 0
  fi

  display_and_log "INFO" "Deleting snapshot '$SNAPSHOT_NAME' for VM '$VMNAME'..."
  start_spinner "Deleting snapshot files..."
  if ! rm -rf "$SNAPSHOT_PATH"; then
    stop_spinner
    display_and_log "ERROR" "Failed to delete snapshot files. Manual cleanup may be required."
    exit 1
  fi
  stop_spinner
  display_and_log "INFO" "Template '$TEMPLATE_NAME' deleted successfully."
}

# === Subcommand: template ===
cmd_template() {
  if [ -z "$1" ]; then
    cmd_template_usage
    exit 1
  fi

  local SUBCOMMAND="$1"
  shift

  case "$SUBCOMMAND" in
    create)
      cmd_template_create "$@"
      ;;
    list)
      cmd_template_list "$@"
      ;;
    delete)
      cmd_template_delete "$@"
      ;;
    --help|help)
      cmd_template_usage
      ;;
    *)
      display_and_log "ERROR" "Invalid subcommand for 'template': $SUBCOMMAND"
      cmd_template_usage
      exit 1
      ;;
  esac
}

# === Subcommand: template create ===
cmd_template_create() {
  if [ -z "$2" ]; then
    cmd_template_usage
    exit 1
  fi

  local SOURCE_VMNAME="$1"
  local TEMPLATE_NAME="$2"

  local SOURCE_VM_DIR="$VM_CONFIG_BASE_DIR/$SOURCE_VMNAME"
  local TEMPLATE_BASE_DIR="$VM_CONFIG_BASE_DIR/templates"
  local NEW_TEMPLATE_DIR="$TEMPLATE_BASE_DIR/$TEMPLATE_NAME"

  if [ ! -d "$SOURCE_VM_DIR" ]; then
    display_and_log "ERROR" "Source VM '$SOURCE_VMNAME' not found."
    exit 1
  fi

  if [ -d "$NEW_TEMPLATE_DIR" ]; then
    display_and_log "ERROR" "Template '$TEMPLATE_NAME' already exists."
    exit 1
  fi

  mkdir -p "$NEW_TEMPLATE_DIR" || { display_and_log "ERROR" "Failed to create template directory '$NEW_TEMPLATE_DIR'."; exit 1; }

  display_and_log "INFO" "Creating template '$TEMPLATE_NAME' from VM '$SOURCE_VMNAME'..."
  start_spinner "Copying VM files to template..."

  # Copy vm.conf and disk image
  cp "$SOURCE_VM_DIR/vm.conf" "$NEW_TEMPLATE_DIR/vm.conf" || {
    stop_spinner
    display_and_log "ERROR" "Failed to copy vm.conf to template."
    rm -rf "$NEW_TEMPLATE_DIR"
    exit 1
  }
  cp "$SOURCE_VM_DIR/disk.img" "$NEW_TEMPLATE_DIR/disk.img" || {
    stop_spinner
    display_and_log "ERROR" "Failed to copy disk image to template."
    rm -rf "$NEW_TEMPLATE_DIR"
    exit 1
  }
  stop_spinner

  # Clean up VM-specific settings in the template's vm.conf
  sed -i '' "/^VMNAME=/d" "$NEW_TEMPLATE_DIR/vm.conf"
  sed -i '' "/^UUID=/d" "$NEW_TEMPLATE_DIR/vm.conf"
  sed -i '' "/^TAP_[0-9]=/d" "$NEW_TEMPLATE_DIR/vm.conf"
  sed -i '' "/^MAC_[0-9]=/d" "$NEW_TEMPLATE_DIR/vm.conf"
  sed -i '' "/^BRIDGE_[0-9]=/d" "$NEW_TEMPLATE_DIR/vm.conf"
  sed -i '' "/^CONSOLE=/d" "$NEW_TEMPLATE_DIR/vm.conf"
  sed -i '' "/^LOG=/d" "$NEW_TEMPLATE_DIR/vm.conf"
  sed -i '' "/^VNC_PORT=/d" "$NEW_TEMPLATE_DIR/vm.conf"
  sed -i '' "/^VNC_WAIT=/d" "$NEW_TEMPLATE_DIR/vm.conf"

  display_and_log "INFO" "Template '$TEMPLATE_NAME' created successfully."
  display_and_log "INFO" "You can now create new VMs from this template using: $0 create --name <new_vm> --from-template $TEMPLATE_NAME --switch <bridge>"
}

# === Subcommand: template list ===
cmd_template_list() {
  local TEMPLATE_BASE_DIR="$VM_CONFIG_BASE_DIR/templates"

  if [ ! -d "$TEMPLATE_BASE_DIR" ] || [ -z "$(ls -A "$TEMPLATE_BASE_DIR")" ]; then
    display_and_log "INFO" "No VM templates found."
    exit 0
  fi

  echo_message "Available VM Templates:"
  echo_message "---------------------------------"
  local count=0
  for TEMPLATE_PATH in "$TEMPLATE_BASE_DIR"/*/; do
    if [ -d "$TEMPLATE_PATH" ]; then
      local TEMPLATE_NAME=$(basename "$TEMPLATE_PATH")
      echo_message "- $TEMPLATE_NAME"
      count=$((count + 1))
    fi
  done

  if [ "$count" -eq 0 ]; then
    display_and_log "INFO" "No VM templates found."
  fi
  echo_message "---------------------------------"
}

# === Subcommand: template delete ===
cmd_template_delete() {
  if [ -z "$1" ]; then
    cmd_template_usage
    exit 1
  fi

  local TEMPLATE_NAME="$1"
  local TEMPLATE_PATH="$VM_CONFIG_BASE_DIR/templates/$TEMPLATE_NAME"

  if [ ! -d "$TEMPLATE_PATH" ]; then
    display_and_log "ERROR" "Template '$TEMPLATE_NAME' not found."
    exit 1
  fi

  read -rp "Are you sure you want to delete template '$TEMPLATE_NAME'? (y/n): " CONFIRM_DELETE
  if ! [[ "$CONFIRM_DELETE" =~ ^[Yy]$ ]]; then
    echo_message "Template deletion cancelled."
    exit 0
  fi

  display_and_log "INFO" "Deleting template '$TEMPLATE_NAME' ..."
  start_spinner "Deleting template files..."
  if ! rm -rf "$TEMPLATE_PATH"; then
    stop_spinner
    display_and_log "ERROR" "Failed to delete template files. Manual cleanup may be required."
    exit 1
  fi
  stop_spinner
  display_and_log "INFO" "Template '$TEMPLATE_NAME' deleted successfully."
}

# === Subcommand: verify ===
cmd_verify() {
  
  display_and_log "INFO" "Starting VM configuration verification..."

  local VERIFY_STATUS="SUCCESS"
  local VM_COUNT=0
  local ERROR_COUNT=0

  if [ ! -d "$VM_CONFIG_BASE_DIR" ] || [ -z "$(ls -A "$VM_CONFIG_BASE_DIR")" ]; then
    display_and_log "INFO" "No virtual machines configured to verify."
    exit 0
  fi

  for VM_DIR_PATH in "$VM_CONFIG_BASE_DIR"/*/; do
    if [ -d "$VM_DIR_PATH" ]; then
      VM_COUNT=$((VM_COUNT + 1))
      local VMNAME=$(basename "$VM_DIR_PATH")
      local CONF_FILE="$VM_DIR_PATH/vm.conf"
      
      echo_message "\nVerifying VM: $VMNAME"
      echo_message "---------------------------------"

      if [ ! -f "$CONF_FILE" ]; then
        display_and_log "ERROR" "  Configuration file '$CONF_FILE' not found."
        VERIFY_STATUS="FAILED"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        continue
      fi

      # Check for syntax errors by sourcing in a subshell
      if ! (source "$CONF_FILE") > /dev/null 2>&1; then
        display_and_log "ERROR" "  Syntax error in '$CONF_FILE'."
        VERIFY_STATUS="FAILED"
        ERROR_COUNT=$((ERROR_COUNT + 1))
      else
        display_and_log "INFO" "  Configuration file syntax: OK"
      fi

      # Load VM config to check disk paths
      # Temporarily set VM_DIR for this check
      local ORIGINAL_VM_DIR="$VM_DIR"
      VM_DIR="$VM_DIR_PATH"
      
      # Source again to get variables for disk checks
      source "$CONF_FILE"

      local DISK_IDX=0
      while true; do
        local CURRENT_DISK_VAR="DISK"
        if [ "$DISK_IDX" -gt 0 ]; then
          CURRENT_DISK_VAR="DISK_${DISK_IDX}"
        fi
        local CURRENT_DISK_FILENAME="${!CURRENT_DISK_VAR}"

        if [ -z "$CURRENT_DISK_FILENAME" ]; then
          break # No more disks configured
        fi

        local CURRENT_DISK_PATH="$VM_DIR/$CURRENT_DISK_FILENAME"
        if [ ! -f "$CURRENT_DISK_PATH" ]; then
          display_and_log "ERROR" "  Disk image '$CURRENT_DISK_PATH' not found."
          VERIFY_STATUS="FAILED"
          ERROR_COUNT=$((ERROR_COUNT + 1))
        else
          display_and_log "INFO" "  Disk image '$CURRENT_DISK_FILENAME': OK"
        fi
        DISK_IDX=$((DISK_IDX + 1))
      done
      
      # Restore original VM_DIR
      VM_DIR="$ORIGINAL_VM_DIR"
      echo_message "---------------------------------"
    fi
  done

  echo_message "\nVerification Summary:"
  echo_message "---------------------------------"
  echo_message "Total VMs checked: $VM_COUNT"
  echo_message "Errors found: $ERROR_COUNT"
  if [ "$ERROR_COUNT" -eq 0 ]; then
    display_and_log "INFO" "All VM configurations verified successfully."
  else
    display_and_log "ERROR" "Verification completed with errors. Please review the logs above."
  fi
  echo_message "---------------------------------"
  
}