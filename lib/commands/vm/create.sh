#!/usr/local/bin/bash

# === Subcommand: create ===
cmd_create() {
  local VMNAME=""
  local DISKSIZE=""
  local VM_BRIDGE=""
  local BOOTLOADER_TYPE="bhyveload" # Default bootloader

  # Parse named arguments
  while (( "$#" )); do
    case "$1" in
      --name)
        shift
        VMNAME="$1"
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
      *)
        display_and_log "ERROR" "Invalid option: $1"
        cmd_create_usage
        exit 1
        ;;
    esac
    shift
  done

  # Validate required arguments
  if [ -z "$VMNAME" ] || [ -z "$DISKSIZE" ] || [ -z "$VM_BRIDGE" ]; then
    cmd_create_usage
    exit 1
  fi

  VM_DIR="$VM_CONFIG_BASE_DIR/$VMNAME"
  CONF="$VM_DIR/vm.conf"

  log "Attempting to create VM directory: $VM_DIR"
  mkdir -p "$VM_DIR" || { display_and_log "ERROR" "Failed to create VM directory '$VM_DIR'. Please check permissions or path."; exit 1; }
  LOG_FILE="$VM_DIR/vm.log" # Set LOG_FILE for create command
  log "VM directory '$VM_DIR' created successfully."

  display_and_log "INFO" "Preparing to create VM '$VMNAME' with disk size ${DISKSIZE}GB and connecting to bridge '$VM_BRIDGE'."

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

  # === Create disk image ===
  log "Attempting to create disk image: $VM_DIR/disk.img with size ${DISKSIZE}GB..."
  local TRUNCATE_CMD="truncate -s \"${DISKSIZE}G\" \"$VM_DIR/disk.img\""
  log "Executing: $TRUNCATE_CMD"
  truncate -s "${DISKSIZE}G" "$VM_DIR/disk.img" || { display_and_log "ERROR" "Failed to create disk image at '$VM_DIR/disk.img'. Command: '$TRUNCATE_CMD'"; exit 1; }
  log "Disk image '$VM_DIR/disk.img' (${DISKSIZE}GB) created successfully."

  # === Generate unique UUID ===
  UUID=$(uuidgen)
  log "Generated unique UUID for VM: $UUID"
  log "VM UUID: $UUID"

  # === Generate unique MAC address (static prefix, random suffix) ===
  MAC_0="58:9c:fc$(jot -r -w ":%02x" -s "" 3 0 255)"
  log "Generated MAC address for NIC0: $MAC_0"
  log "NIC0 MAC Address: $MAC_0"

  # === Safely detect next available TAP & create TAP ===
  local NEXT_TAP_NUM=$(get_next_available_tap_num)
  TAP_0="tap${NEXT_TAP_NUM}"
  log "Assigning next available TAP interface: $TAP_0"
  log "Assigned TAP interface: $TAP_0"

  # === Create and configure TAP interface ===
  if ! create_and_configure_tap_interface "$TAP_0" "$MAC_0" "$VM_BRIDGE" "$VMNAME" 0; then
    exit 1
  fi

  # === Generate unique console name ===
  CONSOLE="nmdm-${VMNAME}.1"
  log "Console device assigned: $CONSOLE"
  log "Assigned console device: $CONSOLE"

  # === Create configuration file ===
  log "Attempting to create VM configuration file: $CONF"
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

  log "Configuration file created: $CONF"
  display_and_log "INFO" "VM '$VMNAME' successfully created."
  echo_message "\nPlease continue by running: $0 install $VMNAME"
}