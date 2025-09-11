#!/usr/local/bin/bash

# === Subcommand: suspend ===
cmd_suspend() {
  if [ -z "$1" ]; then
    cmd_suspend_usage
    exit 1
  fi

  local VMNAME="$1"

  # Detect VM source
  local vm_source=""
  if [ -d "$VM_CONFIG_BASE_DIR/$VMNAME" ]; then
    vm_source="bhyve-cli"
    load_vm_config "$VMNAME" # Load config for bhyve-cli VMs
  else
    local vm_bhyve_base_dir
    vm_bhyve_base_dir=$(get_vm_bhyve_dir)
    if [ -n "$vm_bhyve_base_dir" ] && [ -d "$vm_bhyve_base_dir/$VMNAME" ]; then
      vm_source="vm-bhyve"
      # No need to load full config for vm-bhyve, just need PID
    fi
  fi

  if [ -z "$vm_source" ]; then
    display_and_log "ERROR" "VM '$VMNAME' not found in bhyve-cli or vm-bhyve directories."
    exit 1
  fi

  local pid=$(get_vm_pid "$VMNAME")
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
