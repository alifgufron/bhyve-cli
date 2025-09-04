#!/usr/local/bin/bash

# === Subcommand: startall ===
cmd_startall() {
  log "Entering cmd_startall function."
  start_spinner "Checking VM statuses and starting any stopped VMs..."

  if [ ! -d "$VM_CONFIG_BASE_DIR" ] || [ -z "$(ls -A "$VM_CONFIG_BASE_DIR")" ]; then
    stop_spinner "No virtual machines configured to start."
    exit 0
  fi

  local started_vms=0
  local already_running_vms=0
  local failed_vms=0
  local total_vms=0

  for VM_DIR_PATH in "$VM_CONFIG_BASE_DIR"/*/; do
    local VMNAME=$(basename "$VM_DIR_PATH")
    if [ "$VMNAME" = "templates" ]; then
      log "Skipping templates directory."
      continue
    fi

    if [ -d "$VM_DIR_PATH" ]; then
      total_vms=$((total_vms + 1))
      # Clean up previous VM's config variables from the environment
      unset UUID CPUS MEMORY TAP_0 MAC_0 BRIDGE_0 NIC_0_TYPE DISK DISKSIZE CONSOLE LOG AUTOSTART BOOTLOADER_TYPE VNC_PORT VNC_WAIT
      for i in $(seq 1 10); do # Unset up to DISK_10, TAP_10, etc.
        unset DISK_${i} DISK_${i}_TYPE TAP_${i} MAC_${i} BRIDGE_${i} NIC_${i}_TYPE
      done

      load_vm_config "$VMNAME"

      if is_vm_running "$VMNAME"; then
        log "VM '$VMNAME' is already running. Skipping."
        already_running_vms=$((already_running_vms + 1))
      else
        log "Starting VM '$VMNAME'..."
        # Call cmd_start with --suppress-console-message to avoid extra output
        if cmd_start "$VMNAME" --suppress-console-message; then
          started_vms=$((started_vms + 1))
        else
          failed_vms=$((failed_vms + 1))
          log "Failed to start VM '$VMNAME'."
        fi
      fi
    fi
  done

  local final_message=""
  if [ "$started_vms" -gt 0 ]; then
    final_message+="Successfully started $started_vms VM(s). "
  fi
  if [ "$already_running_vms" -gt 0 ]; then
    final_message+="$already_running_vms VM(s) already running. "
  fi
  if [ "$failed_vms" -gt 0 ]; then
    final_message+="Failed to start $failed_vms VM(s). "
  fi

  if [ "$total_vms" -eq 0 ]; then
    stop_spinner "No virtual machines found."
  elif [ "$started_vms" -eq 0 ] && [ "$failed_vms" -eq 0 ] && [ "$already_running_vms" -gt 0 ]; then
    stop_spinner "All configured VMs are already running."
  elif [ -n "$final_message" ]; then
    stop_spinner "Attempt to start all VMs complete. $final_message"
  else
    stop_spinner "Attempt to start all VMs complete."
  fi

  log "Exiting cmd_startall function."
}
