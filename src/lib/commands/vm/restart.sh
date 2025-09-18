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

  local found_vm_info
  found_vm_info=$(find_any_vm "$VMNAME")

  if [ -z "$found_vm_info" ]; then
    display_and_log "ERROR" "VM '$VMNAME' not found."
    exit 1
  fi

  local vm_source
  vm_source=$(echo "$found_vm_info" | cut -d':' -f1)

  if [ "$vm_source" == "vm-bhyve" ]; then
    display_and_log "INFO" "VM '$VMNAME' is a vm-bhyve instance. Delegating restart command."
    if [ "$FORCE_RESTART" = true ]; then
      # vm-bhyve restart doesn't have a --force, but reset is the equivalent
      display_and_log "INFO" "--force specified, using 'vm reset'."
      sudo vm reset "$VMNAME"
    else
      sudo vm restart "$VMNAME"
    fi
  else # bhyve-cli native VM
    local datastore_path
    datastore_path=$(echo "$found_vm_info" | cut -d':' -f3)
    local vm_dir="$datastore_path/$VMNAME"
    load_vm_config "$VMNAME" "$vm_dir"

    display_and_log "INFO" "Restarting VM '$VMNAME'..."

    # Check if the VM is running
    if ! is_vm_running "$VMNAME" "$vm_dir"; then
      display_and_log "INFO" "VM '$VMNAME' is not running. Starting it..."
      cmd_start "$VMNAME" --suppress-console-message
      display_and_log "INFO" "VM '$VMNAME' started."
      log "Exiting cmd_restart function for VM: $VMNAME"
      exit 0
    fi

    if [ "$FORCE_RESTART" = true ]; then
      # --- Fast but unsafe restart ---
      if $BHYVECTL --vm="$VMNAME" --force-reset; then
        log "VM '$VMNAME' successfully reset via bhyvectl. Waiting a moment before starting again..."
        sleep 2 # Give a moment for the process to fully terminate
        cmd_start "$VMNAME" --suppress-console-message
        display_and_log "INFO" "VM '$VMNAME' successfully restarted (forced)."
      else
        display_and_log "ERROR" "Forced restart failed. The VM might be in an inconsistent state."
        log "bhyvectl --force-reset failed for '$VMNAME'."
        exit 1 # Exit with an error to indicate the forced restart failed
      fi
    else
      # --- Safe default restart ---
      cmd_stop "$VMNAME" --silent
      # Wait for the VM to be fully stopped before starting again
      if ! wait_for_vm_status "$VMNAME" "$vm_dir" "stopped"; then
          display_and_log "ERROR" "Failed to stop VM '$VMNAME' during restart. Aborting."
          exit 1
      fi
      cmd_start "$VMNAME" --suppress-console-message
      display_and_log "INFO" "VM '$VMNAME' successfully restarted."
    fi
  fi

  log "Exiting cmd_restart function for VM: $VMNAME"
}