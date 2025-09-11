#!/usr/local/bin/bash

# === Helper function to process and print VMs from a given directory ===
_process_vm_dir() {
  local base_dir=$1
  local source_label=$2

  if [ ! -d "$base_dir" ] || [ -z "$(ls -A "$base_dir" 2>/dev/null)" ]; then
    return
  fi

  for VM_DIR_PATH in "$base_dir"/*/; do
    if [ -d "$VM_DIR_PATH" ]; then
      local VMNAME=$(basename "$VM_DIR_PATH")
      # Skip templates directory
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
        # Source the config in a subshell to avoid polluting the main script's scope
        (
          . "$CONF_FILE"
          local PID=$(get_vm_pid "$VMNAME")
          local STATUS="stopped"

          if [ -n "$PID" ]; then
            STATUS=$(get_vm_status "$PID")
            # Get stats using ps
            local STATS=$(ps -o %cpu,%mem,etime -p "$PID" | tail -n 1)
            CPU_USAGE=$(echo "$STATS" | awk '{print $1}')
            MEM_USAGE=$(echo "$STATS" | awk '{print $2}')
            
            # Format uptime
            local ETIME=$(echo "$STATS" | awk '{print $3}')
            UPTIME=$(format_etime "$ETIME")
          else
            PID="-"
            CPU_USAGE="-"
            MEM_USAGE="-"
            UPTIME="-"
          fi

          # Adjust for vm-bhyve config naming if needed
          local cpus_val=${CPUS:-${vm_cpus:-N/A}}
          local mem_val=${MEMORY:-${vm_ram:-N/A}}
          local autostart_val=${AUTOSTART:-${vm_autostart:-no}}
          local bootloader_val=${BOOTLOADER_TYPE:-${loader:-bhyveload}}

          printf "%-25s %-12s %-10s %-8s %-10s %-10s %-15s %-10s %-10s %-12s\n" \
            "$VMNAME" \
            "$bootloader_val" \
            "$autostart_val" \
            "$cpus_val" \
            "$mem_val" \
            "$STATUS" \
            "$PID" \
            "$CPU_USAGE" \
            "$MEM_USAGE" \
            "$UPTIME"
        )
      fi
    fi
  done
}


# === Subcommand: list ===
cmd_list() {
  
  local bhyve_cli_vms_found=false
  local vm_bhyve_vms_found=false

  # --- Process bhyve-cli VMs ---
  if [ -d "$VM_CONFIG_BASE_DIR" ] && [ -n "$(ls -A "$VM_CONFIG_BASE_DIR" 2>/dev/null)" ]; then
    printf "%-25s %-12s %-10s %-8s %-10s %-10s %-15s %-10s %-10s %-12s\n" "VM NAME (bhyve-cli)" "BOOTLOADER" "AUTOSTART" "CPUS" "MEMORY" "STATUS" "PID" "CPU%" "MEM%" "UPTIME"
    _process_vm_dir "$VM_CONFIG_BASE_DIR" "bhyve-cli"
    bhyve_cli_vms_found=true
  fi

  # --- Process vm-bhyve VMs ---
  local vm_bhyve_dir
  vm_bhyve_dir=$(get_vm_bhyve_dir)

  if [ -n "$vm_bhyve_dir" ]; then
    if [ "$bhyve_cli_vms_found" = true ]; then
      echo # Add a newline for separation
    fi
    printf "%-25s %-12s %-10s %-8s %-10s %-10s %-15s %-10s %-10s %-12s\n" "VM NAME (vm-bhyve)" "BOOTLOADER" "AUTOSTART" "CPUS" "MEMORY" "STATUS" "PID" "CPU%" "MEM%" "UPTIME"
    _process_vm_dir "$vm_bhyve_dir" "vm-bhyve"
    vm_bhyve_vms_found=true
  fi

  if [ "$bhyve_cli_vms_found" = false ] && [ "$vm_bhyve_vms_found" = false ]; then
    display_and_log "INFO" "No virtual machines found."
    exit 0
  fi
  
}