#!/usr/local/bin/bash

# === Helper function to check if a VM is running ===
is_vm_running() {
  local VMNAME_CHECK="$1"
  get_vm_pid "$VMNAME_CHECK" > /dev/null
  return $?
}

# === Helper functions for VM PID file management ===
get_vm_pid() {
  local VMNAME_GET_PID="$1"
  local VM_DIR_GET_PID="$VM_CONFIG_BASE_DIR/$VMNAME_GET_PID"
  local PID=""
  if [ -f "$VM_DIR_GET_PID/vm.pid" ]; then
    PID=$(cat "$VM_DIR_GET_PID/vm.pid")
    if [ -n "$PID" ] && ps -p "$PID" > /dev/null 2>&1; then
      echo "$PID"
      return 0
    fi
  fi
  # Fallback to pgrep if vm.pid is not found or invalid
  PID=$(pgrep -f "bhyve: $VMNAME_GET_PID")
  if [ -n "$PID" ] && ps -p "$PID" > /dev/null 2>&1; then
    echo "$PID"
    return 0
  fi
  return 1 # PID not found
}

save_vm_pid() {
  local VMNAME_SAVE_PID="$1"
  local PID_TO_SAVE="$2"
  local VM_DIR_SAVE_PID="$VM_CONFIG_BASE_DIR/$VMNAME_SAVE_PID"
  echo "$PID_TO_SAVE" > "$VM_DIR_SAVE_PID/vm.pid"
}

delete_vm_pid() {
  local VMNAME_DELETE_PID="$1"
  local VM_DIR_DELETE_PID="$VM_CONFIG_BASE_DIR/$VMNAME_DELETE_PID"
  if [ -f "$VM_DIR_DELETE_PID/vm.pid" ]; then
    rm "$VM_DIR_DELETE_PID/vm.pid"
  fi
}

# Function to get the detailed status of a VM process (running, suspended, or stopped)
get_vm_status() {
    local pid="$1"
    local process_status

    if [ -z "$pid" ]; then
        echo "stopped"
        return
    fi

    # Get the state of the process
    # -o state= -> get only the state column, with no header
    process_status=$(ps -p "$pid" -o state= 2>/dev/null)

    if [[ "$process_status" == "T" ]]; then
        echo "suspended"
    elif [ -n "$process_status" ]; then
        echo "running"
    else
        echo "stopped"
    fi
}