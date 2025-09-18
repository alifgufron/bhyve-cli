#!/usr/local/bin/bash

source "$LIB_DIR/functions/config.sh"

# === Subcommand: console ===
cmd_console() {
  
  if [ -z "$1" ]; then
    cmd_console_usage
    exit 1
  fi

  local VMNAME="$1"

  local found_vm_info
  found_vm_info=$(find_any_vm "$VMNAME")

  if [ -z "$found_vm_info" ]; then
    display_and_log "ERROR" "VM '$VMNAME' not found in any bhyve-cli or vm-bhyve datastores."
    exit 1
  fi

  local vm_source
  vm_source=$(echo "$found_vm_info" | cut -d':' -f1)
  local datastore_path
  datastore_path=$(echo "$found_vm_info" | cut -d':' -f3)
  local vm_dir="$datastore_path/$VMNAME"

  # Delegate to native vm-bhyve command if applicable
  if [ "$vm_source" == "vm-bhyve" ]; then
    display_and_log "INFO" "VM '$VMNAME' is a vm-bhyve instance. Delegating to 'vm console'."
    # The native 'vm' command handles status checks
    sudo vm console "$VMNAME"
  else # Handle bhyve-cli native VMs
    load_vm_config "$VMNAME" "$vm_dir"

    if ! is_vm_running "$VMNAME" "$vm_dir"; then
      display_and_log "ERROR" "VM '$VMNAME' is not running."
      exit 1
    fi

    local vm_status
    vm_status=$(get_vm_status "$(get_vm_pid "$VMNAME" "$vm_dir")")
    if [ "$vm_status" = "suspended" ]; then
      display_and_log "WARNING" "VM '$VMNAME' is suspended. Please resume it first."
      exit 1
    fi

    clear
    echo_message ">>> Connecting to console for VM '$VMNAME'. Type ~. to exit."
    cu -l "/dev/${CONSOLE}B" -s 115200
  fi

}
