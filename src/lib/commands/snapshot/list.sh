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
  local datastore_path
  vm_source=$(echo "$found_vm_info" | cut -d':' -f1)
  datastore_path=$(echo "$found_vm_info" | cut -d':' -f3)

  # Delegate to vm-bhyve if it's a vm-bhyve VM
  if [ "$vm_source" == "vm-bhyve" ]; then
    if ! command -v vm >/dev/null 2>&1; then
      display_and_log "ERROR" "'vm-bhyve' command not found. Please ensure it is installed and in your PATH."
      exit 1
    fi
    display_and_log "INFO" "Delegating to 'vm snapshot list' for vm-bhyve VM '$VMNAME'..."
    vm snapshot "$VMNAME" list
    exit $?
  fi

  # --- Logic for bhyve-cli VMs ---
  local SNAPSHOT_ROOT_DIR="$datastore_path/snapshots" # Snapshot storage within VM's datastore
  local VM_SNAPSHOT_DIR="$SNAPSHOT_ROOT_DIR/$VMNAME"

  if [ ! -d "$VM_SNAPSHOT_DIR" ] || [ -z "$(ls -A "$VM_SNAPSHOT_DIR" 2>/dev/null)" ]; then
    display_and_log "INFO" "No snapshots found for VM '$VMNAME'."
    exit 0
  fi

  echo_message "Snapshots for VM '$VMNAME':"
  echo_message "---------------------------------"
  local count=0
  for SNAPSHOT_PATH in "$VM_SNAPSHOT_DIR"/*/; do
    if [ -d "$SNAPSHOT_PATH" ]; then
      local SNAPSHOT_NAME=$(basename "$SNAPSHOT_PATH")
      local SNAPSHOT_SIZE_BYTES=$(du -sk "$SNAPSHOT_PATH" | awk '{print $1 * 1024}') # du -sk gives KB
      local SNAPSHOT_SIZE_HUMAN=$(format_bytes "$SNAPSHOT_SIZE_BYTES")
      echo_message "- $SNAPSHOT_NAME ($SNAPSHOT_SIZE_HUMAN)"
      count=$((count + 1))
    fi
  done

  if [ "$count" -eq 0 ]; then
    display_and_log "INFO" "No snapshots found for VM '$VMNAME'."
  fi
  echo_message "---------------------------------"
}