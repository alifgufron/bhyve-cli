#!/usr/local/bin/bash

# === Subcommand: info ===
cmd_info() {
  if [ -z "$1" ]; then
    cmd_info_usage
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

  # Parse the new format: source:datastore_name:datastore_path
  local vm_source
  local datastore_name
  local datastore_path
  vm_source=$(echo "$found_vm_info" | cut -d':' -f1)
  datastore_name=$(echo "$found_vm_info" | cut -d':' -f2)
  datastore_path=$(echo "$found_vm_info" | cut -d':' -f3)

  local vm_dir="$datastore_path/$VMNAME"

  # Load configuration based on the source
  if [ "$vm_source" == "bhyve-cli" ]; then
    load_vm_config "$VMNAME" "$vm_dir"
  else # vm-bhyve
    local conf_file="$vm_dir/$VMNAME.conf"
    if [ -f "$conf_file" ]; then
      # Source the config to get variables
      . "$conf_file"
      # Map vm-bhyve variables to our internal variables
      CPUS=${cpu:-N/A}
      MEMORY=${memory:-N/A}
      BOOTLOADER_TYPE=${loader:-bhyveload}
      AUTOSTART=${autostart:-no}
      LOG_FILE="$vm_dir/vm-bhyve.log"
      CONSOLE=${console:-nmdm1}
    else
      display_and_log "ERROR" "VM configuration for '$VMNAME' not found in vm-bhyve directory: $conf_file"
      exit 1
    fi
  fi

  # Correctly get PID using the full vm_dir path
  local PID_STR=$(get_vm_pid "$VMNAME" "$vm_dir")
  local STATUS_STR="stopped" # Default status

  if [ -n "$PID_STR" ]; then
    STATUS_STR=$(get_vm_status "$PID_STR")
  fi

  printf -- "----------------------------------------\n"
  printf " VM Information for '%s'\n" "$VMNAME"
  printf -- "----------------------------------------\n"
  printf "% -15s: %s\n" "Name" "$VMNAME"
  if [ -n "$PID_STR" ]; then
    printf "% -15s: %s (PID: %s)\n" "Status" "$STATUS_STR" "$PID_STR"
  else
    printf "% -15s: %s\n" "Status" "$STATUS_STR"
  fi
  printf "% -15s: %s (%s)\n" "Datastore" "$datastore_name" "$vm_source"
  printf "% -15s: %s\n" "CPUs" "$CPUS"
  printf "% -15s: %s\n" "Memory" "$MEMORY"
  printf "% -15s: %s\n" "Bootloader" "$BOOTLOADER_TYPE"
  printf "% -15s: %s\n" "Autostart" "$AUTOSTART"
  printf "% -15s: /dev/%sB\n" "Console" "$CONSOLE"
  printf "% -15s: %s\n" "Log File" "$LOG_FILE"

  # VNC Information
  if [ -n "$VNC_PORT" ]; then
    printf "% -15s: %s\n" "VNC Port" "$VNC_PORT"
    if [ -n "$VNC_WAIT" ]; then
      printf "% -15s: %s\n" "VNC Wait" "yes"
    fi
  fi

  # --- Display Network Info ---
  if [ "$vm_source" == "bhyve-cli" ]; then
    local NIC_IDX=0
    while true; do
      local CURRENT_BRIDGE_VAR="BRIDGE_${NIC_IDX}"
      local CURRENT_NIC_TYPE_VAR="NIC_${NIC_IDX}_TYPE"
      local CURRENT_MAC_VAR="MAC_${NIC_IDX}" # New: Read static MAC from vm.conf

      local CURRENT_BRIDGE="${!CURRENT_BRIDGE_VAR}"
      local CURRENT_NIC_TYPE="${!CURRENT_NIC_TYPE_VAR:-virtio-net}"
      local STATIC_MAC="${!CURRENT_MAC_VAR}" # Read static MAC

      if [ -z "$CURRENT_BRIDGE" ]; then break; fi

      printf "\n"
      printf " Interface %d\n" "$NIC_IDX"
      printf "    %-10s: %s\n" "Bridge" "$CURRENT_BRIDGE"
      printf "    %-10s: %s\n" "Type" "$CURRENT_NIC_TYPE"

      if [ -n "$STATIC_MAC" ]; then
        printf "    %-10s: %s\n" "MAC" "$STATIC_MAC"
      else
        printf "    %-10s: %s\n" "MAC" "(Dynamic)"
      fi

      # If VM is running, try to get live TAP info
      if [ "$STATUS_STR" == "running" ]; then
        local LIVE_TAP_NAME
        LIVE_TAP_NAME=$(ifconfig -a | grep -B 1 "description: vmnet/${VMNAME}/${NIC_IDX}/${CURRENT_BRIDGE}" | grep '^tap' | cut -d':' -f1)
        if [ -n "$LIVE_TAP_NAME" ]; then
          printf "    %-10s: %s\n" "TAP" "$LIVE_TAP_NAME"
        else
          printf "    %-10s: %s\n" "TAP" "(Not found)"
        fi
      else
        printf "    %-10s: %s\n" "TAP" "(VM stopped)"
      fi
      NIC_IDX=$((NIC_IDX + 1))
    done
  else # vm-bhyve network info
    local NIC_IDX=0
    while true; do
      local type_var="network${NIC_IDX}_type"
      local switch_var="network${NIC_IDX}_switch"
      local mac_var="network${NIC_IDX}_mac"
      local NIC_TYPE="${!type_var}"
      if [ -z "$NIC_TYPE" ]; then break; fi
      local NIC_SWITCH="${!switch_var}"
      local NIC_MAC="${!mac_var}"
      printf "\n"
      printf " Interface %d\n" "$NIC_IDX"
      printf "    %-10s: %s\n" "Type" "$NIC_TYPE"
      printf "    %-10s: %s\n" "Switch" "$NIC_SWITCH"
      printf "    %-10s: %s\n" "MAC" "$NIC_MAC"
      NIC_IDX=$((NIC_IDX + 1))
    done
  fi

  # --- Display Disk Info ---
  if [ "$vm_source" == "bhyve-cli" ]; then
    local DISK_IDX=0
    while true; do
      local CURRENT_DISK_VAR="DISK_${DISK_IDX}"
      local CURRENT_DISK_FILENAME="${!CURRENT_DISK_VAR}"
      if [ -z "$CURRENT_DISK_FILENAME" ]; then break; fi
      local CURRENT_DISK_TYPE_VAR="DISK_${DISK_IDX}_TYPE"
      local DISK_TYPE="${!CURRENT_DISK_TYPE_VAR:-virtio-blk}"
      local DISK_PATH="$CURRENT_DISK_FILENAME"
      if [[ ! "$DISK_PATH" =~ ^/ ]]; then DISK_PATH="$vm_dir/$CURRENT_DISK_FILENAME"; fi
      printf "\n"
      printf " Disk %d\n" "$DISK_IDX"
      printf "    %-10s: %s\n" "Path" "$DISK_PATH"
      if [ -f "$DISK_PATH" ]; then
        local DISK_SIZE_BYTES=$(stat -f %z "$DISK_PATH")
        local DISK_SIZE_HUMAN=$(format_bytes "$DISK_SIZE_BYTES")
        printf "    %-10s: %s\n" "Set" "$DISK_SIZE_HUMAN"
        local ACTUAL_DISK_USAGE_KILOBYTES=$(du -k "$DISK_PATH" 2>/dev/null | awk '{print $1}')
        local ACTUAL_DISK_USAGE_BYTES=$((ACTUAL_DISK_USAGE_KILOBYTES * 1024))
        local ACTUAL_DISK_USAGE_HUMAN=$(format_bytes "$ACTUAL_DISK_USAGE_BYTES")
        printf "    %-10s: %s\n" "Used" "$ACTUAL_DISK_USAGE_HUMAN"
      else
        printf "    %-10s: %s\n" "Set" "(File not found)"
        printf "    %-10s: %s\n" "Used" "(File not found)"
      fi
      printf "    %-10s: %s\n" "Type" "$DISK_TYPE"
      DISK_IDX=$((DISK_IDX + 1))
    done
  else # vm-bhyve disk info
    local DISK_IDX=0
    while true; do
      local type_var="disk${DISK_IDX}_type"
      local name_var="disk${DISK_IDX}_name"
      local DISK_TYPE="${!type_var}"
      if [ -z "$DISK_TYPE" ]; then break; fi
      local DISK_NAME="${!name_var}"
      local DISK_PATH="$vm_dir/$DISK_NAME"
      printf "\n"
      printf " Disk %d\n" "$DISK_IDX"
      printf "    %-10s: %s\n" "Path" "$DISK_PATH"
      if [ -f "$DISK_PATH" ]; then
        local DISK_SIZE_BYTES=$(stat -f %z "$DISK_PATH")
        local DISK_SIZE_HUMAN=$(format_bytes "$DISK_SIZE_BYTES")
        printf "    %-10s: %s\n" "Set" "$DISK_SIZE_HUMAN"
        local ACTUAL_DISK_USAGE_KILOBYTES=$(du -k "$DISK_PATH" 2>/dev/null | awk '{print $1}')
        local ACTUAL_DISK_USAGE_BYTES=$((ACTUAL_DISK_USAGE_KILOBYTES * 1024))
        local ACTUAL_DISK_USAGE_HUMAN=$(format_bytes "$ACTUAL_DISK_USAGE_BYTES")
        printf "    %-10s: %s\n" "Used" "$ACTUAL_DISK_USAGE_HUMAN"
      else
        printf "    %-10s: %s\n" "Set" "(File not found)"
        printf "    %-10s: %s\n" "Used" "(File not found)"
      fi
      printf "    %-10s: %s\n" "Type" "$DISK_TYPE"
      DISK_IDX=$((DISK_IDX + 1))
    done
  fi
  printf -- "----------------------------------------\n"
}
