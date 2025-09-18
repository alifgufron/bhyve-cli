#!/usr/local/bin/bash

# === Subcommand: resize-disk ===
cmd_resize_disk() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    cmd_resize_disk_usage
    exit 1
  fi

  local VMNAME_ARG="$1" # Use VMNAME_ARG to avoid conflict with global VMNAME
  local NEW_SIZE_GB="$2"

  # Find VM across all datastores
  local found_vm_info
  found_vm_info=$(find_any_vm "$VMNAME_ARG")

  if [ -z "$found_vm_info" ]; then
    display_and_log "ERROR" "VM '$VMNAME_ARG' not found in any bhyve-cli or vm-bhyve datastores."
    exit 1
  fi

  local vm_source
  local datastore_path
  vm_source=$(echo "$found_vm_info" | cut -d':' -f1)
  datastore_path=$(echo "$found_vm_info" | cut -d':' -f3)
  local vm_dir="$datastore_path/$VMNAME_ARG" # Define vm_dir here

  # If it's a vm-bhyve VM, we don't modify it directly
  if [ "$vm_source" == "vm-bhyve" ]; then
    display_and_log "ERROR" "Resizing disks for vm-bhyve VMs is not directly supported by bhyve-cli. Please use vm-bhyve's mechanism."
    exit 1
  fi

  # Load VM config using the found datastore_path. This sets the global VMNAME, VM_DIR, CONF_FILE etc.
  load_vm_config "$VMNAME_ARG" "$vm_dir"

  # Explicitly source the vm.conf file here to ensure variables are available in this script's scope
  # shellcheck disable=SC1090
  . "$CONF_FILE"

  log "DEBUG: resize-disk.sh - DISK_0 after explicit source: $DISK_0"
  local DISK_PATH="$VM_DIR/$DISK_0"

  # === Check if VM is running ===
  if is_vm_running "$VMNAME_ARG" "$vm_dir"; then
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
  # === Update DISK_0_SIZE in vm.conf ===
  # Check if DISK_0_SIZE exists, if so, update it. Otherwise, add it.
  if grep -q "^DISK_0_SIZE=" "$CONF_FILE"; then
    sed -i '' "s/^DISK_0_SIZE=.*/DISK_0_SIZE=${NEW_SIZE_GB}G/" "$CONF_FILE"
  else
    # If DISK_0_SIZE doesn't exist, but DISKSIZE does, update DISKSIZE.
    # Otherwise, add DISK_0_SIZE.
    if grep -q "^DISKSIZE=" "$CONF_FILE"; then
      sed -i '' "s/^DISKSIZE=.*/DISKSIZE=${NEW_SIZE_GB}G/" "$CONF_FILE"
    else
      # Append DISK_0_SIZE if neither exists
      echo "DISK_0_SIZE=${NEW_SIZE_GB}G" >> "$CONF_FILE"
    fi
  fi
  log "Disk resized successfully and vm.conf updated."
  display_and_log "INFO" "Disk for VM '$VMNAME' has been resized to ${NEW_SIZE_GB}GB."
  display_and_log "INFO" "Note: You may need to extend the partition inside the VM operating system."
}
