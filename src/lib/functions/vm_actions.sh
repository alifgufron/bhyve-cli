#!/usr/local/bin/bash

run_bhyveload() {
  local DATA_PATH="$1"
  local QUIET_LOAD="${2:-false}" # New optional parameter

  if [ "$QUIET_LOAD" = true ]; then
    log "Loading kernel via bhyveload (quiet mode)..."
    $BHYVELOAD -m "$MEMORY" -d "$DATA_PATH" -c stdio "$VMNAME" > /dev/null 2>&1
  else
    display_and_log "INFO" "Loading kernel via bhyveload..."
    $BHYVELOAD -m "$MEMORY" -d "$DATA_PATH" -c stdio "$VMNAME"
  fi
  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo_message "[ERROR] bhyveload failed with exit code $exit_code. Cannot proceed."
    $BHYVECTL --vm="$VMNAME" --destroy > /dev/null 2>&1
    return 1
  fi
  log "bhyveload completed successfully."
  return 0
}

cleanup_vm_processes() {
  log "Entering cleanup_vm_processes for VM: $VM_NAME_CLEANUP"

  # Explicitly kill bhyve process associated with this VMNAME
  local VM_PIDS_TO_KILL
  VM_PIDS_TO_KILL=$(get_vm_pid "$VM_NAME_CLEANUP")
  if [ -n "$VM_PIDS_TO_KILL" ]; then
      local PIDS_STRING
  PIDS_STRING=$(echo "$VM_PIDS_TO_KILL" | tr '
' ' ')
      log "Sending TERM signal to bhyve PID(s): $PIDS_STRING"
      kill $VM_PIDS_TO_KILL
      sleep 1 # Give it a moment to terminate

      for pid_to_check in $VM_PIDS_TO_KILL; do
          if ps -p "$pid_to_check" > /dev/null 2>&1; then
              log "PID $pid_to_check still running, forcing KILL..."
              kill -9 "$pid_to_check"
              sleep 1
          fi
      done
      log "bhyve process(es) stopped."
  else
      log "No bhyve process found for '$VM_NAME_CLEANUP' to kill."
  fi

  # Now, destroy from kernel memory
  if $BHYVECTL --vm="$VM_NAME_CLEANUP" --destroy > /dev/null 2>&1; then
      log "VM '$VM_NAME_CLEANUP' successfully destroyed from kernel memory."
  else
      log "VM '$VM_NAME_CLEANUP' was not found in kernel memory (already destroyed or never started)."
  fi

  # Kill any lingering cu or tail -f processes
  log "Attempting to stop associated cu processes for /dev/${CONSOLE_DEVICE_CLEANUP}B and /dev/${CONSOLE_DEVICE_CLEANUP}A..."
  pkill -f "cu -l /dev/${CONSOLE_DEVICE_CLEANUP}B" > /dev/null 2>&1
  pkill -f "cu -l /dev/${CONSOLE_DEVICE_CLEANUP}A" > /dev/null 2>&1

  # Only kill tail -f process if it's not the global log file and is not empty
  if [ -n "$LOG_FILE_CLEANUP" ] && [ "$LOG_FILE_CLEANUP" != "$GLOBAL_LOG_FILE" ]; then
    log "Attempting to stop associated tail -f process for $LOG_FILE_CLEANUP..."
    pkill -f "tail -f $LOG_FILE_CLEANUP" > /dev/null 2>&1
  else
    log "Skipping termination of tail -f for global log file or empty log path: $LOG_FILE_CLEANUP."
  fi
  log "Exiting cleanup_vm_processes for VM: $VM_NAME_CLEANUP"
}

ensure_nmdm_device_nodes() {
  local CONSOLE_DEVICE="$1"
  if [ ! -e "/dev/${CONSOLE_DEVICE}A" ]; then
    log "Creating nmdm device node /dev/${CONSOLE_DEVICE}A"
    mknod "/dev/${CONSOLE_DEVICE}A" c 106 0
    local MKNOD_A_EXIT_CODE=$?
    if [ $MKNOD_A_EXIT_CODE -ne 0 ]; then
      display_and_log "ERROR" "Failed to create /dev/${CONSOLE_DEVICE}A (mknod exit code: $MKNOD_A_EXIT_CODE)"; exit 1;
    fi
    chmod 660 "/dev/${CONSOLE_DEVICE}A"
    local CHMOD_A_EXIT_CODE=$?
    if [ $CHMOD_A_EXIT_CODE -ne 0 ]; then
      display_and_log "ERROR" "Failed to set permissions for /dev/${CONSOLE_DEVICE}A (chmod exit code: $CHMOD_A_EXIT_CODE)"; exit 1;
    fi
    log "Created /dev/${CONSOLE_DEVICE}A. Permissions: $(stat -f "%Sp" "/dev/${CONSOLE_DEVICE}A")"
  fi
  if [ ! -e "/dev/${CONSOLE_DEVICE}B" ]; then
    log "Creating nmdm device node /dev/${CONSOLE_DEVICE}B"
    mknod "/dev/${CONSOLE_DEVICE}B" c 106 1
    local MKNOD_B_EXIT_CODE=$?
    if [ $MKNOD_B_EXIT_CODE -ne 0 ]; then
      display_and_log "ERROR" "Failed to create /dev/${CONSOLE_DEVICE}B (mknod exit code: $MKNOD_B_EXIT_CODE)"; exit 1;
    fi
    chmod 660 "/dev/${CONSOLE_DEVICE}B"
    local CHMOD_B_EXIT_CODE=$?
    if [ $CHMOD_B_EXIT_CODE -ne 0 ]; then
      display_and_log "ERROR" "Failed to set permissions for /dev/${CONSOLE_DEVICE}B (chmod exit code: $CHMOD_B_EXIT_CODE)"; exit 1;
    fi
    log "Created /dev/${CONSOLE_DEVICE}B. Permissions: $(stat -f "%Sp" "/dev/${CONSOLE_DEVICE}B")"
  fi
}

# === Helper function to wait for a VM to reach a specific status ===
wait_for_vm_status() {
  local VMNAME_WAIT="$1"
  local TARGET_STATUS="$2"
  local TIMEOUT=${3:-60} # Default timeout of 60 seconds
  local INTERVAL=${4:-1} # Default check interval of 1 second
  local ELAPSED_TIME=0

  display_and_log "INFO" "Waiting for VM '$VMNAME_WAIT' to become '$TARGET_STATUS' (timeout: ${TIMEOUT}s)..."

  while [ "$ELAPSED_TIME" -lt "$TIMEOUT" ]; do
    local pid=$(get_vm_pid "$VMNAME_WAIT")
    local current_status=$(get_vm_status "$pid")

    if [ "$current_status" == "$TARGET_STATUS" ]; then
      display_and_log "INFO" "VM '$VMNAME_WAIT' is now '$TARGET_STATUS'."
      return 0 # Success
    fi

    sleep "$INTERVAL"
    ELAPSED_TIME=$((ELAPSED_TIME + INTERVAL))
  done

  display_and_log "ERROR" "Timeout waiting for VM '$VMNAME_WAIT' to become '$TARGET_STATUS'. Current status: '$current_status'."
  return 1 # Timeout
}