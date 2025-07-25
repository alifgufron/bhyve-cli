#!/usr/local/bin/bash

# === Subcommand: startall ===
cmd_startall() {
  log "Entering cmd_startall function."
  display_and_log "INFO" "Attempting to start all configured VMs..."

  if [ ! -d "$VM_CONFIG_BASE_DIR" ] || [ -z "$(ls -A "$VM_CONFIG_BASE_DIR")" ]; then
    display_and_log "INFO" "No virtual machines configured to start."
    exit 0
  fi

  for VM_DIR_PATH in "$VM_CONFIG_BASE_DIR"/*/; do
    if [ -d "$VM_DIR_PATH" ]; then
      local VMNAME=$(basename "$VM_DIR_PATH")
      if ! is_vm_running "$VMNAME"; then
        log "Starting VM '$VMNAME'..."
        cmd_start "$VMNAME" --suppress-console-message
      else
        log "VM '$VMNAME' is already running. Skipping."
      fi
    fi
  done
  display_and_log "INFO" "Attempt to start all VMs complete."
  log "Exiting cmd_startall function."
}
