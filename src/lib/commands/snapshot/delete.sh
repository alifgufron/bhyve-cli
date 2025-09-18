#!/usr/local/bin/bash

# === Subcommand: snapshot delete ===
cmd_snapshot_delete() {
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

  # --- Logic for all VMs (bhyve-cli and vm-bhyve) ---
  local SNAPSHOT_ROOT_DIR="$datastore_path/snapshots" # Snapshot storage within VM's datastore
  local SNAPSHOT_PATH="$SNAPSHOT_ROOT_DIR/$VMNAME/$SNAPSHOT_NAME"

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
  log "Attempting to delete snapshot directory: $SNAPSHOT_PATH"
  start_spinner "Deleting snapshot files..."
  if ! rm -rf "$SNAPSHOT_PATH"; then
    stop_spinner
    display_and_log "ERROR" "Failed to delete snapshot files. Manual cleanup may be required."
    exit 1
  fi
  stop_spinner
  log "Snapshot directory deleted: $SNAPSHOT_PATH"
  display_and_log "INFO" "Snapshot '$SNAPSHOT_NAME' deleted successfully."
}