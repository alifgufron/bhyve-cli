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
  log "Entering cmd_console function for VM: $1"
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
  log "Exiting cmd_console function for VM: $VMNAME"
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

  echo_message "VM Information for: $VMNAME"
  echo_message "---------------------------------"
  echo_message "UUID:         $UUID"
  echo_message "CPUs:         $CPUS"
  echo_message "Memory:       $MEMORY"
  echo_message "Bootloader:   $BOOTLOADER_TYPE"
  echo_message "Console:      /dev/${CONSOLE}B"
  echo_message "Log File:     $LOG_FILE"
  echo_message "Autostart:    $AUTOSTART"

  local NIC_IDX=0
  while true; do
    local CURRENT_TAP_VAR="TAP_${NIC_IDX}"
    local CURRENT_MAC_VAR="MAC_${NIC_IDX}"
    local CURRENT_BRIDGE_VAR="BRIDGE_${NIC_IDX}"

    local CURRENT_TAP="${!CURRENT_TAP_VAR}"
    local CURRENT_MAC="${!CURRENT_MAC_VAR}"
    local CURRENT_BRIDGE="${!CURRENT_BRIDGE_VAR}"

    if [ -z "$CURRENT_TAP" ]; then
      break
    fi

    echo_message "NIC $NIC_IDX:"
    echo_message "  TAP Device: $CURRENT_TAP"
    echo_message "  MAC Address: $CURRENT_MAC"
    echo_message "  Bridge:     $CURRENT_BRIDGE"
    NIC_IDX=$((NIC_IDX + 1))
  done

  local DISK_IDX=0
  while true; do
    local CURRENT_DISK_VAR="DISK"
    if [ "$DISK_IDX" -gt 0 ]; then
      CURRENT_DISK_VAR="DISK_${DISK_IDX}"
    fi
    local CURRENT_DISK_FILENAME="${!CURRENT_DISK_VAR}"

    if [ -z "$CURRENT_DISK_FILENAME" ]; then
      break
    fi

    echo_message "Disk $DISK_IDX:"
    echo_message "  Image:      $VM_DIR/$CURRENT_DISK_FILENAME"
    echo_message "  Size:       $(stat -f %z "$VM_DIR/$CURRENT_DISK_FILENAME" | numfmt --to=iec-i --suffix=B)"
    DISK_IDX=$((DISK_IDX + 1))
  done

  if is_vm_running "$VMNAME"; then
    echo_message "Status:       Running (PID: $(get_vm_pid "$VMNAME"))"
  else
    echo_message "Status:       Stopped"
  fi
  echo_message "---------------------------------"
}

# === Subcommand: modify ===
cmd_modify() {
  if [ -z "$1" ]; then
    cmd_modify_usage
    exit 1
  fi

  VMNAME="$1"
  shift

  load_vm_config "$VMNAME"

  while (( "$#" )); do
    case "$1" in
      --cpu)
        sed -i '' "s/^CPUS=.*/CPUS=$2/" "$CONF_FILE"
        display_and_log "INFO" "Set CPU count to $2 for VM '$VMNAME'."
        shift 2
        ;;
      --ram)
        sed -i '' "s/^MEMORY=.*/MEMORY=$2/" "$CONF_FILE"
        display_and_log "INFO" "Set RAM to $2 for VM '$VMNAME'."
        shift 2
        ;;
      --add-nic)
        local NEW_BRIDGE="$2"
        local NEXT_NIC_IDX=$(grep -c '^TAP_' "$CONF_FILE")
        local NEXT_TAP_NUM=$(get_next_available_tap_num)
        local NEW_TAP="tap${NEXT_TAP_NUM}"
        local NEW_MAC="58:9c:fc$(jot -r -w ":%02x" -s "" 3 0 255)"
        echo "TAP_${NEXT_NIC_IDX}=${NEW_TAP}" >> "$CONF_FILE"
        echo "MAC_${NEXT_NIC_IDX}=${NEW_MAC}" >> "$CONF_FILE"
        echo "BRIDGE_${NEXT_NIC_IDX}=${NEW_BRIDGE}" >> "$CONF_FILE"
        display_and_log "INFO" "Added NIC ${NEXT_NIC_IDX} (TAP: ${NEW_TAP}, Bridge: ${NEW_BRIDGE}) to VM '$VMNAME'."
        shift 2
        ;;
      *)
        display_and_log "ERROR" "Invalid option for modify: $1"
        cmd_modify_usage
        exit 1
        ;;
    esac
  done
}

# === Subcommand: clone ===
cmd_clone() {
  if [ -z "$2" ]; then
    cmd_clone_usage
    exit 1
  fi

  local SOURCE_VMNAME="$1"
  local NEW_VMNAME="$2"

  load_vm_config "$SOURCE_VMNAME"

  start_spinner "Cloning VM '$SOURCE_VMNAME' to '$NEW_VMNAME'..."

  local SOURCE_VM_DIR="$VM_CONFIG_BASE_DIR/$SOURCE_VMNAME"
  local NEW_VM_DIR="$VM_CONFIG_BASE_DIR/$NEW_VMNAME"

  mkdir -p "$NEW_VM_DIR"

  cp "$SOURCE_VM_DIR/vm.conf" "$NEW_VM_DIR/vm.conf"
  cp "$SOURCE_VM_DIR/disk.img" "$NEW_VM_DIR/disk.img"

  sed -i '' "s/^VMNAME=.*/VMNAME=$NEW_VMNAME/" "$NEW_VM_DIR/vm.conf"
  sed -i '' "s/^UUID=.*/UUID=$(uuidgen)/" "$NEW_VM_DIR/vm.conf"

  local NIC_IDX=0
  while true; do
    local CURRENT_TAP_VAR="TAP_${NIC_IDX}"
    local CURRENT_MAC_VAR="MAC_${NIC_IDX}"

    local CURRENT_TAP="${!CURRENT_TAP_VAR}"

    if [ -z "$CURRENT_TAP" ]; then
      break
    fi

    local NEW_MAC="58:9c:fc$(jot -r -w ":%02x" -s "" 3 0 255)"
    sed -i '' "s/^${CURRENT_MAC_VAR}=.*/${CURRENT_MAC_VAR}=${NEW_MAC}/" "$NEW_VM_DIR/vm.conf"
    NIC_IDX=$((NIC_IDX + 1))
  done

  stop_spinner
  display_and_log "INFO" "VM '$SOURCE_VMNAME' cloned to '$NEW_VMNAME' successfully."
}

# === Subcommand: resize-disk ===
cmd_resize_disk() {
  if [ -z "$2" ]; then
    cmd_resize_disk_usage
    exit 1
  fi

  local VMNAME="$1"
  local NEW_SIZE_GB="$2"

  load_vm_config "$VMNAME"

  local DISK_PATH="$VM_DIR/disk.img"

  truncate -s "${NEW_SIZE_GB}G" "$DISK_PATH"
  sed -i '' "s/^DISKSIZE=.*/DISKSIZE=${NEW_SIZE_GB}G/" "$CONF_FILE"

  display_and_log "INFO" "Disk for VM '$VMNAME' resized to ${NEW_SIZE_GB}GB."
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
  log "Entering cmd_list function."

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
  log "Exiting cmd_list function."
}

# === Subcommand: status ===
cmd_status() {
  log "Entering cmd_status function."

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
        UPTIME=$(echo "$STATS" | awk '{print $3}')
      fi
      
      printf "%-20s %-10s %-15s %-10s %-10s %-12s\n" "$VMNAME" "$STATUS" "$PID" "$CPU_USAGE" "$MEM_USAGE" "$UPTIME"
    fi
  done
  echo_message "------------------------------------------------------------------------------------"
  log "Exiting cmd_status function."
}
