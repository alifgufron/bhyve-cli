#!/usr/local/bin/bash

# === Subcommand: resize-disk ===
cmd_resize_disk() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    cmd_resize_disk_usage
    exit 1
  fi

  VMNAME="$1"
  NEW_SIZE_GB="$2"
  load_vm_config "$VMNAME"

  local DISK_PATH="$VM_DIR/$DISK"

  # === Check if VM is running ===
  if is_vm_running "$VMNAME"; then
    display_and_log "ERROR" "VM '$VMNAME' is currently running. Please stop the VM before resizing its disk."
    exit 1
  fi

  if [ ! -f "$DISK_PATH" ]; then
    display_and_log "ERROR" "Disk image for VM '$VMNAME' not found: $DISK_PATH"
    exit 1
  fi

  # === Get current disk size in GB ===
  CURRENT_SIZE_BYTES=$(stat -f %z "$DISK_PATH")
  CURRENT_SIZE_GB=$((CURRENT_SIZE_BYTES / 1024 / 1024 / 1024))

  if (( NEW_SIZE_GB <= CURRENT_SIZE_GB )); then
    display_and_log "ERROR" "New size ($NEW_SIZE_GB GB) must be greater than current size ($CURRENT_SIZE_GB GB)."
    exit 1
  fi

  log "Resizing disk for VM '$VMNAME' from ${CURRENT_SIZE_GB}GB to ${NEW_SIZE_GB}GB..."
  truncate -s "${NEW_SIZE_GB}G" "$DISK_PATH"
  if [ $? -ne 0 ]; then
    display_and_log "ERROR" "Failed to resize disk image."
    exit 1
  fi
  # === Update DISKSIZE in vm.conf ===
  sed -i '' "s/^DISKSIZE=.*/DISKSIZE=${NEW_SIZE_GB}/" "$CONF_FILE"
  log "Disk resized successfully and vm.conf updated."
  display_and_log "INFO" "Disk for VM '$VMNAME' has been resized to ${NEW_SIZE_GB}GB."
  display_and_log "INFO" "Note: You may need to extend the partition inside the VM operating system."
}
