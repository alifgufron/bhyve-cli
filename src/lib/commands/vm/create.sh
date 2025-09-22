#!/usr/local/bin/bash

# === Subcommand: create ===
cmd_create() {
  local VMNAME=""
  local DISKSIZE=""
  local VM_BRIDGE=""
  local BOOTLOADER_TYPE="bhyveload" # Default bootloader
  local FROM_TEMPLATE=""
  local DATASTORE_NAME="default"
  local NIC_TYPE="virtio-net" # Default NIC type


  # Parse named arguments
  while (( "$#" )); do
    case "$1" in
      --name) shift; VMNAME="$1" ;;
      --datastore) shift; DATASTORE_NAME="$1" ;;
      --disk-size) shift; DISKSIZE="$1" ;;
      --switch) shift; VM_BRIDGE="$1" ;;
      --bootloader) shift; BOOTLOADER_TYPE="$1" ;;
      --from-template) shift; FROM_TEMPLATE="$1" ;;
      --nic-type) shift; NIC_TYPE="$1" ;;

      * )
        display_and_log "ERROR" "Invalid option: $1"
        cmd_create_usage
        exit 1
        ;;
    esac
    shift
  done

  # Validate required arguments
  if [ -z "$VMNAME" ] || { [ -z "$VM_BRIDGE" ] && [ -z "$FROM_TEMPLATE" ]; }; then
    cmd_create_usage
    exit 1
  fi

  if [ -z "$FROM_TEMPLATE" ] && [ -z "$DISKSIZE" ]; then
    display_and_log "ERROR" "--disk-size is required unless --from-template is used."
    cmd_create_usage
    exit 1
  fi

  local VM_BASE_PATH
  VM_BASE_PATH=$(get_datastore_path "$DATASTORE_NAME")
  if [ -z "$VM_BASE_PATH" ]; then
    display_and_log "ERROR" "Datastore '$DATASTORE_NAME' not found."
    exit 1
  fi

  VM_DIR="$VM_BASE_PATH/$VMNAME"
  CONF="$VM_DIR/vm.conf"
  LOG_FILE="$VM_DIR/vm.log"

  if [ -d "$VM_DIR" ]; then
    display_and_log "ERROR" "VM '$VMNAME' already exists in datastore '$DATASTORE_NAME'."
    exit 1
  fi

  mkdir -p "$VM_DIR" || { display_and_log "ERROR" "Failed to create VM directory '$VM_DIR'."; exit 1; }
  log "VM directory '$VM_DIR' created."
  display_and_log "INFO" "Preparing to create VM '$VMNAME' in datastore '$DATASTORE_NAME'."

  # --- Template-based Creation ---
  if [ -n "$FROM_TEMPLATE" ]; then
    local TEMPLATE_DIR="$VM_BASE_PATH/templates/$FROM_TEMPLATE"
    if [ ! -d "$TEMPLATE_DIR" ]; then
      display_and_log "ERROR" "Template '$FROM_TEMPLATE' not found in datastore '$DATASTORE_NAME'."
      rm -rf "$VM_DIR"
      exit 1
    fi

    display_and_log "INFO" "Creating VM from template '$FROM_TEMPLATE'..."
    start_spinner "Copying template files..."
    cp -R "$TEMPLATE_DIR/." "$VM_DIR/" || {
      stop_spinner
      display_and_log "ERROR" "Failed to copy template files."
      rm -rf "$VM_DIR"
      exit 1
    }
    stop_spinner
    log "Template files copied."

    # Check for zstd availability
    if ! command -v zstd >/dev/null 2>&1; then
      display_and_log "ERROR" "zstd command not found. Please install zstd to decompress template disks."
      rm -rf "$VM_DIR"
      exit 1
    fi

    # Decompress disk images if they are zstd compressed
        log "Template files copied."

    # Load template config to get disk info (needed for decompression loop)
    source "$CONF"

    # Check for zstd availability
    if ! command -v zstd >/dev/null 2>&1; then
      display_and_log "ERROR" "zstd command not found. Please install zstd to decompress template disks."
      rm -rf "$VM_DIR"
      exit 1
    fi

    # Decompress disk images if they are zstd compressed
    local DISK_IDX=0
    while true; do
      local DISK_VAR_NAME="DISK_${DISK_IDX}"
      local DISK_FILENAME="${!DISK_VAR_NAME}"
      if [ -z "$DISK_FILENAME" ]; then break; fi

      local ORIGINAL_DISK_PATH="$VM_DIR/$DISK_FILENAME"

      if [[ "$DISK_FILENAME" == *.zst ]]; then
        local DECOMPRESSED_FILENAME="${DISK_FILENAME%.zst}"
        local DECOMPRESSED_DISK_PATH="$VM_DIR/$DECOMPRESSED_FILENAME"

        log "Decompressing template disk: $ORIGINAL_DISK_PATH to $DECOMPRESSED_DISK_PATH"
        if ! zstd -d "$ORIGINAL_DISK_PATH" -o "$DECOMPRESSED_DISK_PATH"; then
          display_and_log "ERROR" "Failed to decompress template disk '$ORIGINAL_DISK_PATH'. Aborting."
          rm -rf "$VM_DIR"
          exit 1
        fi
        rm "$ORIGINAL_DISK_PATH" # Remove compressed copy
        log "Decompressed '$DECOMPRESSED_DISK_PATH'. Compressed removed."

        # Update vm.conf in the new VM to point to the decompressed file
        sed -i '' "s|${DISK_FILENAME}|${DECOMPRESSED_FILENAME}|" "$CONF"
        log "Updated vm.conf in new VM to reference decompressed file."
      fi
      DISK_IDX=$((DISK_IDX + 1))
    done

    # Clean up template-specific variables (after decompression loop)
    sed -i '' '/^VMNAME=/d' "$CONF"
    sed -i '' '/^UUID=/d' "$CONF"
    sed -i '' '/^CONSOLE=/d' "$CONF"
    sed -i '' '/^LOG=/d' "$CONF"
    sed -i '' '/^AUTOSTART=/d' "$CONF"
    sed -i '' '/^TAP_[0-9]*=/d' "$CONF" # Remove old TAP assignments

    # Regenerate MAC addresses for all NICs from the template
    local NIC_IDX=0
    while grep -q "^BRIDGE_${NIC_IDX}=" "$CONF"; do
      local NEW_MAC_ADDR
      NEW_MAC_ADDR=$(generate_mac_address)
      sed -i '' "/^MAC_${NIC_IDX}=/d" "$CONF" # Remove old MAC
      echo "MAC_${NIC_IDX}=${NEW_MAC_ADDR}" >> "$CONF"
      log "Generated MAC for NIC${NIC_IDX} from template: ${NEW_MAC_ADDR}"
      NIC_IDX=$((NIC_IDX + 1))
    done

    # If --switch is provided, override the bridge for the first NIC
    if [ -n "$VM_BRIDGE" ]; then
        sed -i '' "s/^BRIDGE_0=.*/BRIDGE_0=$VM_BRIDGE/" "$CONF"
        log "Overrode BRIDGE_0 with '$VM_BRIDGE' from command line."
    fi

    # Clean up template-specific variables
    sed -i '' '/^VMNAME=/d' "$CONF"
    sed -i '' '/^UUID=/d' "$CONF"
    sed -i '' '/^CONSOLE=/d' "$CONF"
    sed -i '' '/^LOG=/d' "$CONF"

    sed -i '' '/^AUTOSTART=/d' "$CONF"
    sed -i '' '/^TAP_[0-9]*=/d' "$CONF" # Remove old TAP assignments

    # Load template config to get disk info
    source "$CONF"

    # Regenerate MAC addresses for all NICs from the template
    local NIC_IDX=0
    while grep -q "^BRIDGE_${NIC_IDX}=" "$CONF"; do
      local NEW_MAC_ADDR
      NEW_MAC_ADDR=$(generate_mac_address)
      sed -i '' "/^MAC_${NIC_IDX}=/d" "$CONF" # Remove old MAC
      echo "MAC_${NIC_IDX}=${NEW_MAC_ADDR}" >> "$CONF"
      log "Generated MAC for NIC${NIC_IDX} from template: ${NEW_MAC_ADDR}"
      NIC_IDX=$((NIC_IDX + 1))
    done

    # If --switch is provided, override the bridge for the first NIC
    if [ -n "$VM_BRIDGE" ]; then
        sed -i '' "s/^BRIDGE_0=.*/BRIDGE_0=$VM_BRIDGE/" "$CONF"
        log "Overrode BRIDGE_0 with '$VM_BRIDGE' from command line."
    fi

  # --- Creation from Scratch ---
  else
    display_and_log "INFO" "Creating new VM with ${DISKSIZE}GB disk on switch '$VM_BRIDGE'."
    log "Creating disk image: $VM_DIR/disk.img (${DISKSIZE}GB)..."
    truncate -s "${DISKSIZE}G" "$VM_DIR/disk.img" || { display_and_log "ERROR" "Failed to create disk image."; rm -rf "$VM_DIR"; exit 1; }
    log "Disk image created."

    # Create vm.conf from scratch
    local MAC_0
    MAC_0=$(generate_mac_address)
    log "Generated MAC for NIC0: $MAC_0"

    cat > "$CONF" <<EOF
CPUS=2
MEMORY=2048M
BRIDGE_0=$VM_BRIDGE
NIC_0_TYPE=$NIC_TYPE
MAC_0=$MAC_0
DISK_0=disk.img
DISK_0_TYPE=virtio-blk
DISK_0_SIZE=${DISKSIZE}G
BOOTLOADER_TYPE=$BOOTLOADER_TYPE
EOF
  fi

  # === Finalize Configuration (Common for both methods) ===
  UUID=$(uuidgen)
  CONSOLE="nmdm-${VMNAME}.1"

  {
    echo "VMNAME=$VMNAME"
    echo "UUID=$UUID"
    echo "CONSOLE=$CONSOLE"
    echo "LOG=$LOG_FILE"
    echo "AUTOSTART=no"
  } >> "$CONF"



  log "Configuration file finalized: $CONF"
  display_and_log "INFO" "VM '$VMNAME' successfully created."

  if [ -n "$FROM_TEMPLATE" ]; then
    echo_message "
VM created from template. To start, run: $(basename "$0") vm start $VMNAME"
  else
    echo_message "
VM created. To install an OS, run: $(basename "$0") vm install $VMNAME"
  fi
}
