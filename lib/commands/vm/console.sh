#!/usr/local/bin/bash

# === Subcommand: console ===
cmd_console() {
  
  if [ -z "$1" ]; then
    cmd_console_usage
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  if ! is_vm_running "$VMNAME"; then
    display_and_log "ERROR" "VM '$VMNAME' is not running."
    exit 1
  fi

  local vm_status=$(get_vm_status "$VMNAME")
  if [ "$vm_status" = "suspended" ]; then
    display_and_log "WARNING" "VM '$VMNAME' is suspended and cannot be accessed via console. Please resume it first."
    exit 1
  fi

  echo_message ">>> Connecting to console for VM '$VMNAME'. Type ~. to exit."
  cu -l /dev/"${CONSOLE}B" -s 115200
  
}
