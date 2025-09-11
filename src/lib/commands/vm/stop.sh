#!/usr/local/bin/bash

# === Subcommand: stop ===
cmd_stop() {
  log "Entering cmd_stop function for VM: $1"
  if [ -z "$1" ]; then
    cmd_stop_usage
    exit 1
  fi

  local VMNAME_ARG=$1

  # Detect VM source
  local vm_source=""
  if [ -d "$VM_CONFIG_BASE_DIR/$VMNAME_ARG" ]; then
    vm_source="bhyve-cli"
  else
    local vm_bhyve_base_dir
    vm_bhyve_base_dir=$(get_vm_bhyve_dir)
    if [ -n "$vm_bhyve_base_dir" ] && [ -d "$vm_bhyve_base_dir/$VMNAME_ARG" ]; then
      vm_source="vm-bhyve"
    fi
  fi

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

  # If we are here, it's a bhyve-cli VM. Proceed with original logic.

  local VMNAME="$1"
  local FORCE_STOP=false
  local SILENT_MODE=false

  # Parse arguments
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
  if [ -z "$VMNAME" ] && [ ${#ARGS[@]} -gt 0 ]; then
    VMNAME="${ARGS[0]}"
  fi

  load_vm_config "$VMNAME"

  if ! is_vm_running "$VMNAME"; then
    display_and_log "INFO" "VM '$VMNAME' is not running."
    log "Exiting cmd_stop function for VM: $VMNAME"
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
      local PID_TO_KILL=$(get_vm_pid "$VMNAME")
      if [ -n "$PID_TO_KILL" ]; then
        kill -9 "$PID_TO_KILL" > /dev/null 2>&1
        log "Sent KILL signal to PID $PID_TO_KILL."
      fi
    fi
  else
    log "Attempting graceful shutdown for VM '$VMNAME'..."
    local PID_TO_KILL=$(get_vm_pid "$VMNAME")
    if [ -n "$PID_TO_KILL" ]; then
      kill "$PID_TO_KILL" > /dev/null 2>&1
      log "Sent TERM signal to PID $PID_TO_KILL."
      sleep 15 # Give VM time to shut down gracefully (increased from 5s)
      if is_vm_running "$VMNAME"; then
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
  delete_vm_pid "$VMNAME"
  cleanup_vm_network_interfaces "$VMNAME"
  set_vm_status "$VMNAME" "stopped"

  if [ "$SILENT_MODE" = "false" ]; then
    display_and_log "INFO" "VM '$VMNAME' stopped successfully."
  fi
  log "Exiting cmd_stop function for VM: $VMNAME"
}
