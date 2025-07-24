#!/usr/local/bin/bash

# === Subcommand: create ===
cmd_create() {
  local VMNAME=""
  local DISKSIZE=""
  local VM_BRIDGE=""
  local BOOTLOADER_TYPE="bhyveload" # Default bootloader
  local VNC_PORT=""
  local VNC_WAIT="no"
  local FROM_TEMPLATE=""
  local NIC_TYPE="virtio-net" # Default NIC type

  # Parse named arguments
  while (( "$#" )); do
    case "$1" in
      --name)
        shift
        VMNAME="$1"
        ;;
      --disk-size)
        shift
        DISKSIZE="$1"
        ;;
      --switch)
        shift
        VM_BRIDGE="$1"
        ;;
      --bootloader)
        shift
        BOOTLOADER_TYPE="$1"
        ;;
      --vnc-port)
        shift
        VNC_PORT="$1"
        ;;
      --vnc-wait)
        VNC_WAIT="yes"
        ;;
      --from-template)
        shift
        FROM_TEMPLATE="$1"
        ;;
      --nic-type)
        shift
        NIC_TYPE="$1"
        ;;
      *)
        display_and_log "ERROR" "Invalid option: $1"
        cmd_create_usage
        exit 1
        ;;
    esac
    shift
  done

  # Validate required arguments
  if [ -z "$VMNAME" ] || [ -z "$VM_BRIDGE" ]; then
    cmd_create_usage
    exit 1
  fi

  if [ -z "$FROM_TEMPLATE" ] && [ -z "$DISKSIZE" ]; then
    display_and_log "ERROR" "Either --disk-size or --from-template must be specified."
    cmd_create_usage
    exit 1
  fi

  if [ -n "$FROM_TEMPLATE" ] && [ -n "$DISKSIZE" ]; then
    display_and_log "ERROR" "Cannot use both --disk-size and --from-template simultaneously."
    cmd_create_usage
    exit 1
  fi

  start_spinner "Creating VM '$VMNAME'..."

  VM_DIR="$VM_CONFIG_BASE_DIR/$VMNAME"
  CONF="$VM_DIR/vm.conf"

  log "Attempting to create VM directory: $VM_DIR"
  mkdir -p "$VM_DIR" || { stop_spinner; display_and_log "ERROR" "Failed to create VM directory '$VM_DIR'. Please check permissions or path."; exit 1; }
  LOG_FILE="$VM_DIR/vm.log" # Set LOG_FILE for create command
  log "VM directory '$VM_DIR' created successfully."

  log "Preparing to create VM '$VMNAME' with disk size ${DISKSIZE}GB and connecting to bridge '$VM_BRIDGE'."

  # === Handle template or new disk ===
  if [ -n "$FROM_TEMPLATE" ]; then
    local TEMPLATE_PATH="$VM_CONFIG_BASE_DIR/templates/$FROM_TEMPLATE"
    if [ ! -d "$TEMPLATE_PATH" ] || [ ! -f "$TEMPLATE_PATH/disk.img" ] || [ ! -f "$TEMPLATE_PATH/vm.conf" ]; then
      stop_spinner
      display_and_log "ERROR" "Template '$FROM_TEMPLATE' not found or incomplete."
      rmdir "$VM_DIR" 2>/dev/null
      exit 1
    fi
    log "Creating VM from template '$FROM_TEMPLATE'."
    cp "$TEMPLATE_PATH/disk.img" "$VM_DIR/disk.img" || { stop_spinner; display_and_log "ERROR" "Failed to copy disk image from template."; rm -rf "$VM_DIR"; exit 1; }
    cp "$TEMPLATE_PATH/vm.conf" "$CONF" || { stop_spinner; display_and_log "ERROR" "Failed to copy vm.conf from template."; rm -rf "$VM_DIR"; exit 1; }
    # Load template config to get disk size for logging
    # shellcheck disable=SC1090
    . "$CONF"
    DISKSIZE="${DISKSIZE:-$(stat -f %z "$VM_DIR/disk.img" | awk '{print int($1 / (1024*1024*1024))}')}" # Get size from copied disk if not specified
  else
    # === Create disk image ===
    log "Attempting to create disk image: $VM_DIR/disk.img with size ${DISKSIZE}GB..."
    local TRUNCATE_CMD="truncate -s \"${DISKSIZE}G\" \"$VM_DIR/disk.img\""
    log "Executing: $TRUNCATE_CMD"
    truncate -s "${DISKSIZE}G" "$VM_DIR/disk.img" || { stop_spinner; display_and_log "ERROR" "Failed to create disk image at '$VM_DIR/disk.img'. Command: '$TRUNCATE_CMD'"; exit 1; }
    log "Disk image '$VM_DIR/disk.img' (${DISKSIZE}GB) created successfully."
  fi

  # === Generate unique UUID ===
  UUID=$(uuidgen)
  log "Generated unique UUID for VM: $UUID"

  # === Generate unique MAC address (static prefix, random suffix) ===
  MAC_0="58:9c:fc$(jot -r -w ":%02x" -s "" 3 0 255)"
  log "Generated MAC address for NIC0: $MAC_0"

  # === Safely detect next available TAP & create TAP ===
  local NEXT_TAP_NUM=$(get_next_available_tap_num)
  TAP_0="tap${NEXT_TAP_NUM}"
  log "Assigned next available TAP interface: $TAP_0"

  # === Create and configure TAP interface ===
  if ! create_and_configure_tap_interface "$TAP_0" "$MAC_0" "$VM_BRIDGE" "$VMNAME" 0; then
    stop_spinner
    display_and_log "ERROR" "Failed to create and configure network interface. Check logs for details."
    exit 1
  fi

  # === Generate unique console name ===
  CONSOLE="nmdm-${VMNAME}.1"
  log "Console device assigned: $CONSOLE"

  # === Update/Create configuration file ===
  log "Attempting to create/update VM configuration file: $CONF"
  # If from template, vm.conf already exists, just append/overwrite specific values
  cat >> "$CONF" <<EOF
VMNAME=$VMNAME
UUID=$UUID
CPUS=${CPUS:-2}
MEMORY=${MEMORY:-2048M}
TAP_0=$TAP_0
MAC_0=$MAC_0
BRIDGE_0=$VM_BRIDGE
NIC_0_TYPE=$NIC_TYPE
DISK=disk.img
DISKSIZE=$DISKSIZE
CONSOLE=$CONSOLE
LOG=$LOG_FILE
AUTOSTART=${AUTOSTART:-no}
BOOTLOADER_TYPE=${BOOTLOADER_TYPE:-bhyveload}
VNC_PORT=${VNC_PORT}
VNC_WAIT=${VNC_WAIT}
EOF

  log "Configuration file created/updated: $CONF"

  stop_spinner
  echo_message "VM '$VMNAME' successfully created."
  echo_message "Please continue by running: $0 install $VMNAME"
}

# === Subcommand: delete ===
cmd_delete() {
  if [ -z "$1" ]; then
    cmd_delete_usage
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  # Check if VM is running and get confirmation
  if is_vm_running "$VMNAME"; then
    echo_message "VM '$VMNAME' is currently running."
    read -rp "Do you want to stop and permanently delete the VM '$VMNAME'? [y/n]: " CONFIRM_DELETE
  else
    read -rp "Are you sure you want to permanently delete the VM '$VMNAME'? [y/n]: " CONFIRM_DELETE
  fi

  if ! [[ "$CONFIRM_DELETE" =~ ^[Yy]$ ]]; then
    echo_message "VM deletion cancelled."
    log "VM deletion cancelled by user."
    exit 0
  fi

  start_spinner "Deleting VM '$VMNAME'..."
  log "Initiating deletion process for VM '$VMNAME'..."

  # Stop VM if running and clean up all processes/kernel memory
  log "Cleaning up VM processes and kernel memory..."
  cleanup_vm_processes "$VMNAME" "$CONSOLE" "$LOG_FILE"

  # Clean up network interfaces
  log "Cleaning up VM network interfaces..."
  cleanup_vm_network_interfaces "$VMNAME"

  # Remove console device files
  if [ -e "/dev/${CONSOLE}A" ]; then
    log "Removing console device /dev/${CONSOLE}A..."
    rm -f "/dev/${CONSOLE}A"
  fi
  if [ -e "/dev/${CONSOLE}B" ]; then
    log "Removing console device /dev/${CONSOLE}B..."
    rm -f "/dev/${CONSOLE}B"
  fi

  # Remove vm.pid file
  log "Removing vm.pid file..."
  delete_vm_pid "$VMNAME"

  # Unset LOG_FILE before removing the directory
  unset LOG_FILE

  # Delete VM directory
  log "Deleting VM directory: $VM_DIR..."
  rm -rf "$VM_DIR"
  if [ $? -ne 0 ]; then
    stop_spinner
    display_and_log "ERROR" "Failed to remove VM directory '$VM_DIR'. Please check permissions."
    exit 1
  fi

  stop_spinner
  echo_message "VM '$VMNAME' successfully deleted."
}

# === Subcommand: suspend ===
cmd_suspend() {
  if [ -z "$1" ]; then
    cmd_suspend_usage
    exit 1
  fi

  local VMNAME="$1"
  load_vm_config "$VMNAME"

  if ! is_vm_running "$VMNAME"; then
    display_and_log "ERROR" "VM '$VMNAME' is not running. Cannot suspend a stopped VM."
    exit 1
  fi

  display_and_log "INFO" "Suspending VM '$VMNAME'..."
  start_spinner "Suspending VM '$VMNAME'..."

  if ! $BHYVECTL --vm="$VMNAME" --suspend; then
    stop_spinner
    display_and_log "ERROR" "Failed to suspend VM '$VMNAME'. Check logs for details."
    exit 1
  fi

  stop_spinner
  display_and_log "INFO" "VM '$VMNAME' suspended successfully."
}

# === Subcommand: resume ===
cmd_resume() {
  if [ -z "$1" ]; then
    cmd_resume_usage
    exit 1
  fi

  local VMNAME="$1"
  load_vm_config "$VMNAME"

  if is_vm_running "$VMNAME"; then
    display_and_log "ERROR" "VM '$VMNAME' is already running. Cannot resume a running VM."
    exit 1
  fi

  display_and_log "INFO" "Resuming VM '$VMNAME'..."
  start_spinner "Resuming VM '$VMNAME'..."

  if ! $BHYVECTL --vm="$VMNAME" --resume; then
    stop_spinner
    display_and_log "ERROR" "Failed to resume VM '$VMNAME'. Check logs for details."
    exit 1
  fi

  stop_spinner
  display_and_log "INFO" "VM '$VMNAME' resumed successfully."
}

# === Subcommand: restart ===
cmd_restart() {
  if [ -z "$1" ]; then
    cmd_restart_usage
    exit 1
  fi

  local VMNAME="$1"
  local FORCE_RESTART=false

  # Check for --force flag
  if [ "$2" = "--force" ]; then
    FORCE_RESTART=true
  fi

  load_vm_config "$VMNAME"

  display_and_log "INFO" "Restarting VM '$VMNAME'..."

  # Check if the VM is running
  if ! is_vm_running "$VMNAME"; then
    display_and_log "INFO" "VM '$VMNAME' is not running. Starting it..."
    cmd_start "$VMNAME"
    exit 0
  fi

  if [ "$FORCE_RESTART" = true ]; then
    # --- Fast but unsafe restart ---
    display_and_log "INFO" "VM is running. Performing a fast (forced) restart..."
    local BHYVECTL_RESET_CMD="$BHYVECTL --vm=\"$VMNAME\" --force-reset"
    log "Executing: $BHYVECTL_RESET_CMD"

    if $BHYVECTL --vm="$VMNAME" --force-reset; then
      log "VM '$VMNAME' successfully reset via bhyvectl. Waiting a moment before starting again..."
      sleep 2 # Give a moment for the process to fully terminate
      cmd_start "$VMNAME"
      display_and_log "INFO" "VM '$VMNAME' successfully restarted."
    else
      display_and_log "WARNING" "Fast reset failed. The VM might be in an inconsistent state."
      log "bhyvectl --force-reset failed for '$VMNAME'."
      exit 1 # Exit with an error to indicate the forced restart failed
    fi
  else
    # --- Safe default restart ---
    display_and_log "INFO" "Performing a safe restart (stop and start)..."
    cmd_stop "$VMNAME"
    sleep 2 # Give it a moment to fully stop and clean up
    cmd_start "$VMNAME"
    display_and_log "INFO" "VM '$VMNAME' restart initiated."
  fi
}

# === Subcommand: install ===
cmd_install() {
  local VMNAME=""
  local INSTALL_BOOTLOADER_TYPE="" # Bootloader type for this installation only

  # Parse arguments
  VMNAME="$1"
  shift

  while (( "$#" )); do
    case "$1" in
      --bootloader)
        shift
        INSTALL_BOOTLOADER_TYPE="$1"
        ;;
      *)
        display_and_log "ERROR" "Invalid option for install: $1"
        cmd_install_usage
        exit 1
        ;;
    esac
    shift
  done

  if [ -z "$VMNAME" ]; then
    cmd_install_usage
    exit 1
  fi

  load_vm_config "$VMNAME"

  # Override BOOTLOADER_TYPE if specified for installation
  if [ -n "$INSTALL_BOOTLOADER_TYPE" ]; then
    BOOTLOADER_TYPE="$INSTALL_BOOTLOADER_TYPE"
    log "Overriding bootloader for installation to: $BOOTLOADER_TYPE"
  fi

  ensure_nmdm_device_nodes "$CONSOLE"
  sleep 1 # Give nmdm devices a moment to be ready
  
  log "INFO" "Starting VM '$VMNAME'..."

  # === Stop bhyve if still active ===
  if is_vm_running "$VMNAME"; then
    log "VM '$VMNAME' is still running. Stopped..."
    pkill -f "bhyve.*$VMNAME"
    sleep 1
  fi

  # === Destroy if still remaining in kernel ===
  if $BHYVECTL --vm="$VMNAME" --destroy > /dev/null 2>&1; then
    log "VM '$VMNAME' was still in memory. Destroyed."
  fi

  # === Select ISO source ===
  echo_message ""
  echo_message "Select ISO source:"
  echo_message "1. Choose existing ISO"
  echo_message "2. Download ISO from URL"
  read -rp "Choice [1/2]: " CHOICE

  local ISO_PATH=""
  case "$CHOICE" in
    1)
      log "Searching for ISO files in $ISO_DIR..."
      if [ ! -d "$ISO_DIR" ]; then
        display_and_log "INFO" "ISO directory '$ISO_DIR' not found. Creating it."
        mkdir -p "$ISO_DIR"
      fi
      mapfile -t ISO_LIST < <(find "$ISO_DIR" -type f -name "*.iso" 2>/dev/null)
      if [ ${#ISO_LIST[@]} -eq 0 ]; then
        display_and_log "WARNING" "No ISO files found in $ISO_DIR!"
        exit 1
      fi
      echo_message "Available ISOs:"
      select iso in "${ISO_LIST[@]}"; do
        if [ -n "$iso" ]; then
          ISO_PATH="$iso"
          break
        fi
      done
      ;;
    2)
      read -rp "Enter ISO URL: " ISO_URL
      ISO_FILE="$(basename "$ISO_URL")"
      ISO_PATH="$ISO_DIR/$ISO_FILE"
      mkdir -p "$ISO_DIR"
      log "Downloading ISO from $ISO_URL"
      fetch "$ISO_URL" -o "$ISO_PATH" || {
        display_and_log "ERROR" "Failed to download ISO"
        exit 1
      }
      ;;
    *)
      display_and_log "ERROR" "Invalid choice"
      exit 1
      ;;
  esac

  if [ -z "$ISO_PATH" ]; then
    display_and_log "ERROR" "No ISO selected."
    exit 1
  fi

  local DISK_ARGS_AND_NEXT_DEV
  DISK_ARGS_AND_NEXT_DEV=$(build_disk_args "$VM_DIR")
  local DISK_ARGS=$(echo "$DISK_ARGS_AND_NEXT_DEV" | head -n 1)
  local NEXT_DISK_DEV_NUM=$(echo "$DISK_ARGS_AND_NEXT_DEV" | tail -n 1)
  if [ $? -ne 0 ]; then
    display_and_log "ERROR" "Failed to build disk arguments."
    exit 1
  fi

  local NETWORK_ARGS=$(build_network_args "$VMNAME" "$VM_DIR")
  if [ $? -ne 0 ]; then
    display_and_log "ERROR" "Failed to build network arguments."
    exit 1
  fi

  # === Installation Logic ===
  if [ "$BOOTLOADER_TYPE" = "bhyveload" ]; then
    run_bhyveload "$ISO_PATH" || exit 1

    display_and_log "INFO" "Starting VM with nmdm console for installation..."
    local BHYVE_CMD="$BHYVE -c \"$CPUS\" -m \"$MEMORY\" -AHP -s 0,hostbridge $DISK_ARGS -s ${NEXT_DISK_DEV_NUM}:0,ahci-cd,\"$ISO_PATH\" $NETWORK_ARGS -l com1,/dev/${CONSOLE}A -s 31,lpc \"$VMNAME\""
    log "Executing bhyve command: $BHYVE_CMD"
    eval "$BHYVE_CMD" >> "$LOG_FILE" 2>&1 &
    VM_PID=$!
    save_vm_pid "$VMNAME" "$VM_PID"
    log "Bhyve VM started in background with PID $VM_PID"

    sleep 2 # Give bhyve a moment to start
    if ! is_vm_running "$VMNAME"; then
      log_to_global_file "ERROR" "bhyve process for $VMNAME exited prematurely. Check vm.log for details."
      display_and_log "ERROR" "Failed to start VM for installation. Check logs."
      exit 1
    fi
    echo_message ""
    echo_message ">>> Entering VM '$VMNAME' installation console (exit with ~.)"
    echo_message ">>> IMPORTANT: After shutting down the VM from within, you MUST type '~.' (tilde then dot) to exit this console and allow the script to continue cleanup."
    cu -l /dev/"${CONSOLE}B" -s 115200

    log "cu session ended. Initiating cleanup..."

    # Check the exit status of the bhyve process
    wait "$VM_PID"
    local BHYVE_EXIT_STATUS=$?

    cleanup_vm_processes "$VMNAME" "$CONSOLE" "$LOG_FILE"

    if [ "$BHYVE_EXIT_STATUS" -eq 3 ] || [ "$BHYVE_EXIT_STATUS" -eq 4 ]; then
        display_and_log "ERROR" "Virtual machine '$VMNAME' installer exited with an error (exit code: $BHYVE_EXIT_STATUS). Check VM logs for details."
        exit 1
    else
        log "Bhyve process $VM_PID exited cleanly (status: $BHYVE_EXIT_STATUS)."
    fi
    display_and_log "INFO" "Installation finished. You can now start the VM with: $0 start $VMNAME"
  else
    # --- uefi/GRUB INSTALL ---
    log "Preparing for non-bhyveload installation..."
    local BHYVE_LOADER_CLI_ARG=""
    case "$BOOTLOADER_TYPE" in
      uefi|bootrom)
        local UEFI_FIRMWARE_FOUND=false
        local FOUND_UEFI_FILE=""
        if [ -d "$UEFI_FIRMWARE_PATH" ]; then
          # Try to find BHYVE_UEFI.fd in the configured firmware directory or its subdirectories
          FOUND_UEFI_FILE=$(find "$UEFI_FIRMWARE_PATH" -name "BHYVE_UEFI.fd" -print -quit 2>/dev/null)
        fi

        if [ -n "$FOUND_UEFI_FILE" ]; then
          BHYVE_LOADER_CLI_ARG="-l bootrom,$FOUND_UEFI_FILE"
          log "Using uefi firmware from configured path: $FOUND_UEFI_FILE"
          UEFI_FIRMWARE_FOUND=true
        elif [ -f "/usr/local/share/uefi-firmware/BHYVE_UEFI.fd" ]; then
          BHYVE_LOADER_CLI_ARG="-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd"
          log "Using uefi firmware from default system path: /usr/local/share/uefi-firmware/BHYVE_UEFI.fd"
          UEFI_FIRMWARE_FOUND=true
        fi

        if [ "$UEFI_FIRMWARE_FOUND" = false ]; then
          display_and_log "ERROR" "UEFI firmware not found."
          echo_message "Please ensure 'edk2-bhyve' is installed (pkg install edk2-bhyve) or copy a compatible UEFI firmware file to $UEFI_FIRMWARE_PATH."
          exit 1
        fi
        ;;
      grub2-bhyve)
        if [ -f "$VM_DIR/grub.conf" ]; then
          BHYVE_LOADER_CLI_ARG="-l grub,${VM_DIR}/grub.conf"
          log "Using grub2-bhyve with config: ${VM_DIR}/grub.conf"
        else
          display_and_log "ERROR" "grub.conf not found in $VM_DIR."
          exit 1
        fi
        ;;
      *)
        display_and_log "ERROR" "Unsupported bootloader type for ISO installation: $BOOTLOADER_TYPE"
        exit 1
        ;;
    esac

    clear # Clear screen before console

    log "Running bhyve installer in background..."
    local BHYVE_CMD="$BHYVE -c \"$CPUS\" -m \"$MEMORY\" -AHP -s 0,hostbridge $DISK_ARGS -s ${NEXT_DISK_DEV_NUM}:0,ahci-cd,\"$ISO_PATH\" $NETWORK_ARGS -l com1,/dev/${CONSOLE}A -s 31,lpc ${BHYVE_LOADER_CLI_ARG} \"$VMNAME\""
    log "Executing bhyve command: $BHYVE_CMD"
    log "Full bhyve command: $BHYVE_CMD"
    eval "$BHYVE_CMD" >> "$LOG_FILE" 2>&1 &
    VM_PID=$!
    save_vm_pid "$VMNAME" "$VM_PID"
    log "Bhyve VM started in background with PID $VM_PID"

    echo_message ">>> Entering VM '$VMNAME' console (exit with ~.)"
    echo_message ">>> IMPORTANT: After shutting down the VM from within, you MUST type '~.' (tilde then dot) to exit this console and allow the script to continue cleanup."
    sleep 3 # Give bhyve time to initialize console
    cu -l /dev/"${CONSOLE}B" -s 115200

    log "cu session ended. Initiating cleanup..."

    # Wait for the bhyve process to exit.
    # Capture its exit status.
    wait "$VM_PID"
    local BHYVE_EXIT_STATUS=$?

    cleanup_vm_processes "$VMNAME" "$CONSOLE" "$LOG_FILE"

    if [ "$BHYVE_EXIT_STATUS" -eq 3 ] || [ "$BHYVE_EXIT_STATUS" -eq 4 ]; then
        display_and_log "ERROR" "Virtual machine '$VMNAME' failed to boot or installer exited with an error (exit code: $BHYVE_EXIT_STATUS). Check VM logs for details."
        exit 1
    else
        log "Bhyve process $VM_PID exited cleanly (status: $BHYVE_EXIT_STATUS)."
    fi
    log "Bhyve process $VM_PID exited."
    display_and_log "INFO" "Installation finished. You can now start the VM with: $0 start $VMNAME"
  fi
}


# === Subcommand: start ===
cmd_start() {
  if [ -z "$1" ]; then
    cmd_start_usage
    exit 1
  fi

  local VMNAME="$1"
  local CONNECT_TO_CONSOLE=false
  local QUIET_BOOTLOADER=true # Default to quiet bootloader (no console)
  local BHYVE_LOADER_CLI_ARG="" # Initialize to empty

  # Parse arguments
  local ARGS=()
  for arg in "$@"; do
    if [[ "$arg" == "--console" ]]; then
      CONNECT_TO_CONSOLE=true
      QUIET_BOOTLOADER=false # Show bootloader output if console is requested
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

  # Check if VM is already running
  if is_vm_running "$VMNAME"; then
    display_and_log "INFO" "VM '$VMNAME' is already running."
    if [ "$CONNECT_TO_CONSOLE" = true ]; then
      display_and_log "INFO" "Connecting to console..."
      cmd_console "$VMNAME"
    fi
    exit 0
  fi

  # === Check if VM is installed ===
  local DISK_PATH="$VM_DIR/$DISK"
  if [ -f "$DISK_PATH" ]; then
    # Check actual disk usage. A truncated file will have 0 usage.
    local DISK_USAGE_KB=$(du -k "$DISK_PATH" | awk '{print $1}')
    if [ "$DISK_USAGE_KB" -lt 1024 ]; then # Check if less than 1MB, a reasonable threshold for an uninstalled OS
      stop_spinner
      display_and_log "ERROR" "VM '$VMNAME' has not been installed yet. The disk image is empty."
      echo_message "Please run '$0 install $VMNAME' first."
      exit 1
    fi
  else
    stop_spinner
    display_and_log "ERROR" "Primary disk for VM '$VMNAME' not found at '$DISK_PATH'."
    exit 1
  fi


  start_spinner "Starting VM '$VMNAME'..."
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
    VNC_ARGS="-s 29,fbuf,tcp=$VNC_PORT,w=1024,h=768,vga=std,password=,wait=$VNC_WAIT"
    log "VNC enabled on port $VNC_PORT, wait: $VNC_WAIT"
  fi

  # === Start Logic ===
  if [ "$BOOTLOADER_TYPE" = "bhyveload" ]; then
    log "Preparing for bhyveload start..."
    ensure_nmdm_device_nodes "$CONSOLE"
    sleep 1 # Give nmdm devices a moment to be ready
    
    log "Verifying nmdm device nodes:"
    if [ -e "/dev/${CONSOLE}A" ]; then
      log "/dev/${CONSOLE}A exists with permissions: $(stat -f \"%Sp\" /dev/${CONSOLE}A)"
    else
      stop_spinner
      display_and_log "ERROR" "/dev/${CONSOLE}A does NOT exist! Please ensure the VM has been run at least once, or the device has been created."
      exit 1
    fi
    if [ -e "/dev/${CONSOLE}B" ]; then
      log "/dev/${CONSOLE}B exists with permissions: $(stat -f \"%Sp\" /dev/${CONSOLE}B)"
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

    local BHYVE_CMD="$BHYVE -c \"$CPUS\" -m \"$MEMORY\" -AHP -s 0,hostbridge $DISK_ARGS $NETWORK_ARGS -l com1,/dev/${CONSOLE}A -s 31,lpc ${BHYVE_LOADER_CLI_ARG} $VNC_ARGS \"$VMNAME\""
    log "Executing bhyve command: $BHYVE_CMD"
    log_to_global_file "INFO" "Starting bhyve VM with command: $BHYVE_CMD"
    eval "$BHYVE_CMD" >> "$LOG_FILE" 2>&1 &
    BHYVE_PID=$!
    save_vm_pid "$VMNAME" "$BHYVE_PID"

    # Wait briefly for bhyve to start or fail
    sleep 1
    if ! is_vm_running "$VMNAME"; then
      stop_spinner
      log_to_global_file "ERROR" "bhyve process for $VMNAME exited prematurely. Check vm.log for details."
      display_and_log "ERROR" "Failed to start VM '$VMNAME'. Bhyve process exited prematurely. Check VM logs for details."
      delete_vm_pid "$VMNAME"
      $BHYVECTL --vm="$VMNAME" --destroy > /dev/null 2>&1
      exit 1
    fi

    stop_spinner
    echo_message "VM '$VMNAME' started successfully."
    if [ "$CONNECT_TO_CONSOLE" = true ]; then
      sleep 2 # Give console a moment to be ready
      echo_message "Entering VM '$VMNAME' console (exit with ~.)"
      cu -l /dev/"${CONSOLE}B" -s 115200
      log "cu session ended."
    else
      echo_message "Please connect to the console using: $0 console $VMNAME"
    fi
  else
    log "Preparing for non-bhyveload start..."
    case "$BOOTLOADER_TYPE" in
      uefi|bootrom)
        local UEFI_FIRMWARE_FOUND=false
        local FOUND_UEFI_FILE=""
        if [ -d "$UEFI_FIRMWARE_PATH" ]; then
          # Try to find BHYVE_UEFI.fd in the configured firmware directory or its subdirectories
          FOUND_UEFI_FILE=$(find "$UEFI_FIRMWARE_PATH" -name "BHYVE_UEFI.fd" -print -quit 2>/dev/null)
        fi

        if [ -n "$FOUND_UEFI_FILE" ]; then
          BHYVE_LOADER_CLI_ARG="-l bootrom,$FOUND_UEFI_FILE"
          log "Using uefi firmware from configured path: $FOUND_UEFI_FILE"
          UEFI_FIRMWARE_FOUND=true
        elif [ -f "/usr/local/share/uefi-firmware/BHYVE_UEFI.fd" ]; then
          BHYVE_LOADER_CLI_ARG="-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd"
          log "Using uefi firmware from default system path: /usr/local/share/uefi-firmware/BHYVE_UEFI.fd"
          UEFI_FIRMWARE_FOUND=true
        fi

        if [ "$UEFI_FIRMWARE_FOUND" = false ]; then
          stop_spinner
          echo_message "ERROR: UEFI firmware not found. Please ensure 'edk2-bhyve' is installed (pkg install edk2-bhyve) or copy a compatible UEFI firmware file to $UEFI_FIRMWARE_PATH. Check VM logs for details."
          exit 1
        fi
        ;;
      grub2-bhyve)
        if [ -f "$VM_DIR/grub.conf" ]; then
          BHYVE_LOADER_CLI_ARG="-l grub,${VM_DIR}/grub.conf"
          log "Using grub2-bhyve with config: ${VM_DIR}/grub.conf"
        else
          stop_spinner
          echo_message "ERROR: grub.conf not found in $VM_DIR. Check VM logs for details."
          exit 1
        fi
        ;;
      *)
        stop_spinner
        echo_message "ERROR: Unsupported bootloader type: $BOOTLOADER_TYPE. Check VM logs for details."
        exit 1
        ;;
    esac

    log "Starting VM '$VMNAME'..."
    local BHYVE_CMD="$BHYVE -c \"$CPUS\" -m \"$MEMORY\" -AHP -s 0,hostbridge $DISK_ARGS $NETWORK_ARGS -l com1,/dev/${CONSOLE}A -s 31,lpc ${BHYVE_LOADER_CLI_ARG} $VNC_ARGS \"$VMNAME\""
    log "Executing bhyve command: $BHYVE_CMD"
    eval "$BHYVE_CMD" >> "$LOG_FILE" 2>&1 &
    BHYVE_PID=$!
    save_vm_pid "$VMNAME" "$BHYVE_PID"

    # Wait briefly for bhyve to start or fail
    sleep 1

    # Check if the bhyve process is still running
    if ps -p "$BHYVE_PID" > /dev/null 2>&1; then
      stop_spinner
      echo_message "VM '$VMNAME' started successfully."
      if [ "$CONNECT_TO_CONSOLE" = true ]; then
        echo_message "Entering VM '$VMNAME' console (exit with ~.)"
        cu -l /dev/"${CONSOLE}B" -s 115200
        log "cu session ended."
      else
        echo_message "Please connect to the console using: $0 console $VMNAME"
      fi
    else
      stop_spinner
      echo_message "ERROR: Failed to start VM '$VMNAME'. Bhyve process exited prematurely. Check VM logs for details."
      delete_vm_pid "$VMNAME"
      $BHYVECTL --vm="$VMNAME" --destroy > /dev/null 2>&1
      exit 1
    fi
  fi
}

# === Subcommand: startall ===
cmd_startall() {
  display_and_log "INFO" "Attempting to start all configured VMs..."

  for VMCONF in "$VM_CONFIG_BASE_DIR"/*/vm.conf; do
    [ -f "$VMCONF" ] || continue
    local VMNAME=$(basename "$(dirname "$VMCONF")")
    if ! is_vm_running "$VMNAME"; then
      display_and_log "INFO" "Starting VM '$VMNAME'..."
      "$0" start "$VMNAME" > /dev/null 2>&1
    else
      display_and_log "INFO" "VM '$VMNAME' is already running. Skipping."
    fi
  done
  log "Attempt to start all VMs complete."
}

# === Subcommand: stop ===
cmd_stop() {
  if [ -z "$1" ]; then
    cmd_stop_usage
    exit 1
  fi

  local VMNAME="$1"
  local FORCE_STOP=false

  # Check for --force flag
  if [ "$2" = "--force" ]; then
    FORCE_STOP=true
  fi

  load_vm_config "$VMNAME"

  if ! is_vm_running "$VMNAME"; then
    display_and_log "INFO" "VM '$VMNAME' is not running."
    # Clean up just in case
    cleanup_vm_processes "$VMNAME" "$CONSOLE" "$LOG_FILE"
    delete_vm_pid "$VMNAME"
    exit 0
  fi

  display_and_log "INFO" "Stopping VM '$VMNAME'..."

  if [ "$FORCE_STOP" = true ]; then
    log "Forcefully stopping VM '$VMNAME'."
    cleanup_vm_processes "$VMNAME" "$CONSOLE" "$LOG_FILE"
  else
    log "Attempting graceful shutdown for VM '$VMNAME'."
    # bhyvectl --force-poweroff is not graceful, so we use kill
    local VM_PID_TO_KILL=$(get_vm_pid "$VMNAME")
    if [ -n "$VM_PID_TO_KILL" ]; then
      kill "$VM_PID_TO_KILL"
      # Wait for the process to terminate
      local COUNT=0
      while ps -p "$VM_PID_TO_KILL" > /dev/null 2>&1; do
        sleep 1
        COUNT=$((COUNT + 1))
        if [ "$COUNT" -gt 10 ]; then # 10 second timeout
          log "Graceful shutdown timed out. Forcing stop."
          cleanup_vm_processes "$VMNAME" "$CONSOLE" "$LOG_FILE"
          break
        fi
      done
    fi
    # Final cleanup, even after graceful shutdown
    cleanup_vm_processes "$VMNAME" "$CONSOLE" "$LOG_FILE"
  fi

  delete_vm_pid "$VMNAME"
  display_and_log "INFO" "VM '$VMNAME' stopped."
}

# === Subcommand: stopall ===
cmd_stopall() {
  local FORCE_STOP_ALL=false
  if [ "$1" = "--force" ]; then
    FORCE_STOP_ALL=true
    display_and_log "INFO" "Attempting to forcefully stop all running VMs..."
  else
    display_and_log "INFO" "Attempting to gracefully stop all running VMs..."
  fi

  for VMCONF in "$VM_CONFIG_BASE_DIR"/*/vm.conf; do
    [ -f "$VMCONF" ] || continue
    local VMNAME=$(basename "$(dirname "$VMCONF")")
    if is_vm_running "$VMNAME"; then
      display_and_log "INFO" "Stopping VM '$VMNAME'..."
      if [ "$FORCE_STOP_ALL" = true ]; then
        "$0" stop "$VMNAME" --force > /dev/null 2>&1
      else
        "$0" stop "$VMNAME" > /dev/null 2>&1
      fi
    fi
  done
  log "Attempt to stop all VMs complete."
}

# === Subcommand: modify ===
cmd_modify() {
  if [ -z "$1" ]; then
    cmd_modify_usage
    exit 1
  fi

  VMNAME="$1"
  shift

  load_vm_config "$VMNAME"

  local CURRENT_DISK_PATH=""
  local CURRENT_DISK_TYPE="virtio-blk" # Default disk type

  while (( "$#" )); do
    case "$1" in
      --cpu)
        sed -i '' "s/^CPUS=.*/CPUS=$2/" "$CONF_FILE"
        display_and_log "INFO" "Set CPU count to $2 for VM '$VMNAME'."
        shift 2
        ;;
      --ram)
        sed -i '' "s/^MEMORY=.*/MEMORY=$2/" "$CONF_FILE"
        display_and_log "INFO" "Set RAM to $2 for VM '$VMNAME'."
        shift 2
        ;;
      --nic)
        local NIC_TO_MODIFY_IDX="$2"
        shift 2
        local NIC_MOD_OPTS=()
        while (( "$#" )); do
          case "$1" in
            --tap)
              NIC_MOD_OPTS+=("TAP_${NIC_TO_MODIFY_IDX}=$2")
              shift 2
              ;;
            --mac)
              NIC_MOD_OPTS+=("MAC_${NIC_TO_MODIFY_IDX}=$2")
              shift 2
              ;;
            --bridge)
              NIC_MOD_OPTS+=("BRIDGE_${NIC_TO_MODIFY_IDX}=$2")
              shift 2
              ;;
            --type)
              NIC_MOD_OPTS+=("NIC_${NIC_TO_MODIFY_IDX}_TYPE=$2")
              shift 2
              ;;
            *)
              break # Exit inner loop if not a NIC option
              ;;
          esac
        done
        if [ ${#NIC_MOD_OPTS[@]} -eq 0 ]; then
          display_and_log "ERROR" "No modification options provided for --nic."
          cmd_modify_usage
          exit 1
        fi
        for OPTION in "${NIC_MOD_OPTS[@]}"; do
          local VAR_NAME=$(echo "$OPTION" | cut -d'=' -f1)
          local NEW_VALUE=$(echo "$OPTION" | cut -d'=' -f2)
          sed -i '' "s/^${VAR_NAME}=.*/${VAR_NAME}=${NEW_VALUE}/" "$CONF_FILE"
          display_and_log "INFO" "Updated ${VAR_NAME} to ${NEW_VALUE} for VM '$VMNAME'."
        done
        ;;
      --add-nic)
        local NEW_BRIDGE="$2"
        local NEW_NIC_TYPE="virtio-net" # Default type for new NIC
        shift 2
        # Check for optional --nic-type argument after --add-nic
        if [[ "$1" == "--nic-type" ]]; then
          NEW_NIC_TYPE="$2"
          shift 2
        fi
        local NEXT_NIC_IDX=$(grep -c '^TAP_' "$CONF_FILE")
        local NEXT_TAP_NUM=$(get_next_available_tap_num)
        local NEW_TAP="tap${NEXT_TAP_NUM}"
        local NEW_MAC="58:9c:fc$(jot -r -w ":%02x" -s "" 3 0 255)"
        echo "TAP_${NEXT_NIC_IDX}=${NEW_TAP}" >> "$CONF_FILE"
        echo "MAC_${NEXT_NIC_IDX}=${NEW_MAC}" >> "$CONF_FILE"
        echo "BRIDGE_${NEXT_NIC_IDX}=${NEW_BRIDGE}" >> "$CONF_FILE"
        echo "NIC_${NEXT_NIC_IDX}_TYPE=${NEW_NIC_TYPE}" >> "$CONF_FILE"
        display_and_log "INFO" "Added NIC ${NEXT_NIC_IDX} (TAP: ${NEW_TAP}, Bridge: ${NEW_BRIDGE}, Type: ${NEW_NIC_TYPE}) to VM '$VMNAME'."
        ;;
      --remove-nic)
        local NIC_TO_REMOVE_IDX="$2"
        sed -i '' "/^TAP_${NIC_TO_REMOVE_IDX}=/d" "$CONF_FILE"
        sed -i '' "/^MAC_${NIC_TO_REMOVE_IDX}=/d" "$CONF_FILE"
        sed -i '' "/^BRIDGE_${NIC_TO_REMOVE_IDX}=/d" "$CONF_FILE"
        display_and_log "INFO" "Removed NIC ${NIC_TO_REMOVE_IDX} from VM '$VMNAME'."
        shift 2
        ;;
      --add-disk)
        local DISK_SIZE="$2"
        local NEXT_DISK_IDX=$(grep -c '^DISK' "$CONF_FILE")
        local NEW_DISK_FILENAME="disk${NEXT_DISK_IDX}.img"
        local NEW_DISK_PATH="$VM_DIR/$NEW_DISK_FILENAME"
        truncate -s "${DISK_SIZE}G" "$NEW_DISK_PATH" || { display_and_log "ERROR" "Failed to create new disk image."; exit 1; }
        echo "DISK_${NEXT_DISK_IDX}=${NEW_DISK_FILENAME}" >> "$CONF_FILE"
        echo "DISK_${NEXT_DISK_IDX}_TYPE=${CURRENT_DISK_TYPE}" >> "$CONF_FILE"
        display_and_log "INFO" "Added new disk ${NEXT_DISK_IDX} (${DISK_SIZE}GB, type: ${CURRENT_DISK_TYPE}) to VM '$VMNAME'."
        shift 2
        CURRENT_DISK_TYPE="virtio-blk" # Reset to default
        ;;
      --add-disk-path)
        local DISK_PATH_TO_ADD="$2"
        if [ ! -f "$DISK_PATH_TO_ADD" ]; then
          display_and_log "ERROR" "Disk file '$DISK_PATH_TO_ADD' not found."
          exit 1
        fi
        local NEXT_DISK_IDX=$(grep -c '^DISK' "$CONF_FILE")
        local DISK_FILENAME_ONLY=$(basename "$DISK_PATH_TO_ADD")
        # Decide whether to copy or link. For simplicity, let's copy for now.
        cp "$DISK_PATH_TO_ADD" "$VM_DIR/$DISK_FILENAME_ONLY" || { display_and_log "ERROR" "Failed to copy disk file."; exit 1; }
        echo "DISK_${NEXT_DISK_IDX}=${DISK_FILENAME_ONLY}" >> "$CONF_FILE"
        echo "DISK_${NEXT_DISK_IDX}_TYPE=${CURRENT_DISK_TYPE}" >> "$CONF_FILE"
        display_and_log "INFO" "Added existing disk ${NEXT_DISK_IDX} ('$DISK_FILENAME_ONLY', type: ${CURRENT_DISK_TYPE}) to VM '$VMNAME'."
        shift 2
        CURRENT_DISK_TYPE="virtio-blk" # Reset to default
        ;;
      --add-disk-type)
        CURRENT_DISK_TYPE="$2"
        shift 2
        ;;
      --remove-disk)
        local DISK_TO_REMOVE_IDX="$2"
        local DISK_VAR_NAME="DISK_${DISK_TO_REMOVE_IDX}"
        local DISK_TYPE_VAR_NAME="DISK_${DISK_TO_REMOVE_IDX}_TYPE"
        
        # Get filename before deleting config line
        local FILENAME_TO_DELETE=$(grep "^${DISK_VAR_NAME}=" "$CONF_FILE" | cut -d'=' -f2)

        sed -i '' "/^${DISK_VAR_NAME}=/d" "$CONF_FILE"
        sed -i '' "/^${DISK_TYPE_VAR_NAME}=/d" "$CONF_FILE"
        
        if [ -n "$FILENAME_TO_DELETE" ]; then
          read -rp "Delete associated disk file '$VM_DIR/$FILENAME_TO_DELETE'? (y/n): " CONFIRM_FILE_DELETE
          if [[ "$CONFIRM_FILE_DELETE" =~ ^[Yy]$ ]]; then
            rm -f "$VM_DIR/$FILENAME_TO_DELETE"
            display_and_log "INFO" "Associated disk file deleted."
          fi
        fi
        display_and_log "INFO" "Removed disk ${DISK_TO_REMOVE_IDX} from VM '$VMNAME'."
        shift 2
        ;;
      *)
        display_and_log "ERROR" "Invalid option: $1"
        cmd_modify_usage
        exit 1
        ;;
    esac
  done
}