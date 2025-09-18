#!/usr/local/bin/bash

# === Subcommand: start ===
cmd_start() {
  log "Entering cmd_start for VM: $1"
  local VMNAME_ARG="$1"
  local CONNECT_TO_CONSOLE=false
  local QUIET_BOOTLOADER=true
  local SUPPRESS_CONSOLE_MESSAGE=false

  # --- Argument Parsing ---
  shift # Remove vm name
  while (( "$#" )); do
    case "$1" in
      --console)
        CONNECT_TO_CONSOLE=true
        QUIET_BOOTLOADER=false
        ;;
      --suppress-console-message)
        SUPPRESS_CONSOLE_MESSAGE=true
        ;;
      *)
        display_and_log "ERROR" "Invalid option for start: $1"
        cmd_start_usage
        exit 1
        ;;
    esac
    shift
  done

  if [ -z "$VMNAME_ARG" ]; then
    cmd_start_usage
    exit 1
  fi

  # --- VM Discovery and Validation ---
  local found_vm_info
  found_vm_info=$(find_any_vm "$VMNAME_ARG")
  if [ -z "$found_vm_info" ]; then
    display_and_log "ERROR" "VM '$VMNAME_ARG' not found."
    exit 1
  fi

  local vm_source datastore_path
  vm_source=$(echo "$found_vm_info" | cut -d':' -f1)
  datastore_path=$(echo "$found_vm_info" | cut -d':' -f3)
  local VM_DIR="$datastore_path/$VMNAME_ARG"

  if [ "$vm_source" == "vm-bhyve" ]; then
    display_and_log "INFO" "Delegating start to vm-bhyve for '$VMNAME_ARG'..."
    vm start "$VMNAME_ARG"
    exit $?
  fi

  load_vm_config "$VMNAME_ARG" "$VM_DIR"

  if is_vm_running "$VMNAME" "$VM_DIR"; then
    display_and_log "INFO" "VM '$VMNAME' is already running."
    if [ "$CONNECT_TO_CONSOLE" = true ]; then
      cmd_console "$VMNAME"
    fi
    exit 0
  fi

  # --- Installation Check ---
  local DISK0_PATH
  if [[ ! "$DISK_0" =~ ^/ ]]; then DISK0_PATH="$VM_DIR/$DISK_0"; else DISK0_PATH="$DISK_0"; fi
  if [ ! -f "$DISK0_PATH" ]; then
    display_and_log "ERROR" "VM disk image not found at '$DISK0_PATH'."
    exit 1
  fi
  local ACTUAL_DISK_USAGE_KB
  ACTUAL_DISK_USAGE_KB=$(du -k "$DISK0_PATH" | awk '{print $1}')
  if (( ACTUAL_DISK_USAGE_KB < 10240 )); then # 10MB threshold
    display_and_log "ERROR" "VM '$VMNAME' appears to be uninstalled. Please run '$(basename $0) vm install $VMNAME' first."
    exit 1
  fi

  [ "$SUPPRESS_CONSOLE_MESSAGE" = false ] && start_spinner "Starting VM '$VMNAME'..."

  display_and_log "INFO" "Preparing to start VM '$VMNAME_ARG'..."
  # --- Pre-start Cleanup ---
  cleanup_vm_network_interfaces "$VMNAME"
  $BHYVECTL --vm="$VMNAME" --destroy > /dev/null 2>&1
  log "Ensured VM '$VMNAME' is destroyed from kernel before start."

  # --- Build bhyve Arguments ---
  local DISK_ARGS NETWORK_ARGS VNC_ARGS BHYVE_LOADER_ARG
  DISK_ARGS=$(build_disk_args "$VM_DIR") || { stop_spinner; display_and_log "ERROR" "Failed to build disk arguments."; exit 1; }
  NETWORK_ARGS=$(build_network_args "$VMNAME" "$VM_DIR") || { stop_spinner; display_and_log "ERROR" "Failed to build network arguments."; exit 1; }
  VNC_ARGS=$(build_vnc_args) # This one is optional, no need to exit on failure
  BHYVE_LOADER_ARG=$(get_bootloader_arg "$BOOTLOADER_TYPE" "$VM_DIR") || { stop_spinner; display_and_log "ERROR" "Failed to get bootloader arguments."; exit 1; }

  # --- Bhyveload Boot ---
  if [ "$BOOTLOADER_TYPE" = "bhyveload" ]; then
    ensure_nmdm_device_nodes "$CONSOLE"
    sleep 1
    run_bhyveload "$DISK0_PATH" "$QUIET_BOOTLOADER" || {
      [ "$SUPPRESS_CONSOLE_MESSAGE" = false ] && stop_spinner
      display_and_log "ERROR" "bhyveload failed. Check VM logs."
      exit 1
    }
  fi

  # --- Execute Bhyve ---
  local BHYVE_CMD="$BHYVE -c $CPUS -m $MEMORY -AHP -s 0,hostbridge $DISK_ARGS $NETWORK_ARGS $VNC_ARGS -l com1,/dev/${CONSOLE}A -s 31,lpc $BHYVE_LOADER_ARG \"$VMNAME\""
  log "Executing bhyve command: $BHYVE_CMD"

  eval "$BHYVE_CMD >> \"$LOG_FILE\" 2>&1" &

  sleep 1 # Give bhyve a moment to spawn

  # --- Post-start Verification ---
  local BHYVE_PID
  BHYVE_PID=$(pgrep -f "bhyve: $VMNAME")
  if [ -z "$BHYVE_PID" ]; then
    [ "$SUPPRESS_CONSOLE_MESSAGE" = false ] && stop_spinner
    display_and_log "ERROR" "Failed to start VM '$VMNAME'. Bhyve process exited prematurely. Check logs."
    $BHYVECTL --vm="$VMNAME" --destroy > /dev/null 2>&1
    exit 1
  fi

  save_vm_pid "$VMNAME" "$BHYVE_PID" "$VM_DIR"
  log "VM '$VMNAME' started with PID $BHYVE_PID."

  [ "$SUPPRESS_CONSOLE_MESSAGE" = false ] && stop_spinner && display_and_log "INFO" "VM '$VMNAME' started successfully."

  if [ "$CONNECT_TO_CONSOLE" = true ]; then
    cmd_console "$VMNAME"
  elif [ "$SUPPRESS_CONSOLE_MESSAGE" = false ]; then
    echo_message "To connect to the console, run: $(basename $0) vm console $VMNAME"
  fi

  log "Exiting cmd_start for VM: $VMNAME"
}
