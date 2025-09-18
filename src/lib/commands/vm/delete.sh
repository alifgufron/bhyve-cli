#!/usr/local/bin/bash

# === Subcommand: delete ===
cmd_delete() {
  if [ -z "$1" ]; then
    cmd_delete_usage
    exit 1
  fi

  local VMNAME="$1"
  # Note: We are ignoring --datastore as find_any_vm handles searching all datastores.

  local found_vm_info
  found_vm_info=$(find_any_vm "$VMNAME")

  if [ -z "$found_vm_info" ]; then
    display_and_log "ERROR" "VM '$VMNAME' not found."
    exit 1
  fi

  local vm_source
  vm_source=$(echo "$found_vm_info" | cut -d':' -f1)

  # Confirm deletion first
  read -p "Are you sure you want to permanently delete VM '$VMNAME'? This action cannot be undone. (y/N): " -n 1 -r
  echo
  if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    display_and_log "INFO" "VM deletion cancelled."
    exit 0
  fi

  if [ "$vm_source" == "vm-bhyve" ]; then
    display_and_log "INFO" "VM '$VMNAME' is a vm-bhyve instance. Delegating to 'vm destroy'."
    # vm-bhyve's destroy command handles stopping the VM
    sudo vm destroy "$VMNAME"
  else # bhyve-cli native VM
    local datastore_path
    datastore_path=$(echo "$found_vm_info" | cut -d':' -f3)
    local vm_dir="$datastore_path/$VMNAME"

    display_and_log "INFO" "Deleting bhyve-cli VM '$VMNAME'..."

    # Stop the VM if it's running
    if is_vm_running "$VMNAME" "$vm_dir"; then
      display_and_log "INFO" "VM '$VMNAME' is running. Stopping it first..."
      # cmd_stop is already refactored and can find the VM
      if ! cmd_stop "$VMNAME" --silent; then
        display_and_log "ERROR" "Failed to stop VM '$VMNAME'. Cannot delete a running VM."
        exit 1
      fi
      # Wait for it to be fully stopped
      if ! wait_for_vm_status "$VMNAME" "$vm_dir" "stopped"; then
          display_and_log "ERROR" "Failed to stop VM '$VMNAME' during delete. Aborting."
          exit 1
      fi
    fi

    display_and_log "INFO" "Deleting VM files from '$vm_dir'..."
    # Unset LOG_FILE before deleting the directory to prevent errors
    unset LOG_FILE
    if rm -rf "$vm_dir"; then
      display_and_log "INFO" "Successfully deleted VM directory: $vm_dir"
    else
      display_and_log "ERROR" "Failed to delete VM directory: $vm_dir"
      exit 1
    fi
  fi
}

# === Usage: delete ===
cmd_delete_usage() {
  echo "Usage: bhyve-cli vm delete <vm_name>"
  echo ""
  echo "Permanently deletes a virtual machine and all its associated files."
  echo "Finds the VM across all available datastores (bhyve-cli and vm-bhyve)."
  echo ""
  echo "Arguments:"
  echo "  <vm_name>           The name of the virtual machine to delete."
}