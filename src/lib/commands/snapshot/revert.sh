#!/usr/local/bin/bash

# === Subcommand: snapshot revert ===
cmd_snapshot_revert() {
  if [ -z "$2" ]; then
    cmd_snapshot_usage
    exit 1
  fi

  local VMNAME="$1"
  local SNAPSHOT_NAME="$2"

  # Use the centralized find_any_vm function to determine the VM source
  local found_vm_info
  found_vm_info=$(find_any_vm "$VMNAME")

  if [ -z "$found_vm_info" ]; then
    display_and_log "ERROR" "VM '$VMNAME' not found in any bhyve-cli or vm-bhyve datastores."
    exit 1
  fi

  local vm_source
  local datastore_path
  vm_source=$(echo "$found_vm_info" | cut -d':' -f1)
  datastore_path=$(echo "$found_vm_info" | cut -d':' -f3)
  local vm_dir="$datastore_path/$VMNAME"

  # --- Logic for all VMs (bhyve-cli and vm-bhyve) ---
  # Correctly check if VM is running using the full vm_dir path
  if is_vm_running "$VMNAME" "$vm_dir"; then
    display_and_log "ERROR" "VM '$VMNAME' is running. Please stop the VM before reverting to a snapshot."
    exit 1
  fi

  local SNAPSHOT_ROOT_DIR="$datastore_path/snapshots" # Snapshot storage within VM's datastore
  local SNAPSHOT_PATH="$SNAPSHOT_ROOT_DIR/$VMNAME/$SNAPSHOT_NAME"
  if [ ! -d "$SNAPSHOT_PATH" ]; then
    display_and_log "ERROR" "Snapshot '$SNAPSHOT_NAME' not found for VM '$VMNAME'."
    exit 1
  fi

  read -rp "This will overwrite the current state of VM '$VMNAME'. Are you sure you want to revert to snapshot '$SNAPSHOT_NAME'? (y/n): " CONFIRM_REVERT
  if ! [[ "$CONFIRM_REVERT" =~ ^[Yy]$ ]]; then
    echo_message "Snapshot revert cancelled."
    exit 0
  fi

  display_and_log "INFO" "Reverting VM '$VMNAME' to snapshot '$SNAPSHOT_NAME'..."
  log "Attempting to revert VM '$VMNAME' from snapshot '$SNAPSHOT_NAME'."
  start_spinner "Copying snapshot files..."

  # Load the bhyve-cli VM config to get disk details
  load_vm_config "$VMNAME" "$vm_dir"

  # --- Revert Disks by copying them from the snapshot directory ---
  local DISK_IDX=0
  while true; do
    local CURRENT_DISK_VAR="DISK_${DISK_IDX}"
    local CURRENT_DISK_FILENAME="${!CURRENT_DISK_VAR}"
    if [ -z "$CURRENT_DISK_FILENAME" ]; then break; fi

    local SNAPSHOT_DISK_PATH="$SNAPSHOT_PATH/$CURRENT_DISK_FILENAME"
    local VM_DISK_PATH="$vm_dir/$CURRENT_DISK_FILENAME"

    # Check if the snapshot disk is compressed
    if [ -f "${SNAPSHOT_DISK_PATH}.zst" ]; then
      log "Decompressing snapshot disk: ${SNAPSHOT_DISK_PATH}.zst to $VM_DISK_PATH"
      if ! zstd -d -f "${SNAPSHOT_DISK_PATH}.zst" -o "$VM_DISK_PATH"; then
        stop_spinner
        display_and_log "ERROR" "Failed to decompress disk image '${CURRENT_DISK_FILENAME}.zst' from snapshot. Aborting."
        exit 1
      fi
    elif [ -f "$SNAPSHOT_DISK_PATH" ]; then
      log "Copying uncompressed snapshot disk: $SNAPSHOT_DISK_PATH to $VM_DISK_PATH"
      if ! cp "$SNAPSHOT_DISK_PATH" "$VM_DISK_PATH"; then
        stop_spinner
        display_and_log "ERROR" "Failed to revert disk image '$CURRENT_DISK_FILENAME' from snapshot. Aborting."
        exit 1
      fi
    else
      log "WARNING: Snapshot disk file '$SNAPSHOT_DISK_PATH' (or .zst) not found, skipping revert for this disk."
    fi
    DISK_IDX=$((DISK_IDX + 1))
  done

  # Revert vm.conf as well
  if [ -f "$SNAPSHOT_PATH/vm.conf" ]; then
    log "Copying vm.conf from snapshot: $SNAPSHOT_PATH/vm.conf to $vm_dir/vm.conf"
    cp "$SNAPSHOT_PATH/vm.conf" "$vm_dir/vm.conf"
    log "VM configuration reverted."
  fi

  stop_spinner
  display_and_log "INFO" "VM '$VMNAME' successfully reverted to snapshot '$SNAPSHOT_NAME'."
}