#!/usr/local/bin/bash

# === Subcommand: resume ===
cmd_resume() {
  if [ -z "$1" ]; then
    cmd_resume_usage # This usage function will need to be created in lib/usage/vm.sh
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  local pid=$(get_vm_pid "$VMNAME")
  if [ -z "$pid" ]; then
    display_and_log "ERROR" "VM '$VMNAME' is not running or suspended. Cannot resume."
    exit 1
  fi

  local current_status
  current_status=$(get_vm_status "$pid")

  if [ "$current_status" != "suspended" ]; then
      display_and_log "ERROR" "VM '$VMNAME' is not suspended. Current status: $current_status."
      exit 1
  fi

  display_and_log "INFO" "Resuming VM '$VMNAME' (PID: $pid)..."
  if kill -SIGCONT "$pid"; then
    set_vm_status "$VMNAME" "running"
    display_and_log "INFO" "VM '$VMNAME' resumed successfully."
  else
    display_and_log "ERROR" "Failed to resume VM '$VMNAME'."
    exit 1
  fi
}