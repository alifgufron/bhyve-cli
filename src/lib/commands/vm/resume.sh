#!/usr/local/bin/bash

# === Subcommand: resume ===
cmd_resume() {
  if [ -z "$1" ]; then
    cmd_resume_usage # This usage function will need to be created in lib/usage/vm.sh
    exit 1
  fi

  local VMNAME="$1"

  # Use the centralized find_any_vm function
  local found_vm_info
  found_vm_info=$(find_any_vm "$VMNAME")

  if [ -z "$found_vm_info" ]; then
    display_and_log "ERROR" "VM '$VMNAME' not found in any bhyve-cli or vm-bhyve datastores."
    exit 1
  fi

  # Parse the new format: source:datastore_name:datastore_path
  local datastore_path
  datastore_path=$(echo "$found_vm_info" | cut -d':' -f3)
  local vm_dir="$datastore_path/$VMNAME"

  # Correctly get PID using the full vm_dir path
  local pid=$(get_vm_pid "$VMNAME" "$vm_dir")
  if [ -z "$pid" ]; then
    display_and_log "ERROR" "VM '$VMNAME' is not running or suspended. Cannot resume."
    exit 1
  fi

  local current_status
  current_status=$(get_vm_status "$pid")

  if [ "$current_status" != "suspended" ]; then
      display_and_log "ERROR" "VM '$VMNAME' is not suspended. Current status: $current_status."
      exit 1
  fi

  display_and_log "INFO" "Resuming VM '$VMNAME' (PID: $pid)..."
  if kill -SIGCONT "$pid"; then
    set_vm_status "$VMNAME" "running"
    display_and_log "INFO" "VM '$VMNAME' resumed successfully."
  else
    display_and_log "ERROR" "Failed to resume VM '$VMNAME'."
    exit 1
  fi
}
