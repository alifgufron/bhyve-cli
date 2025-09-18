#!/usr/local/bin/bash

# === Subcommand: vnc ===
cmd_vnc() {
  
  if [ -z "$1" ]; then
    cmd_vnc_usage
    exit 1
  fi

  local VMNAME_ARG="$1" # Use VMNAME_ARG to avoid conflict with global VMNAME

  # Find VM across all datastores
  local found_vm_info
  found_vm_info=$(find_any_vm "$VMNAME_ARG")

  if [ -z "$found_vm_info" ]; then
    display_and_log "ERROR" "VM '$VMNAME_ARG' not found in any bhyve-cli or vm-bhyve datastores."
    exit 1
  fi

  local vm_source
  local datastore_path
  vm_source=$(echo "$found_vm_info" | cut -d':' -f1)
  datastore_path=$(echo "$found_vm_info" | cut -d':' -f3)
  local vm_dir="$datastore_path/$VMNAME_ARG" # Define vm_dir here

  # If it's a vm-bhyve VM, we don't manage VNC directly
  if [ "$vm_source" == "vm-bhyve" ]; then
    display_and_log "ERROR" "VNC connection for vm-bhyve VMs is not directly supported by bhyve-cli. Please use vm-bhyve's mechanism."
    exit 1
  fi

  # Load VM config using the found datastore_path. This sets the global VMNAME, VM_DIR, CONF_FILE etc.
  load_vm_config "$VMNAME_ARG" "$vm_dir"

  if [ -z "$VNC_PORT" ]; then
    display_and_log "ERROR" "VNC is not configured for VM '$VMNAME_ARG'. Please use 'create --vnc-port <port>' or 'modify --vnc-port <port>'."
    exit 1
  fi

  if ! is_vm_running "$VMNAME_ARG" "$vm_dir"; then
    display_and_log "ERROR" "VM '$VMNAME_ARG' is not running. Please start the VM first."
    exit 1
  fi

  echo_message "Connecting to VNC console for VM '$VMNAME_ARG'."
  echo_message "Please ensure you have a VNC client installed (e.g., \`vncviewer\`)."
  echo_message "You can connect to: localhost:$VNC_PORT"

  # Attempt to launch vncviewer if available
  if command -v vncviewer >/dev/null 2>&1; then
    display_and_log "INFO" "Launching vncviewer..."
    vncviewer "localhost::$VNC_PORT" &
  else
    display_and_log "WARNING" "vncviewer not found. Please connect manually to localhost:$VNC_PORT with your VNC client."
  fi
  
}

