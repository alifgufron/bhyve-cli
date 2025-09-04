#!/usr/local/bin/bash

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
