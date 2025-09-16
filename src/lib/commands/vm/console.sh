#!/usr/local/bin/bash

# === Subcommand: console ===
cmd_console() {
  
  if [ -z "$1" ]; then
    cmd_console_usage
    exit 1
  fi

  VMNAME="$1"

  # Find VM across all datastores
  local found_bhyve_cli_vm
  found_bhyve_cli_vm=$(find_vm_in_datastores "$VMNAME")

  if [ -n "$found_bhyve_cli_vm" ]; then
    local datastore_name=$(echo "$found_bhyve_cli_vm" | head -n 1 | cut -d':' -f1)
    local vm_dir=$(echo "$found_bhyve_cli_vm" | head -n 1 | cut -d':' -f2)/"$VMNAME"
    load_vm_config "$VMNAME" "$vm_dir" # Pass vm_dir as custom_datastore_path
  else
    # If not found in bhyve-cli datastores, check vm-bhyve directories
    local vm_bhyve_dirs
    vm_bhyve_dirs=$(get_vm_bhyve_dir) # Returns "name:path" pairs

    local vm_found_in_vm_bhyve=false
    if [ -n "$vm_bhyve_dirs" ]; then
      for datastore_pair in $vm_bhyve_dirs; do
        local current_ds_name=$(echo "$datastore_pair" | cut -d':' -f1)
        local current_ds_path=$(echo "$datastore_pair" | cut -d':' -f2)
        
        if [ -d "$current_ds_path/$VMNAME" ]; then
          # For vm-bhyve VMs, we need to set VM_DIR and source its config.
          VM_DIR="$current_ds_path/$VMNAME"
          local conf_file="$VM_DIR/$VMNAME.conf"
          if [ -f "$conf_file" ]; then
            . "$conf_file"
            # Map vm-bhyve variables to our internal variables
            CPUS=${cpu:-N/A}
            MEMORY=${memory:-N/A}
            BOOTLOADER_TYPE=${loader:-bhyveload}
            AUTOSTART=${autostart:-no}
            LOG_FILE="$VM_DIR/vm-bhyve.log"
            CONSOLE=${console:-nmdm1}
            vm_found_in_vm_bhyve=true
            break # VM found, exit loop
          else
            display_and_log "ERROR" "VM configuration for '$VMNAME' not found in vm-bhyve directory: $conf_file"
            exit 1
          fi
        fi
      done
    fi

    if [ "$vm_found_in_vm_bhyve" = false ]; then
      display_and_log "ERROR" "VM '$VMNAME' not found in any bhyve-cli or vm-bhyve datastores."
      exit 1
    fi
  fi

  if ! is_vm_running "$VMNAME"; then
    display_and_log "ERROR" "VM '$VMNAME' is not running."
    exit 1
  fi

  local vm_status=$(get_vm_status "$VMNAME")
  if [ "$vm_status" = "suspended" ]; then
    display_and_log "WARNING" "VM '$VMNAME' is suspended and cannot be accessed via console. Please resume it first."
    exit 1
  fi
  

  clear
  echo_message ">>> Connecting to console for VM '$VMNAME'. Type ~. to exit."
  cu -l /dev/"${CONSOLE}B" -s 115200
  
}
