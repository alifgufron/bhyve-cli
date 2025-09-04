#!/usr/local/bin/bash

# === Subcommand: info ===
cmd_info() {
  if [ -z "$1" ]; then
    cmd_info_usage
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  local PID_STR=$(get_vm_pid "$VMNAME")
  local STATUS_STR="Stopped" # Default status

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
  printf "% -15s: %s\n" "CPUs" "$CPUS"
  printf "% -15s: %s\n" "Memory" "$MEMORY"
  printf "% -15s: %s\n" "Bootloader" "$BOOTLOADER_TYPE"
  printf "% -15s: %s\n" "Autostart" "$AUTOSTART"
  printf "% -15s: /dev/%sB\n" "Console" "$CONSOLE"
  printf "% -15s: %s\n" "Log File" "$LOG_FILE"

  local NIC_IDX=0
  while true; do
    local CURRENT_TAP_VAR="TAP_${NIC_IDX}"
    local CURRENT_MAC_VAR="MAC_${NIC_IDX}"
    local CURRENT_BRIDGE_VAR="BRIDGE_${NIC_IDX}"
    local CURRENT_NIC_TYPE_VAR="NIC_${NIC_IDX}_TYPE"

    local CURRENT_TAP="${!CURRENT_TAP_VAR}"
    
    if [ -z "$CURRENT_TAP" ]; then
      break
    fi
    
    local CURRENT_MAC="${!CURRENT_MAC_VAR}"
    local CURRENT_BRIDGE="${!CURRENT_BRIDGE_VAR}"
    local CURRENT_NIC_TYPE="${!CURRENT_NIC_TYPE_VAR:-virtio-net}"

    printf "\n"
    printf " Interface %d\n" "$NIC_IDX"
    printf "    %-10s: %s\n" "TAP" "$CURRENT_TAP"
    printf "    %-10s: %s\n" "MAC" "$CURRENT_MAC"
    printf "    %-10s: %s\n" "Bridge" "$CURRENT_BRIDGE"
    printf "    %-10s: %s\n" "Type" "$CURRENT_NIC_TYPE"
    NIC_IDX=$((NIC_IDX + 1))
  done

  local DISK_IDX=0
  while true; do
    local CURRENT_DISK_VAR="DISK"
    if [ "$DISK_IDX" -gt 0 ]; then
      CURRENT_DISK_VAR="DISK_${DISK_IDX}"
    fi
    local CURRENT_DISK_FILENAME="${!CURRENT_DISK_VAR}"
    
    if [ -z "$CURRENT_DISK_FILENAME" ]; then
      break
    fi

    local CURRENT_DISK_TYPE_VAR="DISK_${DISK_IDX}_TYPE"
    local DISK_TYPE="${!CURRENT_DISK_TYPE_VAR:-virtio-blk}"
    
    local DISK_PATH="$CURRENT_DISK_FILENAME"
    if [[ ! "$DISK_PATH" =~ ^/ ]]; then
      DISK_PATH="$VM_DIR/$CURRENT_DISK_FILENAME"
    fi

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
  printf -- "----------------------------------------\n"
}
