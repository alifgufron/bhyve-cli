#!/usr/local/bin/bash

# === Subcommand: verify ===
cmd_verify() {
  local TARGET_VMNAME="$1" # Capture the optional VM name argument
  start_spinner "Starting VM configuration verification..."

  local VERIFY_STATUS="SUCCESS"
  local VM_COUNT=0
  local ERROR_COUNT=0

  # Get all bhyve-cli datastores
  local bhyve_cli_datastores
  bhyve_cli_datastores=$(get_all_bhyve_cli_datastores)

  local VMS_TO_VERIFY_PATHS=()
  if [ -n "$TARGET_VMNAME" ]; then
    # Verify a specific VM
    local found_vm_info
    found_vm_info=$(find_any_vm "$TARGET_VMNAME")
    if [ -z "$found_vm_info" ]; then
      stop_spinner "Error: VM '$TARGET_VMNAME' not found in any bhyve-cli or vm-bhyve datastores."
      exit 1
    fi
    local vm_source=$(echo "$found_vm_info" | cut -d':' -f1)
    local datastore_path=$(echo "$found_vm_info" | cut -d':' -f3)
    local vm_dir_path="$datastore_path/$TARGET_VMNAME"

    if [ "$vm_source" == "vm-bhyve" ]; then
      stop_spinner "Error: Verification for vm-bhyve VMs is not directly supported by bhyve-cli."
      exit 1
    fi
    VMS_TO_VERIFY_PATHS+=("$vm_dir_path")
  else
    # Verify all bhyve-cli VMs
    for datastore_pair in $bhyve_cli_datastores; do
      local ds_name=$(echo "$datastore_pair" | cut -d':' -f1)
      local ds_path=$(echo "$datastore_pair" | cut -d':' -f2)

      for VM_DIR_PATH_RAW in "$ds_path"/*/; do
        local VMNAME_CHECK=$(basename "$VM_DIR_PATH_RAW")
        if [ "$VMNAME_CHECK" = "templates" ] || [ "$VMNAME_CHECK" = "snapshots" ]; then
          log "Skipping special directory: $VMNAME_CHECK."
          continue
        fi
        if [ -d "$VM_DIR_PATH_RAW" ]; then
          VMS_TO_VERIFY_PATHS+=("$VM_DIR_PATH_RAW")
        fi
      done
    done
  fi

  if [ ${#VMS_TO_VERIFY_PATHS[@]} -eq 0 ]; then
    stop_spinner "No bhyve-cli virtual machines found to verify."
    exit 0
  fi

  for VM_DIR_PATH_RAW in "${VMS_TO_VERIFY_PATHS[@]}"; do
    local VMNAME=$(basename "$VM_DIR_PATH_RAW")
    local VM_DIR_PATH=$(readlink -f "$VM_DIR_PATH_RAW") # Resolve symlinks
    local CONF_FILE="$VM_DIR_PATH/vm.conf"
    
    log "Verifying VM: $VMNAME (Path: $VM_DIR_PATH)"
    VM_COUNT=$((VM_COUNT + 1))

    if [ ! -f "$CONF_FILE" ]; then
      log "ERROR: Configuration file '$CONF_FILE' not found."
      VERIFY_STATUS="FAILED"
      ERROR_COUNT=$((ERROR_COUNT + 1))
      continue
    fi

    # Load VM config using the fixed load_vm_config. This will set global variables.
    # Use a subshell to prevent polluting the main script's environment with VM config vars
    # and to catch errors from sourcing.
    if ! (load_vm_config "$VMNAME" "$VM_DIR_PATH") > /dev/null 2>&1; then
      log "ERROR: Failed to load configuration for '$VMNAME' from '$CONF_FILE'. Syntax error or missing variables."
      VERIFY_STATUS="FAILED"
      ERROR_COUNT=$((ERROR_COUNT + 1))
      continue
    fi

    # Now, source the config again in the current shell to get the variables for checks
    # This is necessary because load_vm_config is called in a subshell above to catch errors.
    # We need the variables in the current shell for the checks below.
    # shellcheck disable=SC1090
    . "$CONF_FILE"

    # --- Disk Checks ---
    local DISK_IDX=0
    while true; do
      local CURRENT_DISK_VAR="DISK_${DISK_IDX}"
      local CURRENT_DISK_FILENAME="${!CURRENT_DISK_VAR}"

      if [ -z "$CURRENT_DISK_FILENAME" ]; then
        # If DISK_0 is not found, check for old 'DISK' variable for compatibility
        if [ "$DISK_IDX" -eq 0 ] && [ -n "$DISK" ]; then
          CURRENT_DISK_FILENAME="$DISK"
        else
          break # No more disks configured
        fi
      fi

      local ACTUAL_DISK_PATH="$CURRENT_DISK_FILENAME"
      if [[ ! "$ACTUAL_DISK_PATH" =~ ^/ ]]; then
        ACTUAL_DISK_PATH="$VM_DIR_PATH/$CURRENT_DISK_FILENAME" # Use VM_DIR_PATH for disk path
      fi

      if [ ! -f "$ACTUAL_DISK_PATH" ]; then
        log "ERROR: Disk image '$ACTUAL_DISK_PATH' not found for VM '$VMNAME'."
        VERIFY_STATUS="FAILED"
        ERROR_COUNT=$((ERROR_COUNT + 1))
      else
        log "INFO: Disk image '$ACTUAL_DISK_PATH': OK"
      fi
      DISK_IDX=$((DISK_IDX + 1))
    done

    # --- NIC Checks ---
    local NIC_IDX=0
    while true; do
      local CURRENT_TAP_VAR="TAP_${NIC_IDX}"
      local CURRENT_MAC_VAR="MAC_${NIC_IDX}"
      local CURRENT_BRIDGE_VAR="BRIDGE_${NIC_IDX}"

      local CURRENT_TAP="${!CURRENT_TAP_VAR}"
      local CURRENT_MAC="${!CURRENT_MAC_VAR}"
      local CURRENT_BRIDGE="${!CURRENT_BRIDGE_VAR}"

      if [ -z "$CURRENT_TAP" ] && [ -z "$CURRENT_MAC" ] && [ -z "$CURRENT_BRIDGE" ]; then
        break # No more NICs configured
      fi

      if [ -z "$CURRENT_MAC" ]; then
        log "ERROR: MAC address for NIC $NIC_IDX is not set for VM '$VMNAME'."
        VERIFY_STATUS="FAILED"
        ERROR_COUNT=$((ERROR_COUNT + 1))
      fi
      # Basic check for bridge existence (assuming bridge is a network interface)
      if [ -n "$CURRENT_BRIDGE" ] && [ ! -e "/dev/$CURRENT_BRIDGE" ]; then
        log "WARNING: Bridge '$CURRENT_BRIDGE' for NIC $NIC_IDX not found for VM '$VMNAME'. This might be created dynamically or is a logical bridge."
      fi
      NIC_IDX=$((NIC_IDX + 1))
    done

    # --- Console Check ---
    if [ -n "$CONSOLE" ] && [ ! -e "/dev/$CONSOLE" ]; then
      log "WARNING: Console device '/dev/$CONSOLE' not found for VM '$VMNAME'. This might be created at VM start."
    fi

    # --- Bootloader Firmware Check ---
    if [ "$BOOTLOADER_TYPE" = "uefi" ] || [ "$BOOTLOADER_TYPE" = "bootrom" ]; then
      local FIRMWARE_FILE=""
      if [ -n "$UEFI_FIRMWARE_PATH" ]; then
        FIRMWARE_FILE="$(readlink -f "$UEFI_FIRMWARE_PATH")"
      else
        FIRMWARE_FILE="/usr/local/share/uefi-firmware/BHYVE_UEFI.fd"
      fi

      if [ ! -f "$FIRMWARE_FILE" ]; then
        log "ERROR: UEFI firmware file '$FIRMWARE_FILE' not found for VM '$VMNAME'."
        VERIFY_STATUS="FAILED"
        ERROR_COUNT=$((ERROR_COUNT + 1))
      fi
    elif [ "$BOOTLOADER_TYPE" = "grub2-bhyve" ]; then
      local GRUB_CONF_FILE="$(readlink -f "$VM_DIR_PATH/grub.conf")" # Use VM_DIR_PATH
      if [ ! -f "$GRUB_CONF_FILE" ]; then
        log "ERROR: GRUB configuration file '$GRUB_CONF_FILE' not found for VM '$VMNAME'."
        VERIFY_STATUS="FAILED"
        ERROR_COUNT=$((ERROR_COUNT + 1))
      fi
    fi
  done

  local final_message=""
  if [ "$ERROR_COUNT" -eq 0 ]; then
    final_message="All $VM_COUNT VM configurations verified successfully."
  else
    final_message="Verification completed with $ERROR_COUNT error(s) for $VM_COUNT VM(s). Please review the logs for details."
  fi
  stop_spinner "$final_message"
}
