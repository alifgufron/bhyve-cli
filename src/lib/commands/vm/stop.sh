#!/usr/local/bin/bash

# === Subcommand: stop ===
cmd_stop() {
  log "Entering cmd_stop function for VM: $1"
  if [ -z "$1" ]; then
    cmd_stop_usage
    exit 1
  fi

  local VMNAME_ARG=$1
  local FORCE_STOP=false
  local SILENT_MODE=false

  # Parse arguments for --force and --silent
  local ARGS=()
  for arg in "$@"; do
    if [[ "$arg" == "--force" ]]; then
      FORCE_STOP=true
    elif [[ "$arg" == "--silent" ]]; then
      SILENT_MODE=true
    else
      ARGS+=("$arg")
    fi
  done

  # Ensure VMNAME is set from ARGS
  if [ -z "$VMNAME_ARG" ] && [ ${#ARGS[@]} -gt 0 ]; then
    VMNAME_ARG="${ARGS[0]}"
  fi

  if [ -z "$VMNAME_ARG" ]; then
    cmd_stop_usage
    exit 1
  fi

  local found_vm_info
  found_vm_info=$(find_any_vm "$VMNAME_ARG")

  if [ -z "$found_vm_info" ]; then
    display_and_log "ERROR" "VM '$VMNAME_ARG' not found in any bhyve-cli or vm-bhyve datastores."
    exit 1
  fi

  # Parse the new format: source:datastore_name:datastore_path
  local vm_source
  local vm_datastore_name
  local datastore_path
  vm_source=$(echo "$found_vm_info" | cut -d':' -f1)
  vm_datastore_name=$(echo "$found_vm_info" | cut -d':' -f2)
  datastore_path=$(echo "$found_vm_info" | cut -d':' -f3)

  # Delegate to vm-bhyve if applicable
  if [ "$vm_source" == "vm-bhyve" ]; then
    if ! command -v vm >/dev/null 2>&1; then
      display_and_log "ERROR" "'vm-bhyve' command not found. Please ensure it is installed and in your PATH."
      exit 1
    fi
    display_and_log "INFO" "Delegating stop command to vm-bhyve for VM '$VMNAME_ARG'..."
    vm stop "$VMNAME_ARG"
    exit $?
  fi

  # If we are here, it's a bhyve-cli VM. Proceed with corrected logic.
  # Load VM config using the found datastore_path. This sets the global VM_DIR.
  load_vm_config "$VMNAME_ARG" "$datastore_path"

  # is_vm_running and other pid functions require the full VM_DIR path.
  if ! is_vm_running "$VMNAME_ARG" "$VM_DIR"; then
    display_and_log "INFO" "VM '$VMNAME_ARG' is not running."
    log "Exiting cmd_stop function for VM: $VMNAME_ARG"
    exit 0
  fi

  if [ "$SILENT_MODE" = false ]; then
    start_spinner "Stopping VM '$VMNAME'..."
  fi

  if [ "$FORCE_STOP" = true ]; then
    log "Force stopping VM '$VMNAME'..."
    if $BHYVECTL --vm="$VMNAME" --force-reset > /dev/null 2>&1; then
      log "VM '$VMNAME' forcefully reset."
    else
      log "WARNING: Failed to forcefully reset VM '$VMNAME'. Attempting kill."
      local PID_TO_KILL=$(get_vm_pid "$VMNAME_ARG" "$VM_DIR")
      if [ -n "$PID_TO_KILL" ]; then
        kill -9 "$PID_TO_KILL" > /dev/null 2>&1
        log "Sent KILL signal to PID $PID_TO_KILL."
      fi
    fi
  else
    log "Attempting graceful shutdown for VM '$VMNAME'..."
    local PID_TO_KILL=$(get_vm_pid "$VMNAME_ARG" "$VM_DIR")
    if [ -n "$PID_TO_KILL" ]; then
      kill "$PID_TO_KILL" > /dev/null 2>&1
      log "Sent TERM signal to PID $PID_TO_KILL."
      sleep 15 # Give VM time to shut down gracefully (increased from 5s)
      if is_vm_running "$VMNAME" "$VM_DIR"; then
        display_and_log "WARNING" "VM '$VMNAME' did not shut down gracefully. Force stopping..."
        if $BHYVECTL --vm="$VMNAME" --force-reset > /dev/null 2>&1; then
          log "VM '$VMNAME' forcefully reset."
        else
          log "WARNING: Failed to forcefully reset VM '$VMNAME'. Attempting kill."
          kill -9 "$PID_TO_KILL" > /dev/null 2>&1
          log "Sent KILL signal to PID $PID_TO_KILL."
        fi
      fi
    fi
  fi

  # Ensure VM is destroyed from kernel memory and PID file is removed
  if $BHYVECTL --vm="$VMNAME" --destroy > /dev/null 2>&1; then
    log "VM '$VMNAME' successfully destroyed from kernel memory."
  else
    log "VM '$VMNAME' was not found in kernel memory (already destroyed or never started)."
  fi
  delete_vm_pid "$VMNAME_ARG" "$VM_DIR"
  cleanup_vm_network_interfaces "$VMNAME"
  set_vm_status "$VMNAME" "stopped"

  if [ "$SILENT_MODE" = "false" ]; then
    display_and_log "INFO" "VM '$VMNAME' stopped successfully."
  fi
  log "Exiting cmd_stop function for VM: $VMNAME"
}