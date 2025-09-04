#!/usr/local/bin/bash

# === Subcommand: suspend ===
cmd_suspend() {
  if [ -z "$1" ]; then
    cmd_suspend_usage
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  local pid=$(get_vm_pid "$VMNAME")
  if [ -z "$pid" ]; then
    display_and_log "ERROR" "VM '$VMNAME' is not running. Cannot suspend."
    exit 1
  fi

  display_and_log "INFO" "Suspending VM '$VMNAME' (PID: $pid)..."
  if kill -SIGSTOP "$pid"; then
    set_vm_status "$VMNAME" "suspended"
    display_and_log "INFO" "VM '$VMNAME' suspended successfully."
  else
    display_and_log "ERROR" "Failed to suspend VM '$VMNAME'."
    exit 1
  fi
}
