#!/usr/local/bin/bash

# === Subcommand: verify ===
cmd_verify() {
  start_spinner "Starting VM configuration verification..."

  local VERIFY_STATUS="SUCCESS"
  local VM_COUNT=0
  local ERROR_COUNT=0

  if [ ! -d "$VM_CONFIG_BASE_DIR" ] || [ -z "$(ls -A "$VM_CONFIG_BASE_DIR")" ]; then
    stop_spinner "No virtual machines configured to verify."
    exit 0
  fi

  for VM_DIR_PATH_RAW in "$VM_CONFIG_BASE_DIR"/*/; do
    if [ -d "$VM_DIR_PATH_RAW" ]; then
      VM_COUNT=$((VM_COUNT + 1))
      local VM_DIR_PATH=$(readlink -f "$VM_DIR_PATH_RAW") # Resolve symlinks
      local VMNAME=$(basename "$VM_DIR_PATH")
      local CONF_FILE="$VM_DIR_PATH/vm.conf"
      
      log "Verifying VM: $VMNAME"

      if [ ! -f "$CONF_FILE" ]; then
        log "ERROR: Configuration file '$CONF_FILE' not found."
        VERIFY_STATUS="FAILED"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        continue
      fi

      # Load VM config to check variables. Use a subshell to avoid polluting current shell.
      local VM_CONF_CONTENT
      VM_CONF_CONTENT=$(cat "$CONF_FILE")
      if ! (eval "$VM_CONF_CONTENT") > /dev/null 2>&1; then
        log "ERROR: Syntax error in '$CONF_FILE'."
        VERIFY_STATUS="FAILED"
        ERROR_COUNT=$((ERROR_COUNT + 1))
      else
        log "INFO: Configuration file syntax: OK"
      fi

      # Temporarily set VM_DIR for this check
      local ORIGINAL_VM_DIR="$VM_DIR"
      VM_DIR="$VM_DIR_PATH"
      
      # Source again to get variables for disk and other checks
      # Clear previous VM's configuration variables to prevent pollution
      unset VMNAME UUID CPUS MEMORY TAP_0 MAC_0 BRIDGE_0 NIC_0_TYPE DISK DISKSIZE CONSOLE LOG AUTOSTART BOOTLOADER_TYPE VNC_PORT VNC_WAIT UEFI_FIRMWARE_PATH
      for i in $(seq 1 10); do # Unset indexed variables up to DISK_10, NIC_10 etc.
        unset DISK_${i} DISK_${i}_TYPE TAP_${i} MAC_${i} BRIDGE_${i} NIC_${i}_TYPE
      done
      source "$CONF_FILE"

      log "DEBUG: DISK_1 value: ${DISK_1}"
      log "DEBUG: DISK_2 value: ${DISK_2}"
      log "DEBUG: UEFI_FIRMWARE_PATH value: ${UEFI_FIRMWARE_PATH}"

      # --- Disk Checks ---
      local DISK_IDX=0
      while true; do
        local CURRENT_DISK_VAR="DISK"
        if [ "$DISK_IDX" -gt 0 ]; then
          CURRENT_DISK_VAR="DISK_${DISK_IDX}"
        fi
        local CURRENT_DISK_FILENAME="${!CURRENT_DISK_VAR}"

        if [ -z "$CURRENT_DISK_FILENAME" ]; then
          break # No more disks configured
        fi

        local ACTUAL_DISK_PATH="$CURRENT_DISK_FILENAME"
        if [[ ! "$ACTUAL_DISK_PATH" =~ ^/ ]]; then
          ACTUAL_DISK_PATH="$VM_DIR/$CURRENT_DISK_FILENAME"
        fi

        if [ ! -f "$ACTUAL_DISK_PATH" ]; then
          log "ERROR: Disk image '$ACTUAL_DISK_PATH' not found."
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

        if [ -z "$CURRENT_TAP" ]; then
          break # No more NICs configured
        fi

        if [ ! -e "/dev/$CURRENT_TAP" ]; then
          log "WARNING: TAP device '/dev/$CURRENT_TAP' for NIC $NIC_IDX not found. This might be created at VM start."
        fi
        if [ -z "$CURRENT_MAC" ]; then
          log "ERROR: MAC address for NIC $NIC_IDX is not set."
          VERIFY_STATUS="FAILED"
          ERROR_COUNT=$((ERROR_COUNT + 1))
        fi
        # Basic check for bridge existence (assuming bridge is a network interface)
        if [ -n "$CURRENT_BRIDGE" ] && [ ! -e "/dev/$CURRENT_BRIDGE" ]; then
          log "WARNING: Bridge '$CURRENT_BRIDGE' for NIC $NIC_IDX not found. This might be created dynamically or is a logical bridge."
        fi
        NIC_IDX=$((NIC_IDX + 1))
      done

      # --- Console Check ---
      if [ -n "$CONSOLE" ] && [ ! -e "/dev/$CONSOLE" ]; then
        log "WARNING: Console device '/dev/$CONSOLE' not found. This might be created at VM start."
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
          log "ERROR: UEFI firmware file '$FIRMWARE_FILE' not found."
          VERIFY_STATUS="FAILED"
          ERROR_COUNT=$((ERROR_COUNT + 1))
        fi
      elif [ "$BOOTLOADER_TYPE" = "grub2-bhyve" ]; then
        local GRUB_CONF_FILE="$(readlink -f "$VM_DIR/grub.conf")"
        if [ ! -f "$GRUB_CONF_FILE" ]; then
          log "ERROR: GRUB configuration file '$GRUB_CONF_FILE' not found."
          VERIFY_STATUS="FAILED"
          ERROR_COUNT=$((ERROR_COUNT + 1))
        fi
      fi

      # Restore original VM_DIR
      VM_DIR="$ORIGINAL_VM_DIR"
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