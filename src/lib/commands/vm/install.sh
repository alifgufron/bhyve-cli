#!/usr/local/bin/bash

# === Subcommand: install ===
cmd_install() {
  log "Entering cmd_install function for VM: $1"
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

  # Find VM across all datastores
  local found_bhyve_cli_vm
  found_bhyve_cli_vm=$(find_vm_in_datastores "$VMNAME")

  if [ -n "$found_bhyve_cli_vm" ]; then
    local datastore_name=$(echo "$found_bhyve_cli_vm" | head -n 1 | cut -d':' -f1)
    local vm_dir=$(echo "$found_bhyve_cli_vm" | head -n 1 | cut -d':' -f2)/"$VMNAME"
    load_vm_config "$VMNAME" "$vm_dir" # Pass vm_dir as custom_datastore_path
  else
    # If not found in bhyve-cli datastores, check vm-bhyve directories
    local vm_bhyve_dirs
    vm_bhyve_dirs=$(get_vm_bhyve_dir) # Returns "name:path" pairs

    local vm_found_in_vm_bhyve=false
    if [ -n "$vm_bhyve_dirs" ]; then
      for datastore_pair in $vm_bhyve_dirs; do
        local current_ds_name=$(echo "$datastore_pair" | cut -d':' -f1)
        local current_ds_path=$(echo "$datastore_pair" | cut -d':' -f2)
        
        if [ -d "$current_ds_path/$VMNAME" ]; then
          # For vm-bhyve VMs, we don't use load_vm_config directly,
          # but we need to set VM_DIR and source its config.
          VM_DIR="$current_ds_path/$VMNAME"
          local conf_file="$VM_DIR/$VMNAME.conf"
          if [ -f "$conf_file" ]; then
            . "$conf_file"
            # Map vm-bhyve variables to our internal variables
            CPUS=${cpu:-N/A}
            MEMORY=${memory:-N/A}
            BOOTLOADER_TYPE=${loader:-bhyveload}
            AUTOSTART=${autostart:-no}
            LOG_FILE="$VM_DIR/vm-bhyve.log"
            CONSOLE=${console:-nmdm1}
            vm_found_in_vm_bhyve=true
            break # VM found, exit loop
          else
            display_and_log "ERROR" "VM configuration for '$VMNAME' not found in vm-bhyve directory: $conf_file"
            exit 1
          fi
        fi
      done
    fi

    if [ "$vm_found_in_vm_bhyve" = false ]; then
      display_and_log "ERROR" "VM '$VMNAME' not found in any bhyve-cli or vm-bhyve datastores."
      exit 1
    fi
  fi

  # Override BOOTLOADER_TYPE if specified for installation
  if [ -n "$INSTALL_BOOTLOADER_TYPE" ]; then
    BOOTLOADER_TYPE="$INSTALL_BOOTLOADER_TYPE"
    log "Overriding bootloader for installation to: $BOOTLOADER_TYPE"
  fi

  ensure_nmdm_device_nodes "$CONSOLE"
  sleep 1 # Give nmdm devices a moment to be ready

  log "Starting VM '$VMNAME'ருங்கள்"

  # === Stop bhyve if still active ===
  if is_vm_running "$VMNAME"; then
    log "VM '$VMNAME' is still running. Stopped..."
    pkill -f "bhyve: $VMNAME"
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
      local ISO_FILES=()
      # Populate ISO_FILES array with .iso files from ISO_DIR
      local REAL_ISO_DIR
      REAL_ISO_DIR=$(readlink -f "$ISO_DIR")
      if [ -z "$REAL_ISO_DIR" ]; then
        display_and_log "ERROR" "Failed to resolve ISO directory: $ISO_DIR"
        exit 1
      fi
      # Populate ISO_FILES array with .iso files from REAL_ISO_DIR
      while IFS= read -r -d '' file; do
        ISO_FILES+=("$file")
      done < <(find "$REAL_ISO_DIR" -maxdepth 1 -type f -name "*.iso" -print0)

      if [ ${#ISO_FILES[@]} -eq 0 ]; then
        display_and_log "ERROR" "No ISO files found in $ISO_DIR!"
        exit 1
      fi
      echo_message "Available ISOs:"
      select iso in "${ISO_FILES[@]}"; do
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
  clear # Clear screen
  local BHYVE_LOADER_CLI_ARG=""
  if [ "$BOOTLOADER_TYPE" = "bhyveload" ]; then
    run_bhyveload "$ISO_PATH" || exit 1
  else
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
  fi

  clear # Clear screen

  display_and_log "INFO" "Starting VM with nmdm console for installation..."
  local BHYVE_CMD="$BHYVE -c \"$CPUS\" -m \"$MEMORY\" -AHP -s 0,hostbridge $DISK_ARGS -s ${NEXT_DISK_DEV_NUM}:0,ahci-cd,\"$ISO_PATH\" $NETWORK_ARGS -l com1,/dev/${CONSOLE}A -s 31,lpc ${BHYVE_LOADER_CLI_ARG} \"$VMNAME\""
  log "Constructed bhyve command: $BHYVE_CMD"

  # Execute bhyve in the background
  eval "$BHYVE_CMD" >> "$LOG_FILE" 2>&1 &
  VM_PID=$!
  save_vm_pid "$VMNAME" "$VM_PID"
  log "Bhyve VM started in background with PID $VM_PID"

  echo_message ""
  echo_message ">>> Entering VM '$VMNAME' console (exit with ~.)"
  if [[ "$BOOTLOADER_TYPE" == "uefi" || "$BOOTLOADER_TYPE" == "bootrom" ]]; then
    echo_message "\e[1;33m>>> UEFI BOOT: To enter the boot menu, start pressing [ESC] repeatedly NOW.\e[0m"
  fi
  echo_message ">>> IMPORTANT: After shutting down the VM from within, you MUST type '~.' (tilde then dot) to exit this console and allow the script to continue cleanup."

  # A minimal sleep is needed for the nmdm device to be ready before cu connects.
  sleep 1

  cu -l /dev/"${CONSOLE}B" -s 115200

  log "cu session ended. Initiating cleanup..."

  cleanup_vm_processes "$VMNAME" "$CONSOLE" "$LOG_FILE"

  # Wait for the bhyve process to exit and capture its exit status.
  wait "$VM_PID"
  local BHYVE_EXIT_STATUS=$?

  # Check the exit status of the bhyve process
  if [ "$BHYVE_EXIT_STATUS" -eq 3 ] || [ "$BHYVE_EXIT_STATUS" -eq 4 ]; then
      # If bhyve exited due to a fault or error, then display error message
      display_and_log "ERROR" "Virtual machine '$VMNAME' failed to boot or installer exited with an error (exit code: $BHYVE_EXIT_STATUS). Check VM logs for details."
      exit 1
  else
      log "Bhyve process $VM_PID exited cleanly (status: $BHYVE_EXIT_STATUS)."
  fi
  display_and_log "INFO" "Installation finished. You can now start the VM with: $0 start $VMNAME"
  log "Exiting cmd_install function for VM: $VMNAME"
}