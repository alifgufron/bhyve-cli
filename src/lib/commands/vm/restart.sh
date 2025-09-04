#!/usr/local/bin/bash

# === Subcommand: restart ===
cmd_restart() {
  log "Entering cmd_restart function for VM: $1"
  if [ -z "$1" ]; then
    cmd_restart_usage
    exit 1
  fi

  local VMNAME="$1"
  local FORCE_RESTART=false

  # Check for --force flag
  if [ "$2" = "--force" ]; then
    FORCE_RESTART=true
  fi

  load_vm_config "$VMNAME"

  display_and_log "INFO" "Restarting VM '$VMNAME'..."

  # Check if the VM is running
  if ! is_vm_running "$VMNAME"; then
    display_and_log "INFO" "VM '$VMNAME' is not running. Starting it..."
    cmd_start "$VMNAME" --suppress-console-message
    display_and_log "INFO" "VM '$VMNAME' started."
    log_debug "Exiting cmd_restart function for VM: $VMNAME"
    exit 0
  fi

  if [ "$FORCE_RESTART" = true ]; then
    # --- Fast but unsafe restart ---
    local BHYVECTL_RESET_CMD="$BHYVECTL --vm=\"$VMNAME\" --force-reset"
    log_debug "Executing: $BHYVECTL_RESET_CMD"

    if $BHYVECTL --vm=\"$VMNAME\" --force-reset; then
      log_debug "VM '$VMNAME' successfully reset via bhyvectl. Waiting a moment before starting again..."
      sleep 2 # Give a moment for the process to fully terminate
      cmd_start "$VMNAME" --suppress-console-message
      display_and_log "INFO" "VM '$VMNAME' successfully restarted."
    else
      display_and_log "WARNING" "Fast reset failed. The VM might be in an inconsistent state."
      log "bhyvectl --force-reset failed for '$VMNAME'."
      exit 1 # Exit with an error to indicate the forced restart failed
    fi
  else
    # --- Safe default restart ---
    cmd_stop "$VMNAME" --silent
    sleep 2 # Give it a moment to fully stop and clean up
    cmd_start "$VMNAME" --suppress-console-message
    display_and_log "INFO" "VM '$VMNAME' successfully restarted."
  fi

  log "Exiting cmd_restart function for VM: $VMNAME"
}