#!/usr/local/bin/bash

# === Helper function to process and print VMs from a given directory ===
# Arg1: base_dir, Arg2: source_label, Arg3: datastore_name
_process_vm_dir() {
  local base_dir=$1
  local source_label=$2
  local datastore_name=$3

    if [ ! -d "$base_dir" ] || [ -z "$(/bin/ls -A "$base_dir" 2>/dev/null)" ]; then
    return
  fi

  for VM_DIR_PATH in "$base_dir"/*/; do
    if [ -d "$VM_DIR_PATH" ]; then
      local VMNAME=$(basename "$VM_DIR_PATH")
      
      if [ "$VMNAME" == "templates" ]; then
        continue
      fi

      local CONF_FILE
      if [ "$source_label" == "vm-bhyve" ]; then
        CONF_FILE="$VM_DIR_PATH/$VMNAME.conf"
      else
        CONF_FILE="$VM_DIR_PATH/vm.conf"
      fi
      
      if [ -f "$CONF_FILE" ]; then
        # Clear previous VM's configuration variables to prevent pollution
        unset UUID CPUS MEMORY TAP_0 MAC_0 BRIDGE_0 NIC_0_TYPE DISK DISKSIZE CONSOLE LOG AUTOSTART BOOTLOADER_TYPE VNC_PORT VNC_WAIT UEFI_FIRMWARE_PATH
        for i in $(seq 1 10); do # Unset indexed variables up to DISK_10, NIC_10 etc.
          unset DISK_${i} DISK_${i}_TYPE TAP_${i} MAC_${i} BRIDGE_${i} NIC_${i}_TYPE
        done

        . "$CONF_FILE"
        local CPUS_FROM_CONF=${cpu:-N/A}
        local MEMORY_FROM_CONF=${memory:-N/A}
        local PID=$(get_vm_pid "$VMNAME" "$VM_DIR_PATH")
        local STATUS="stopped"

        if [ -n "$PID" ]; then
          STATUS=$(get_vm_status "$PID")
          local STATS=$(ps -o %cpu,%mem,etime -p "$PID" | tail -n 1)
          CPU_USAGE=$(echo "$STATS" | awk '{print $1}')
          MEM_USAGE=$(echo "$STATS" | awk '{print $2}')
          local ETIME=$(echo "$STATS" | awk '{print $3}')
          UPTIME=$(format_etime "$ETIME")
        else
          PID="-"
          CPU_USAGE="-"
          MEM_USAGE="-"
          UPTIME="-"
        fi

        local cpus_val
        local mem_val
        if [ "$source_label" == "vm-bhyve" ]; then
          cpus_val=${CPUS_FROM_CONF}
          mem_val=${MEMORY_FROM_CONF}
        else
          cpus_val=${CPUS:-N/A}
          mem_val=${MEMORY:-N/A}
        fi
        local autostart_val=${AUTOSTART:-${vm_autostart:-no}}
        local bootloader_val=${BOOTLOADER_TYPE:-${loader:-bhyveload}}
        local vnc_port_val=${VNC_PORT:--}

        local DISPLAY_VM_NAME="$VMNAME"
        # Removed: if [ "$source_label" == "bhyve-cli" ]; then
        # Removed:   DISPLAY_VM_NAME="$VMNAME ($datastore_name)"
        # Removed: fi

        printf "% -40s % -20s % -12s % -10s % -8s % -10s % -10s % -10s % -8s % -6s % -6s % -12s\n" \
          "$DISPLAY_VM_NAME" "$datastore_name" "$bootloader_val" "$autostart_val" "$cpus_val" \
          "$mem_val" "$vnc_port_val" "$STATUS" "$PID" "$CPU_USAGE" "$MEM_USAGE" "$UPTIME"
      fi
    fi
  done
}


# === Subcommand: list ===
cmd_list() {
  local bhyve_cli_vms_found=false
  local vm_bhyve_vms_found=false

  # --- Process bhyve-cli VMs ---
  local bhyve_cli_datastores
  bhyve_cli_datastores=$(get_all_bhyve_cli_datastores)

  if [ -n "$bhyve_cli_datastores" ]; then
    printf "% -40s % -20s % -12s % -10s % -8s % -10s % -10s % -10s % -8s % -6s % -6s % -12s\n" "VM NAME (bhyve-cli)" "DATASTORE" "BOOTLOADER" "AUTOSTART" "CPUS" "MEMORY" "VNC PORT" "STATUS" "PID" "CPU%" "MEM%" "UPTIME"
    for datastore_pair in $bhyve_cli_datastores; do
      local datastore_name
      local datastore_path
      datastore_name=$(echo "$datastore_pair" | cut -d':' -f1)
      datastore_path=$(echo "$datastore_pair" | cut -d':' -f2)
      _process_vm_dir "$datastore_path" "bhyve-cli" "$datastore_name"
    done
    bhyve_cli_vms_found=true
  fi

  # --- Process vm-bhyve VMs ---
  local vm_bhyve_dirs
  vm_bhyve_dirs=$(get_vm_bhyve_dir)

  if [ -n "$vm_bhyve_dirs" ]; then
    if [ "$bhyve_cli_vms_found" = true ]; then
      echo # Add a newline for separation
    fi
    printf "% -40s % -20s % -12s % -10s % -8s % -10s % -10s % -10s % -8s % -6s % -6s % -12s\n" "VM NAME (vm-bhyve)" "DATASTORE" "BOOTLOADER" "AUTOSTART" "CPUS" "MEMORY" "VNC PORT" "STATUS" "PID" "CPU%" "MEM%" "UPTIME"
    
    # Loop through each datastore directory
    for datastore_pair in $vm_bhyve_dirs; do
      local datastore_name
      local datastore_path
      datastore_name=$(echo "$datastore_pair" | cut -d':' -f1)
      datastore_path=$(echo "$datastore_pair" | cut -d':' -f2)
      
      _process_vm_dir "$datastore_path" "vm-bhyve" "$datastore_name"
    done
    vm_bhyve_vms_found=true
  fi

  if [ "$bhyve_cli_vms_found" = false ] && [ "$vm_bhyve_vms_found" = false ]; then
    display_and_log "INFO" "No virtual machines found."
    exit 0
  fi
}
