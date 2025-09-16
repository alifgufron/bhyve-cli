#!/usr/local/bin/bash

# === Helper function to check if a VM is running (i.e., not suspended or stopped) ===
is_vm_running() {
  local VMNAME_CHECK="$1"
  local VM_DIR_CHECK="$2"
  local pid=$(get_vm_pid "$VMNAME_CHECK" "$VM_DIR_CHECK")
  if [ -n "$pid" ]; then
    local status=$(get_vm_status "$pid")
    if [ "$status" == "running" ]; then
      return 0 # Running
    fi
  fi
  return 1 # Not running (stopped or suspended)
}

# === Helper functions for VM PID file management ===
get_vm_pid() {
  local VMNAME_GET_PID="$1"
  local VM_DIR_GET_PID="$2"
  local PID=""
  if [ -f "${VM_DIR_GET_PID}vm.pid" ]; then
    PID=$(cat "${VM_DIR_GET_PID}vm.pid")
    if [ -n "$PID" ] && ps -p "$PID" > /dev/null 2>&1; then
      echo "$PID"
      return 0
    fi
  fi
  # Fallback to pgrep if vm.pid is not found or invalid
  PID=$(pgrep -f "bhyve: [[:<:]]$VMNAME_GET_PID.*")
  if [ -n "$PID" ] && ps -p "$PID" > /dev/null 2>&1; then
    echo "$PID"
    return 0
  fi
  return 1 # PID not found
}

save_vm_pid() {
  local VMNAME_SAVE_PID="$1"
  local PID_TO_SAVE="$2"
  local VM_DIR_SAVE_PID="$3"
  echo "$PID_TO_SAVE" > "${VM_DIR_SAVE_PID}vm.pid"
}

delete_vm_pid() {
  local VMNAME_DELETE_PID="$1"
  local VM_DIR_DELETE_PID="$2"
  if [ -f "${VM_DIR_DELETE_PID}vm.pid" ]; then
    rm "${VM_DIR_DELETE_PID}vm.pid"
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

    if [[ "$process_status" == "T" || "$process_status" == "TC" ]]; then
        echo "suspended"
    elif [ -n "$process_status" ]; then
        echo "running"
    else
        echo "stopped"
    fi
}

# Function to set the VM status (currently a placeholder)
set_vm_status() {
  local VMNAME_SET_STATUS="$1"
  local STATUS_TO_SET="$2"
  log "Attempted to set VM '$VMNAME_SET_STATUS' status to '$STATUS_TO_SET'. (Function is a placeholder)"
}