#!/usr/local/bin/bash

# === Subcommand: stopall ===
cmd_stopall() {
  log "Entering cmd_stopall function."
  start_spinner "Checking VM statuses and stopping any running VMs..."

  local FORCE_STOP=false
  if [ "$1" = "--force" ]; then
    FORCE_STOP=true
  fi

  local stopped_vms=0
  local already_stopped_vms=0
  local failed_vms=0
  local total_vms=0

  # Get all bhyve-cli datastores
  local bhyve_cli_datastores
  bhyve_cli_datastores=$(get_all_bhyve_cli_datastores)

  for datastore_pair in $bhyve_cli_datastores; do
    local ds_name=$(echo "$datastore_pair" | cut -d':' -f1)
    local ds_path=$(echo "$datastore_pair" | cut -d':' -f2)

    for VM_DIR_PATH in "$ds_path"/*/; do # Iterate through each VM directory in the datastore
      local VMNAME=$(basename "$VM_DIR_PATH")
      if [ "$VMNAME" = "templates" ] || [ "$VMNAME" = "snapshots" ]; then # Skip special directories
        log "Skipping special directory: $VMNAME."
        continue
      fi

      if [ -d "$VM_DIR_PATH" ]; then
        total_vms=$((total_vms + 1))
        # Load VM config to ensure VM_DIR is set for is_vm_running and cmd_stop
        # We don't need to unset variables here as cmd_stop handles its own scope
        load_vm_config "$VMNAME" "$VM_DIR_PATH"

        if is_vm_running "$VMNAME" "$VM_DIR_PATH"; then # Pass vm_dir to is_vm_running
          log "Stopping VM '$VMNAME'..."
          if [ "$FORCE_STOP" = true ]; then
            if cmd_stop "$VMNAME" --force --silent; then
              stopped_vms=$((stopped_vms + 1))
            else
              failed_vms=$((failed_vms + 1))
              log "Failed to stop VM '$VMNAME'."
            fi
          else
            if cmd_stop "$VMNAME" --silent; then
              stopped_vms=$((stopped_vms + 1))
            else
              failed_vms=$((failed_vms + 1))
              log "Failed to stop VM '$VMNAME'."
            fi
          fi
        else
          log "VM '$VMNAME' is not running. Skipping."
          already_stopped_vms=$((already_stopped_vms + 1))
        fi
      fi
    done
  done

  local final_message=""
  if [ "$stopped_vms" -gt 0 ]; then
    final_message+="Successfully stopped $stopped_vms VM(s). "
  fi
  if [ "$already_stopped_vms" -gt 0 ]; then
    final_message+="$already_stopped_vms VM(s) already stopped. "
  fi
  if [ "$failed_vms" -gt 0 ]; then
    final_message+="Failed to stop $failed_vms VM(s). "
  fi

  if [ "$total_vms" -eq 0 ]; then
    stop_spinner "No virtual machines found."
  elif [ -n "$final_message" ]; then
    stop_spinner "Attempt to stop all VMs complete. $final_message"
  else
    stop_spinner "Attempt to stop all VMs complete."
  fi

  log "Exiting cmd_stopall function."
}
