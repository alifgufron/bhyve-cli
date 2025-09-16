#!/usr/local/bin/bash

# === Subcommand: create ===
cmd_create() {
  local VMNAME=""
  local DISKSIZE=""
  local VM_BRIDGE=""
  local BOOTLOADER_TYPE="bhyveload" # Default bootloader
  local FROM_TEMPLATE="" # New variable for template name
  local DATASTORE_NAME="default" # Default datastore

  # Parse named arguments
  while (( "$#" )); do
    case "$1" in
      --name)
        shift
        VMNAME="$1"
        ;;
      --datastore)
        shift
        DATASTORE_NAME="$1"
        ;;
      --disk-size)
        shift
        DISKSIZE="$1"
        ;;
      --switch)
        shift
        VM_BRIDGE="$1"
        ;;
      --bootloader)
        shift
        BOOTLOADER_TYPE="$1"
        ;;
      --from-template)
        shift
        FROM_TEMPLATE="$1"
        ;;
      --vnc-port)
        shift
        local VNC_PORT="$1"
        ;;
      --vnc-wait)
        local VNC_WAIT="true"
        ;;
      * )
        display_and_log "ERROR" "Invalid option: $1"
        cmd_create_usage
        exit 1
        ;;
    esac
    shift
  done

  # Validate required arguments
  if [ -z "$VMNAME" ] || [ -z "$VM_BRIDGE" ]; then
    cmd_create_usage
    exit 1
  fi

  if [ -z "$FROM_TEMPLATE" ] && [ -z "$DISKSIZE" ]; then
    display_and_log "ERROR" "--disk-size is required unless --from-template is used."
    cmd_create_usage
    exit 1
  fi

  # Get the absolute path for the selected datastore
  local VM_BASE_PATH
  VM_BASE_PATH=$(get_datastore_path "$DATASTORE_NAME")
  if [ -z "$VM_BASE_PATH" ]; then
    display_and_log "ERROR" "Datastore '$DATASTORE_NAME' not found. Please check 'datastore list'."
    exit 1
  fi

  VM_DIR="$VM_BASE_PATH/$VMNAME"
  CONF="$VM_DIR/vm.conf"

  if [ -d "$VM_DIR" ]; then
    display_and_log "ERROR" "VM '$VMNAME' already exists in datastore '$DATASTORE_NAME'."
    exit 1
  fi

  log "Attempting to create VM directory: $VM_DIR"
  mkdir -p "$VM_DIR" || { display_and_log "ERROR" "Failed to create VM directory '$VM_DIR'. Please check permissions or path."; exit 1; }
  LOG_FILE="$VM_DIR/vm.log" # Set LOG_FILE for create command
  log "VM directory '$VM_DIR' created successfully."

  display_and_log "INFO" "Preparing to create VM '$VMNAME' in datastore '$DATASTORE_NAME'."

  if [ -n "$FROM_TEMPLATE" ]; then
    local TEMPLATE_DIR="$VM_BASE_PATH/templates/$FROM_TEMPLATE"
    if [ ! -d "$TEMPLATE_DIR" ]; then
      display_and_log "ERROR" "Template '$FROM_TEMPLATE' not found in datastore '$DATASTORE_NAME'."
      rmdir "$VM_DIR" # Clean up empty VM directory
      exit 1
    fi
    display_and_log "INFO" "Creating VM from template '$FROM_TEMPLATE' நான."
    start_spinner "Copying template files..."
    cp -R "$TEMPLATE_DIR/." "$VM_DIR/" || {
      stop_spinner
      display_and_log "ERROR" "Failed to copy template files."
      rm -rf "$VM_DIR"
      exit 1
    }
    stop_spinner
    log "Template files copied successfully."

    # Load template config to get disk info
    source "$CONF"

    # Ensure DISKSIZE is set from template if not explicitly provided
    if [ -z "$DISKSIZE" ] && [ -n "$DISK" ]; then
      local TEMPLATE_DISK_PATH="$VM_DIR/$DISK"
      if [ -f "$TEMPLATE_DISK_PATH" ]; then
        DISKSIZE=$(stat -f %z "$TEMPLATE_DISK_PATH" | awk '{print int($1 / (1024*1024*1024))}')
        log "DISKSIZE set from template disk.img to ${DISKSIZE}GB."
      fi
    fi

    # Clean up template-specific variables from the new VM's vm.conf
    sed -i '' "/^VMNAME=/d" "$CONF"
    sed -i '' "/^UUID=/d" "$CONF"
    sed -i '' "/^CONSOLE=/d" "$CONF"
    sed -i '' "/^LOG=/d" "$CONF"
    sed -i '' "/^VNC_PORT=/d" "$CONF"
    sed -i '' "/^VNC_WAIT=/d" "$CONF"
    sed -i '' "/^AUTOSTART=/d" "$CONF"
    # BOOTLOADER_TYPE is kept from template unless overridden by --bootloader

  else
    display_and_log "INFO" "Preparing to create VM '$VMNAME' with disk size ${DISKSIZE}GB and connecting to bridge '$VM_BRIDGE'."

    # === Create disk image ===
    log "Attempting to create disk image: $VM_DIR/disk.img with size ${DISKSIZE}GB..."
    local TRUNCATE_CMD="truncate -s \"${DISKSIZE}G\" \"$VM_DIR/disk.img\""
    log "Executing: $TRUNCATE_CMD"
    truncate -s "${DISKSIZE}G" "$VM_DIR/disk.img" || { display_and_log "ERROR" "Failed to create disk image at '$VM_DIR/disk.img'. Command: '$TRUNCATE_CMD'"; exit 1; }
    log "Disk image '$VM_DIR/disk.img' (${DISKSIZE}GB) created successfully."
  fi

  # === Check and create bridge interface if it doesn't exist ===
  if ! ifconfig "$VM_BRIDGE" > /dev/null 2>&1; then
    log "Bridge interface '$VM_BRIDGE' does not exist. Attempting to create..."
    local CREATE_BRIDGE_CMD="ifconfig bridge create name \"$VM_BRIDGE\""
    log "Executing: $CREATE_BRIDGE_CMD"
    ifconfig bridge create name "$VM_BRIDGE" || { display_and_log "ERROR" "Failed to create bridge '$VM_BRIDGE'. Command: '$CREATE_BRIDGE_CMD'"; exit 1; }
    log "Bridge interface '$VM_BRIDGE' successfully created."
  else
    log "Bridge interface '$VM_BRIDGE' already exists. Skipping creation."
  fi

  # === Generate unique UUID ===
  UUID=$(uuidgen)
  log "Generated unique UUID for VM: $UUID"

  # === Generate unique MAC address (static prefix, random suffix) ===
  MAC_0="58:9c:fc$(jot -r -w ":%02x" -s "" 3 0 255)"
  log "Generated MAC address for NIC0: $MAC_0"

  # === Safely detect next available TAP & create TAP ===
  local NEXT_TAP_NUM=$(get_next_available_tap_num)
  TAP_0="tap${NEXT_TAP_NUM}"
  log "Assigning next available TAP interface: $TAP_0"

  # === Create and configure TAP interface ===
  if ! create_and_configure_tap_interface "$TAP_0" "$MAC_0" "$VM_BRIDGE" "$VMNAME" 0; then
    exit 1
  fi

  # === Generate unique console name ===
  CONSOLE="nmdm-${VMNAME}.1"
  log "Console device assigned: $CONSOLE"

  # === Create configuration file ===
  log "Attempting to create VM configuration file: $CONF"

  if [ -n "$FROM_TEMPLATE" ]; then
    # For template-based creation, modify the copied vm.conf
    # Update VM-specific details while preserving template's disk/NIC configs
    # Ensure VMNAME is set correctly (delete existing, then append new)
    sed -i '' "/^VMNAME=/d" "$CONF"
    echo "VMNAME=$VMNAME" >> "$CONF"

    # Ensure UUID is set correctly (delete existing, then append new)
    sed -i '' "/^UUID=/d" "$CONF"
    echo "UUID=$UUID" >> "$CONF"

    # Ensure CONSOLE is set correctly (delete existing, then append new)
    sed -i '' "/^CONSOLE=/d" "$CONF"
    echo "CONSOLE=$CONSOLE" >> "$CONF"
    sed -i '' "s|^LOG=.*|LOG=$LOG_FILE|" "$CONF"
    # Ensure DISKSIZE is updated if it was derived from template
    sed -i '' "s/^DISKSIZE=.*/DISKSIZE=$DISKSIZE/" "$CONF"

    # Regenerate TAP and MAC addresses for all network interfaces from template
    local NIC_IDX=0
    while true; do
      local CURRENT_TAP_VAR="TAP_${NIC_IDX}"
      local CURRENT_MAC_VAR="MAC_${NIC_IDX}"
      local CURRENT_BRIDGE_VAR="BRIDGE_${NIC_IDX}" # Keep bridge as is

      # Check if the variable exists in the sourced config
      if compgen -v "$CURRENT_TAP_VAR" > /dev/null; then
        local NEW_TAP_NUM=$(get_next_available_tap_num)
        local NEW_TAP_NAME="tap${NEW_TAP_NUM}"
        local NEW_MAC_ADDR="58:9c:fc$(jot -r -w ":%02x" -s "" 3 0 255)"

        log "Regenerating network config for NIC${NIC_IDX}: Old TAP=${!CURRENT_TAP_VAR}, New TAP=${NEW_TAP_NAME}; Old MAC=${!CURRENT_MAC_VAR}, New MAC=${NEW_MAC_ADDR}"

        sed -i '' "s/^TAP_${NIC_IDX}=.*/TAP_${NIC_IDX}=${NEW_TAP_NAME}/" "$CONF"
        sed -i '' "s/^MAC_${NIC_IDX}=.*/MAC_${NIC_IDX}=${NEW_MAC_ADDR}/" "$CONF"

        # If it's the first NIC (NIC_0), also update BRIDGE_0 if --switch was provided
        if [ "$NIC_IDX" -eq 0 ] && [ -n "$VM_BRIDGE" ]; then
          sed -i '' "s/^BRIDGE_0=.*/BRIDGE_0=$VM_BRIDGE/" "$CONF"
        fi

        NIC_IDX=$((NIC_IDX + 1))
      else
        break # No more TAP_X variables found
      fi
    done

    # Remove any remaining VM-specific variables that should not be in the new VM's config
    sed -i '' "/^VNC_PORT=/d" "$CONF"
    sed -i '' "/^VNC_WAIT=/d" "$CONF"

    # Ensure AUTOSTART is set (default to no if not present in template)
    if ! grep -q "^AUTOSTART=" "$CONF"; then
      echo "AUTOSTART=no" >> "$CONF"
    fi

    # Add VNC configuration if provided
    if [ -n "$VNC_PORT" ]; then
      echo "VNC_PORT=$VNC_PORT" >> "$CONF"
      if [ -n "$VNC_WAIT" ]; then
        echo "VNC_WAIT=yes" >> "$CONF"
      fi
    fi

  else
    # For non-template creation, create vm.conf from scratch
    cat > "$CONF" <<EOF
VMNAME=$VMNAME
UUID=$UUID
CPUS=2
MEMORY=2048M
TAP_0=$TAP_0
MAC_0=$MAC_0
BRIDGE_0=$VM_BRIDGE
DISK=disk.img
DISKSIZE=$DISKSIZE
CONSOLE=$CONSOLE
LOG=$LOG_FILE
AUTOSTART=no
BOOTLOADER_TYPE=$BOOTLOADER_TYPE
EOF
    # Add VNC configuration if provided
    if [ -n "$VNC_PORT" ]; then
      echo "VNC_PORT=$VNC_PORT" >> "$CONF"
      if [ -n "$VNC_WAIT" ]; then
        echo "VNC_WAIT=yes" >> "$CONF"
      fi
    fi
  fi

  log "Configuration file created: $CONF"
  display_and_log "INFO" "VM '$VMNAME' successfully created."
  if [ -n "$FROM_TEMPLATE" ]; then
    echo_message "\nPlease continue by running: $(basename "$0") start $VMNAME"
  else
    echo_message "\nPlease continue by running: $(basename "$0") install $VMNAME"
  fi
}