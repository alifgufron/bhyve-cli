#!/usr/local/bin/bash

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
