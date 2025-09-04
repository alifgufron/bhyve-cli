#!/usr/local/bin/bash

# === Subcommand: delete ===
cmd_delete() {
  log "Entering cmd_delete function for VM: $1"
  if [ -z "$1" ]; then
    cmd_delete_usage
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  # Check if VM is running
  if is_vm_running "$VMNAME"; then
    display_and_log "ERROR" "VM '$VMNAME' is still running."
    read -rp "Do you want to stop and delete the VM '$VMNAME'? [y/n]: " CONFIRM_STOP_DELETE
    if ! [[ "$CONFIRM_STOP_DELETE" =~ ^[Yy]$ ]]; then
      display_and_log "INFO" "VM deletion cancelled."
      log "VM deletion cancelled by user."
      exit 0 # Exit without deleting
    fi
    display_and_log "INFO" "Stopping VM '$VMNAME' before deletion..."
    cmd_stop "$VMNAME" --force # Force stop the VM
    # Give it a moment to ensure it's stopped
    sleep 2
  fi

  log "Deleting VM '$VMNAME'..."
  display_and_log "INFO" "Initiating deletion process for VM '$VMNAME'..."

  log "Cleaning up VM processes and kernel memory..."
  cleanup_vm_processes "$VMNAME" "$CONSOLE" "$LOG_FILE"

  log "Cleaning up VM network interfaces..."
  cleanup_vm_network_interfaces "$VMNAME"

  # === Remove console device files ===
  if [ -e "/dev/${CONSOLE}A" ]; then
    log "Removing console device /dev/${CONSOLE}A..."
    rm -f "/dev/${CONSOLE}A"
    if [ $? -eq 0 ]; then
      log "/dev/${CONSOLE}A removed successfully."
    else
      display_and_log "WARNING" "Failed to remove /dev/${CONSOLE}A."
    fi
  else
    log "Console device /dev/${CONSOLE}A not found. Skipping removal."
  fi
  if [ -e "/dev/${CONSOLE}B" ]; then
    log "Removing console device /dev/${CONSOLE}B..."
    rm -f "/dev/${CONSOLE}B"
    if [ $? -eq 0 ]; then
      log "/dev/${CONSOLE}B removed successfully."
    else
      display_and_log "WARNING" "Failed to remove /dev/${CONSOLE}B."
    fi
  else
    log "Console device /dev/${CONSOLE}B not found. Skipping removal."
  fi

  # Remove vm.pid file if it exists
  delete_vm_pid "$VMNAME"
  log "vm.pid file removal attempted."

  unset LOG_FILE # Unset LOG_FILE here, after all operations that might use it for the VM.

  # Remove vm.pid file if it exists
  delete_vm_pid "$VMNAME"
  log "vm.pid file removal attempted."

  unset LOG_FILE # Unset LOG_FILE after vm.pid is handled and before VM directory is removed

  # === Delete VM directory ===
  display_and_log "INFO" "Deleting VM directory: $VM_DIR..."
  rm -rf "$VM_DIR"
  if [ $? -eq 0 ]; then
    log "VM directory '$VM_DIR' removed successfully."
  else
    log "Failed to remove VM directory '$VM_DIR'. Please check permissions."
  fi

  display_and_log "INFO" "VM '$VMNAME' successfully deleted."
  log "Exiting cmd_delete function for VM: $VMNAME"
}
