#!/usr/local/bin/bash

# === Subcommand: list ===
cmd_list() {
  

  if [ ! -d "$VM_CONFIG_BASE_DIR" ] || [ -z "$(ls -A "$VM_CONFIG_BASE_DIR")" ]; then
    display_and_log "INFO" "No virtual machines configured."
    exit 0
  fi

  printf "%-20s %-38s %-12s %-10s %-8s %-10s %-10s %-15s %-10s %-10s %-12s\n" "VM NAME" "UUID" "BOOTLOADER" "AUTOSTART" "CPUS" "MEMORY" "STATUS" "PID" "CPU%" "MEM%" "UPTIME"

  for VM_DIR_PATH in "$VM_CONFIG_BASE_DIR"/*/; do
    if [ -d "$VM_DIR_PATH" ]; then
      local VMNAME=$(basename "$VM_DIR_PATH")
      local CONF_FILE="$VM_DIR_PATH/vm.conf"
      
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

          printf "%-20s %-38s %-12s %-10s %-8s %-10s %-10s %-15s %-10s %-10s %-12s\n" \
            "$VMNAME" \
            "${UUID:-N/A}" \
            "${BOOTLOADER_TYPE:-bhyveload}" \
            "${AUTOSTART:-no}" \
            "${CPUS:-N/A}" \
            "${MEMORY:-N/A}" \
            "$STATUS" \
            "$PID" \
            "$CPU_USAGE" \
            "$MEM_USAGE" \
            "$UPTIME"
        )
      fi
    fi
  done
  echo_message "-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
  
}

