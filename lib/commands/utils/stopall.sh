#!/usr/local/bin/bash

# === Subcommand: stopall ===
cmd_stopall() {
  log "Entering cmd_stopall function."
  display_and_log "INFO" "Attempting to stop all configured VMs..."

  local FORCE_STOP=false
  if [ "$1" = "--force" ]; then
    FORCE_STOP=true
  fi

  if [ ! -d "$VM_CONFIG_BASE_DIR" ] || [ -z "$(ls -A "$VM_CONFIG_BASE_DIR")" ]; then
    display_and_log "INFO" "No virtual machines configured to stop."
    exit 0
  fi

  for VM_DIR_PATH in "$VM_CONFIG_BASE_DIR"/*/; do
    if [ -d "$VM_DIR_PATH" ]; then
      local VMNAME=$(basename "$VM_DIR_PATH")
      if is_vm_running "$VMNAME"; then
        log "Stopping VM '$VMNAME'..."
        if [ "$FORCE_STOP" = true ]; then
          cmd_stop "$VMNAME" --force
        else
          cmd_stop "$VMNAME"
        fi
      else
        log "VM '$VMNAME' is not running. Skipping."
      fi
    fi
  done
  display_and_log "INFO" "Attempt to stop all VMs complete."
  log "Exiting cmd_stopall function."
}
