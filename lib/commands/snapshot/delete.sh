#!/usr/local/bin/bash

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
