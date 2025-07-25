#!/usr/local/bin/bash

# === Subcommand: info ===
cmd_info() {
  if [ -z "$1" ]; then
    cmd_info_usage
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  local STATUS_STR="Stopped"
  if is_vm_running "$VMNAME"; then
    local PID=$(get_vm_pid "$VMNAME")
    STATUS_STR="Running [$PID]"
  fi

  echo_message "----------------------------------------"
  echo_message "VM Information for '$VMNAME':"
  echo_message "----------------------------------------"
  printf "%-15s : %s\n" "Name" "$VMNAME"
  printf "%-15s : %s\n" "Status" "$STATUS_STR"
  printf "%-15s : %s\n" "CPUs" "$CPUS"
  printf "%-15s : %s\n" "Memory" "$MEMORY"
  printf "%-15s : %s\n" "Bootloader" "$BOOTLOADER_TYPE"
  printf "%-15s : %s\n" "Autostart" "$AUTOSTART"
  printf "%-15s : %s\n" "Console" "/dev/${CONSOLE}B"
  printf "%-15s : %s\n" "Log File" "$LOG_FILE"

  local NIC_IDX=0
  while true; do
    local CURRENT_TAP_VAR="TAP_${NIC_IDX}"
    local CURRENT_MAC_VAR="MAC_${NIC_IDX}"
    local CURRENT_BRIDGE_VAR="BRIDGE_${NIC_IDX}"
    local CURRENT_NIC_TYPE_VAR="NIC_${NIC_IDX}_TYPE"

    local CURRENT_TAP="${!CURRENT_TAP_VAR}"
    local CURRENT_MAC="${!CURRENT_MAC_VAR}"
    local CURRENT_BRIDGE="${!CURRENT_BRIDGE_VAR}"
    local CURRENT_NIC_TYPE="${!CURRENT_NIC_TYPE_VAR}"

    if [ -z "$CURRENT_TAP" ]; then
      break
    fi

    echo_message "Interface ${NIC_IDX} :"
    printf "    %-10s: %s\n" "TAP" "$CURRENT_TAP"
    printf "    %-10s: %s\n" "MAC" "$CURRENT_MAC"
    printf "    %-10s: %s\n" "Bridge" "$CURRENT_BRIDGE"
    printf "    %-10s: %s\n" "Type" "${CURRENT_NIC_TYPE:-virtio-net}"
    NIC_IDX=$((NIC_IDX + 1))
  done

  local DISK_IDX=0
  while true; do
    local CURRENT_DISK_VAR="DISK"
    if [ "$DISK_IDX" -gt 0 ]; then
      CURRENT_DISK_VAR="DISK_${DISK_IDX}"
    fi
    local CURRENT_DISK_FILENAME="${!CURRENT_DISK_VAR}"
    local CURRENT_DISK_TYPE_VAR="DISK_${DISK_IDX}_TYPE"
    local DISK_TYPE="${!CURRENT_DISK_TYPE_VAR:-virtio-blk}"

    if [ -z "$CURRENT_DISK_FILENAME" ]; then
      break
    fi
    
    local DISK_PATH="$VM_DIR/$CURRENT_DISK_FILENAME"

    echo_message "Disk :"
    printf "    %-10s: %s\n" "Path" "$DISK_PATH"
    
    local DISK_SIZE_BYTES=$(stat -f %z "$DISK_PATH")
    local DISK_SIZE_HUMAN=$(format_bytes "$DISK_SIZE_BYTES")
    printf "    %-10s: %s\n" "Set" "$DISK_SIZE_HUMAN"

    local ACTUAL_DISK_USAGE_KILOBYTES=$(du -k "$DISK_PATH" 2>/dev/null | awk '{print $1}')
    local ACTUAL_DISK_USAGE_BYTES=$((ACTUAL_DISK_USAGE_KILOBYTES * 1024))
    local ACTUAL_DISK_USAGE_HUMAN=$(format_bytes "$ACTUAL_DISK_USAGE_BYTES")
    printf "    %-10s: %s\n" "Used" "$ACTUAL_DISK_USAGE_HUMAN"
    printf "    %-10s: %s\n" "Type" "$DISK_TYPE"
    DISK_IDX=$((DISK_IDX + 1))
  done
  echo_message "----------------------------------------"
}