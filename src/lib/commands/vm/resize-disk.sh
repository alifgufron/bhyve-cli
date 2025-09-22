#!/usr/local/bin/bash

# === Subcommand: resize-disk ===
cmd_resize_disk() {
  local VMNAME_ARG=""
  local NEW_SIZE_GB=""
  local DISK_INDEX=0 # Default to primary disk (DISK_0)

  # Parse named arguments
  while (( "$#" )); do
    case "$1" in
      --disk-index) shift; DISK_INDEX="$1" ;;
      *)
        if [ -z "$VMNAME_ARG" ]; then VMNAME_ARG="$1";
        elif [ -z "$NEW_SIZE_GB" ]; then NEW_SIZE_GB="$1";
        else
          display_and_log "ERROR" "Invalid option or too many arguments: $1"
          cmd_resize_disk_usage
          exit 1
        fi
        ;;
    esac
    shift
  done

  if [ -z "$VMNAME_ARG" ] || [ -z "$NEW_SIZE_GB" ]; then
    cmd_resize_disk_usage
    exit 1
  fi

  # Find VM across all datastores
  local found_vm_info
  found_vm_info=$(find_any_vm "$VMNAME_ARG")

  if [ -z "$found_vm_info" ]; then
    display_and_log "ERROR" "VM '$VMNAME_ARG' not found in any bhyve-cli or vm-bhyve datastores."
    exit 1
  fi

  local vm_source
  local datastore_path
  vm_source=$(echo "$found_vm_info" | cut -d':' -f1)
  datastore_path=$(echo "$found_vm_info" | cut -d':' -f3)
  local vm_dir="$datastore_path/$VMNAME_ARG" # Define vm_dir here

  # If it's a vm-bhyve VM, we don't modify it directly
  if [ "$vm_source" == "vm-bhyve" ]; then
    display_and_log "ERROR" "Resizing disks for vm-bhyve VMs is not directly supported by bhyve-cli. Please use vm-bhyve's mechanism."
    exit 1
  fi

  # Load VM config using the found datastore_path. This sets the global VMNAME, VM_DIR, CONF_FILE etc.
  load_vm_config "$VMNAME_ARG" "$vm_dir"

  # Explicitly source the vm.conf file here to ensure variables are available in this script's scope
  # shellcheck disable=SC1090
  . "$CONF_FILE"

  log "DEBUG: resize-disk.sh - DISK_0 after explicit source: $DISK_0"
  local DISK_VAR="DISK_${DISK_INDEX}"
  local DISK_PATH_VAR_NAME="${DISK_VAR}" # e.g., DISK_0, DISK_1
  local DISK_PATH_VALUE="${!DISK_PATH_VAR_NAME}" # Get the value of DISK_0 or DISK_1 etc.

  if [ -z "$DISK_PATH_VALUE" ]; then
    display_and_log "ERROR" "Disk with index $DISK_INDEX not found for VM '$VMNAME_ARG'."
    exit 1
  fi

  local DISK_PATH=""
  if [[ "$DISK_PATH_VALUE" =~ ^/ ]]; then
    # Absolute path
    DISK_PATH="$DISK_PATH_VALUE"
  else
    # Relative path
    DISK_PATH="$VM_DIR/$DISK_PATH_VALUE"
  fi

  # === Check if VM is running ===
  if is_vm_running "$VMNAME_ARG" "$vm_dir"; then
    display_and_log "ERROR" "VM '$VMNAME' is currently running. Please stop the VM before resizing its disk."
    exit 1
  fi

  if [ ! -f "$DISK_PATH" ]; then
    display_and_log "ERROR" "Disk image for VM '$VMNAME' not found: $DISK_PATH"
    exit 1
  fi

  # === Get current disk size in GB ===
  CURRENT_SIZE_BYTES=$(stat -f %z "$DISK_PATH")
  CURRENT_SIZE_GB=$((CURRENT_SIZE_BYTES / 1024 / 1024 / 1024))

  if (( NEW_SIZE_GB <= CURRENT_SIZE_GB )); then
    display_and_log "ERROR" "New size ($NEW_SIZE_GB GB) must be greater than current size ($CURRENT_SIZE_GB GB)."
    exit 1
  fi

  log "Resizing disk (index $DISK_INDEX) for VM '$VMNAME' from ${CURRENT_SIZE_GB}GB to ${NEW_SIZE_GB}GB..."
  truncate -s "${NEW_SIZE_GB}G" "$DISK_PATH"
  if [ $? -ne 0 ]; then
    display_and_log "ERROR" "Failed to resize disk image."
    exit 1
  fi

  # === Update DISK_X_SIZE in vm.conf ===
  local DISK_SIZE_CONF_VAR="DISK_${DISK_INDEX}_SIZE"
  local DISK_CONF_VAR="DISK_${DISK_INDEX}" # For cases where DISK_0_SIZE might not exist but DISK_0 does

  # Check if ${DISK_SIZE_CONF_VAR} exists, if so, update it. Otherwise, add it.
  if grep -q "^${DISK_SIZE_CONF_VAR}=" "$CONF_FILE"; then
    sed -i '' "s/^${DISK_SIZE_CONF_VAR}=.*/${DISK_SIZE_CONF_VAR}=${NEW_SIZE_GB}G/" "$CONF_FILE"
  else
    # If ${DISK_SIZE_CONF_VAR} doesn't exist, but ${DISK_CONF_VAR} does, update ${DISK_SIZE_CONF_VAR}.
    # This handles cases where DISK_0 might have been created without an explicit DISK_0_SIZE entry.
    if grep -q "^${DISK_CONF_VAR}=" "$CONF_FILE"; then
      echo "${DISK_SIZE_CONF_VAR}=${NEW_SIZE_GB}G" >> "$CONF_FILE"
    else
      # This case should ideally not happen if DISK_INDEX is valid
      display_and_log "WARNING" "Neither ${DISK_SIZE_CONF_VAR} nor ${DISK_CONF_VAR} found in vm.conf for VM '$VMNAME'. Cannot update size in config."
    fi
  fi
  log "Disk resized successfully and vm.conf updated."
  display_and_log "INFO" "Disk (index $DISK_INDEX) for VM '$VMNAME' has been resized to ${NEW_SIZE_GB}GB."
  display_and_log "INFO" "Note: You may need to extend the partition inside the VM operating system."
}
