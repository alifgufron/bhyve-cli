#!/usr/local/bin/bash

# === Subcommand: suspend ===
cmd_suspend() {
  if [ -z "$1" ]; then
    cmd_suspend_usage
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

  local vm_source
  vm_source=$(echo "$found_vm_info" | cut -d':' -f1)
  # No delegation for vm-bhyve suspend, use native bhyve-cli logic

  # Parse the new format: source:datastore_name:datastore_path
  local datastore_path
  datastore_path=$(echo "$found_vm_info" | cut -d':' -f3)
  local vm_dir="$datastore_path/$VMNAME"

  # Correctly get PID using the full vm_dir path
  local pid=$(get_vm_pid "$VMNAME" "$vm_dir")
  if [ -z "$pid" ]; then
    display_and_log "ERROR" "VM '$VMNAME' is not running. Cannot suspend."
    exit 1
  fi

  display_and_log "INFO" "Suspending VM '$VMNAME' (PID: $pid)..."
  if kill -SIGSTOP "$pid"; then
    display_and_log "INFO" "VM '$VMNAME' suspended successfully."
  else
    display_and_log "ERROR" "Failed to suspend VM '$VMNAME'."
    exit 1
  fi
}