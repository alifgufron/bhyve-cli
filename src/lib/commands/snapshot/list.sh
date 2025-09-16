#!/usr/local/bin/bash

# === Subcommand: snapshot list ===
cmd_snapshot_list() {
  if [ -z "$1" ]; then
    cmd_snapshot_usage
    exit 1
  fi

  local VMNAME="$1"

  # Use the centralized find_any_vm function to determine the VM source
  local found_vm_info
  found_vm_info=$(find_any_vm "$VMNAME")

  if [ -z "$found_vm_info" ]; then
    display_and_log "ERROR" "VM '$VMNAME' not found in any bhyve-cli or vm-bhyve datastores."
    exit 1
  fi

  local vm_source
  vm_source=$(echo "$found_vm_info" | cut -d':' -f1)

  # Delegate to vm-bhyve if it's a vm-bhyve VM
  if [ "$vm_source" == "vm-bhyve" ]; then
    if ! command -v vm >/dev/null 2>&1; then
      display_and_log "ERROR" "'vm-bhyve' command not found. Please ensure it is installed and in your PATH."
      exit 1
    fi
    display_and_log "INFO" "Delegating to 'vm snapshot list' for vm-bhyve VM '$VMNAME'..."
    vm snapshot list "$VMNAME"
    exit $?
  fi

  # --- Logic for bhyve-cli VMs ---
  # Snapshots for bhyve-cli are stored centrally
  local SNAPSHOT_DIR="$VM_CONFIG_BASE_DIR/snapshots/$VMNAME"

  if [ ! -d "$SNAPSHOT_DIR" ] || [ -z "$(ls -A "$SNAPSHOT_DIR" 2>/dev/null)" ]; then
    display_and_log "INFO" "No snapshots found for VM '$VMNAME'."
    exit 0
  fi

  echo_message "Snapshots for VM '$VMNAME':"
  echo_message "---------------------------------"
  local count=0
  for SNAPSHOT_PATH in "$SNAPSHOT_DIR"/*/; do
    if [ -d "$SNAPSHOT_PATH" ]; then
      local SNAPSHOT_NAME=$(basename "$SNAPSHOT_PATH")
      echo_message "- $SNAPSHOT_NAME"
      count=$((count + 1))
    fi
  done

  if [ "$count" -eq 0 ]; then
    display_and_log "INFO" "No snapshots found for VM '$VMNAME'."
  fi
  echo_message "---------------------------------"
}