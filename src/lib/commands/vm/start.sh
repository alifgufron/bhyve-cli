#!/usr/local/bin/bash

# === Subcommand: start ===
cmd_start() {
  log "Entering cmd_start function for VM: $1"
  if [ -z "$1" ]; then
    cmd_start_usage
    exit 1
  fi

  local VMNAME="$1"
  local CONNECT_TO_CONSOLE=false
  local QUIET_BOOTLOADER=true # Default to quiet bootloader (no console)
  local SUPPRESS_CONSOLE_MESSAGE=false # New flag to suppress console message

  # Parse arguments
  local ARGS=()
  for arg in "$@"; do
    if [[ "$arg" == "--console" ]]; then
      CONNECT_TO_CONSOLE=true
      QUIET_BOOTLOADER=false # Show bootloader output if console is requested
    elif [[ "$arg" == "--suppress-console-message" ]]; then
      SUPPRESS_CONSOLE_MESSAGE=true
    else
      ARGS+=("$arg")
    fi
  done

  # Ensure VMNAME is set from ARGS
  if [ -z "$VMNAME" ] && [ ${#ARGS[@]} -gt 0 ]; then
    VMNAME="${ARGS[0]}"
  fi

  if [ -z "$VMNAME" ]; then
    cmd_start_usage
    exit 1
  fi

  load_vm_config "$VMNAME"

  # Check if VM is installed (disk size check)
  local DISK_PATH="$VM_DIR/$DISK"
  if [ ! -f "$DISK_PATH" ]; then
    display_and_log "ERROR" "VM disk image not found at '$DISK_PATH'. Cannot start."
    exit 1
  fi

  local ACTUAL_DISK_USAGE_KB=$(du -k "$DISK_PATH" | awk '{print $1}')
  local MIN_INSTALLED_DISK_SIZE_KB=10240 # 10MB threshold

  if (( ACTUAL_DISK_USAGE_KB < MIN_INSTALLED_DISK_SIZE_KB )); then
    display_and_log "ERROR" "VM '$VMNAME' appears to be uninstalled (either uninstalled or not yet installed). Please run './bhyve-cli.sh install $VMNAME' first."
    exit 1
  fi

  # Check if VM is already running
  if is_vm_running "$VMNAME"; then
    display_and_log "INFO" "VM '$VMNAME' is already running."
    if [ "$CONNECT_TO_CONSOLE" = true ]; then
      display_and_log "INFO" "Connecting to console..."
      cmd_console "$VMNAME"
    fi
    exit 0
  fi

  if [ "$SUPPRESS_CONSOLE_MESSAGE" = false ]; then
    start_spinner "Starting VM '$VMNAME'..."
  fi
  # Ensure VM is destroyed from kernel memory before attempting to start
  log "Attempting to destroy VM '$VMNAME' from kernel memory before start..."
  $BHYVECTL --vm="$VMNAME" --destroy > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    log "VM '$VMNAME' successfully destroyed from kernel memory (if it existed)."
  else
    log "VM '$VMNAME' was not found in kernel memory or destroy failed (this might be normal if it was already stopped)."
  fi
  log "Loading VM configuration for '$VMNAME'...";
  log "VM Name: $VMNAME"
  log "CPUs: $CPUS"
  log "Memory: $MEMORY"
  local DISK_ARGS_AND_NEXT_DEV
  DISK_ARGS_AND_NEXT_DEV=$(build_disk_args "$VM_DIR")
  local DISK_ARGS=$(echo "$DISK_ARGS_AND_NEXT_DEV" | head -n 1)
  local NEXT_DISK_DEV_NUM=$(echo "$DISK_ARGS_AND_NEXT_DEV" | tail -n 1)
  if [ $? -ne 0 ]; then
    stop_spinner
    display_and_log "ERROR" "Failed to build disk arguments. Check VM logs for details."
    exit 1
  fi

  local NETWORK_ARGS=$(build_network_args "$VMNAME" "$VM_DIR")
  if [ $? -ne 0 ]; then
    stop_spinner
    display_and_log "ERROR" "Failed to build network arguments. Check VM logs for details."
    exit 1
  fi

  local VNC_ARGS=""
  if [ -n "$VNC_PORT" ]; then
    VNC_ARGS="-s ${NEXT_DISK_DEV_NUM},vnc=${VNC_PORT}"
    if [ "$VNC_WAIT" = "yes" ]; then
      VNC_ARGS+=",wait"
    fi
    log "VNC arguments: $VNC_ARGS"
  fi

  local BHYVE_CMD_COMMON_ARGS="$BHYVE -c $CPUS -m $MEMORY -AHP -s 0,hostbridge $DISK_ARGS $NETWORK_ARGS ${VNC_ARGS}"

  # === Start Logic ===
  if [ "$BOOTLOADER_TYPE" = "bhyveload" ]; then
    log "Preparing for bhyveload start..."
    ensure_nmdm_device_nodes "$CONSOLE"
    sleep 1 # Give nmdm devices a moment to be ready
    
    log "Verifying nmdm device nodes:"
    if [ -e "/dev/${CONSOLE}A" ]; then
      log "/dev/${CONSOLE}A exists with permissions: $(stat -f "%Sp" /dev/${CONSOLE}A)"
    else
      stop_spinner
      display_and_log "ERROR" "/dev/${CONSOLE}A does NOT exist! Please ensure the VM has been run at least once, or the device has been created."
      exit 1
    fi
    if [ -e "/dev/${CONSOLE}B" ]; then
      log "/dev/${CONSOLE}B exists with permissions: $(stat -f "%Sp" /dev/${CONSOLE}B)"
    else
      stop_spinner
      display_and_log "ERROR" "/dev/${CONSOLE}B does NOT exist! Please ensure the VM has been run at least once, or the device has been created."
      exit 1
    fi

    run_bhyveload "$VM_DIR/$DISK" "$QUIET_BOOTLOADER" || {
      stop_spinner
      display_and_log "ERROR" "bhyveload failed. Check VM logs for details."
      exit 1
    }

    local BHYVE_CMD_COMMON_ARGS="$BHYVE -c $CPUS -m $MEMORY -AHP -s 0,hostbridge $DISK_ARGS $NETWORK_ARGS ${VNC_ARGS}"
    local BHYVE_CMD="${BHYVE_CMD_COMMON_ARGS} -l com1,/dev/${CONSOLE}A -s 31,lpc ${BHYVE_LOADER_CLI_ARG} \"$VMNAME\""
    log "Executing bhyve command: $BHYVE_CMD"
    log_to_global_file "INFO" "Starting bhyve VM with command: $BHYVE_CMD"
    # Execute bhyve command and capture its output and exit code
    local BHYVE_EXEC_OUTPUT
    local BHYVE_EXEC_EXIT_CODE
    BHYVE_EXEC_OUTPUT=$(eval "$BHYVE_CMD" >> "$LOG_FILE" 2>&1 & echo $!)
    BHYVE_EXEC_EXIT_CODE=$?
    log "Bhyve command executed. PID: $BHYVE_EXEC_OUTPUT, Exit Code: $BHYVE_EXEC_EXIT_CODE"
    log_to_global_file "INFO" "Bhyve command execution result: PID=$BHYVE_EXEC_OUTPUT, ExitCode=$BHYVE_EXEC_EXIT_CODE"
    # Give bhyve a moment to start and register its process
    sleep 0.5
    # Find the actual bhyve process PID
    BHYVE_PID=$(pgrep -f "bhyve: [[:<:]]$VMNAME.*")
    if [ -z "$BHYVE_PID" ]; then
        log_to_global_file "ERROR" "Could not find bhyve PID for $VMNAME after start attempt."
        if [ "$SUPPRESS_CONSOLE_MESSAGE" = false ]; then
            stop_spinner
        fi
        display_and_log "ERROR" "Failed to start VM '$VMNAME'. Could not find bhyve process PID."
        exit 1
    fi
    save_vm_pid "$VMNAME" "$BHYVE_PID"

    # Wait briefly for bhyve to start or fail
    sleep 1
    if ! is_vm_running "$VMNAME"; then
      if [ "$SUPPRESS_CONSOLE_MESSAGE" = false ]; then
        stop_spinner
      fi
      log_to_global_file "ERROR" "bhyve process for $VMNAME exited prematurely. Check vm.log for details."
      display_and_log "ERROR" "Failed to start VM '$VMNAME'. Bhyve process exited prematurely. Check VM logs for details."
      delete_vm_pid "$VMNAME"
      $BHYVECTL --vm="$VMNAME" --destroy > /dev/null 2>&1
      exit 1
    fi

    if [ "$SUPPRESS_CONSOLE_MESSAGE" = false ]; then
      stop_spinner
      echo_message "VM '$VMNAME' started successfully."
    fi
    set_vm_status "$VMNAME" "running"
    if [ "$CONNECT_TO_CONSOLE" = true ]; then
      echo_message ">>> Entering VM '$VMNAME' console (exit with ~.)"
      cu -l /dev/"${CONSOLE}B"
      log "cu session ended."
    elif [ "$SUPPRESS_CONSOLE_MESSAGE" = false ]; then
      echo_message "Please connect to the console using: $0 console $VMNAME"
    fi
  else
    log "Preparing for non-bhyveload start..."
    ensure_nmdm_device_nodes "$CONSOLE"
    sleep 1 # Give nmdm devices a moment to be ready
    local BHYVE_LOADER_CLI_ARG=""
    case "$BOOTLOADER_TYPE" in
      uefi|bootrom)
        local UEFI_FIRMWARE_FOUND=false
        if [ -f "/usr/local/share/uefi-firmware/BHYVE_UEFI.fd" ]; then
          BHYVE_LOADER_CLI_ARG="-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd"
          log "Using uefi firmware from default system path: /usr/local/share/uefi-firmware/BHYVE_UEFI.fd"
          UEFI_FIRMWARE_FOUND=true
        elif [ -f "$UEFI_FIRMWARE_PATH/BHYVE_UEFI.fd" ]; then
          BHYVE_LOADER_CLI_ARG="-l bootrom,$UEFI_FIRMWARE_PATH/BHYVE_UEFI.fd"
          log "Using uefi firmware from configured path: $UEFI_FIRMWARE_PATH/BHYVE_UEFI.fd"
          UEFI_FIRMWARE_FOUND=true
        fi

        if [ "$UEFI_FIRMWARE_FOUND" = false ]; then
          if [ "$SUPPRESS_CONSOLE_MESSAGE" = false ]; then
            stop_spinner
          fi
          echo_message "ERROR: UEFI firmware not found. Please ensure 'edk2-bhyve' is installed (pkg install edk2-bhyve) or copy a compatible UEFI firmware file to $UEFI_FIRMWARE_PATH. Check VM logs for details."
          exit 1
        fi
        ;;
      grub2-bhyve)
        if [ -f "$VM_DIR/grub.conf" ]; then
          BHYVE_LOADER_CLI_ARG="-l grub,${VM_DIR}/grub.conf"
          log "Using grub2-bhyve with config: ${VM_DIR}/grub.conf"
        else
          if [ "$SUPPRESS_CONSOLE_MESSAGE" = false ]; then
            stop_spinner
          fi
          echo_message "ERROR: grub.conf not found in $VM_DIR. Check VM logs for details."
          exit 1
        fi
        ;;
      *)
        if [ "$SUPPRESS_CONSOLE_MESSAGE" = false ]; then
          stop_spinner
        fi
        echo_message "ERROR: Unsupported bootloader type: $BOOTLOADER_TYPE. Check VM logs for details."
        exit 1
        ;;
    esac

    log "Starting VM '$VMNAME'..."
    local BHYVE_CMD="${BHYVE_CMD_COMMON_ARGS} -l com1,/dev/${CONSOLE}A -s 31,lpc ${BHYVE_LOADER_CLI_ARG} \"$VMNAME\""
    log "Executing bhyve command: $BHYVE_CMD"
    # Execute bhyve command and capture its output and exit code
    local BHYVE_EXEC_OUTPUT
    local BHYVE_EXEC_EXIT_CODE
    BHYVE_EXEC_OUTPUT=$(eval "$BHYVE_CMD" >> "$LOG_FILE" 2>&1 & echo $!)
    BHYVE_EXEC_EXIT_CODE=$?
    log "Bhyve command executed. PID: $BHYVE_EXEC_OUTPUT, Exit Code: $BHYVE_EXEC_EXIT_CODE"
    log_to_global_file "INFO" "Bhyve command execution result: PID=$BHYVE_EXEC_OUTPUT, ExitCode=$BHYVE_EXEC_EXIT_CODE"
    # Give bhyve a moment to start and register its process
    sleep 0.5
    # Find the actual bhyve process PID
    BHYVE_PID=$(pgrep -f "bhyve: [[:<:]]$VMNAME.*")
    if [ -z "$BHYVE_PID" ]; then
        log_to_global_file "ERROR" "Could not find bhyve PID for $VMNAME after start attempt."
        if [ "$SUPPRESS_CONSOLE_MESSAGE" = false ]; then
            stop_spinner
        fi
        display_and_log "ERROR" "Failed to start VM '$VMNAME'. Could not find bhyve process PID."
        exit 1
    fi
    save_vm_pid "$VMNAME" "$BHYVE_PID"

    # Wait briefly for bhyve to start or fail
    sleep 1

    # Check if the bhyve process is still running
    if ps -p "$BHYVE_PID" > /dev/null 2>&1; then
      if [ "$SUPPRESS_CONSOLE_MESSAGE" = false ]; then
        stop_spinner
        echo_message "VM '$VMNAME' started successfully."
      fi
      set_vm_status "$VMNAME" "running"
      if [ "$CONNECT_TO_CONSOLE" = true ]; then
        echo_message ">>> Entering VM '$VMNAME' console (exit with ~.)"
        cu -l /dev/"${CONSOLE}B"
        log "cu session ended."
      else
        if [ "$SUPPRESS_CONSOLE_MESSAGE" = false ]; then
          echo_message "Please connect to the console using: $0 console $VMNAME"
        fi
      fi
    else
      if [ "$SUPPRESS_CONSOLE_MESSAGE" = false ]; then
        stop_spinner
      fi
      echo_message "ERROR: Failed to start VM '$VMNAME'. Bhyve process exited prematurely. Check VM logs for details."
      delete_vm_pid "$VMNAME"
      $BHYVECTL --vm="$VMNAME" --destroy > /dev/null 2>&1
      exit 1
    fi
  fi
  log "Exiting cmd_start function for VM: $VMNAME"
}
