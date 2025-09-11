#!/usr/local/bin/bash

# === Subcommand: snapshot create ===
cmd_snapshot_create() {
  if [ -z "$2" ]; then
    cmd_snapshot_usage
    exit 1
  fi

  local VMNAME_ARG="$1"
  local SNAPSHOT_NAME_ARG="$2"

  # Detect VM source
  local vm_source=""
  local vm_base_dir=""
  if [ -d "$VM_CONFIG_BASE_DIR/$VMNAME_ARG" ]; then
    vm_source="bhyve-cli"
    vm_base_dir="$VM_CONFIG_BASE_DIR"
  else
    local vm_bhyve_base_dir
    vm_bhyve_base_dir=$(get_vm_bhyve_dir)
    if [ -n "$vm_bhyve_base_dir" ] && [ -d "$vm_bhyve_base_dir/$VMNAME_ARG" ]; then
      vm_source="vm-bhyve"
      vm_base_dir="$vm_bhyve_base_dir"
    fi
  fi

  if [ -z "$vm_source" ]; then
    display_and_log "ERROR" "VM '$VMNAME_ARG' not found in bhyve-cli or vm-bhyve directories."
    exit 1
  fi

  # --- Common Snapshot Setup ---
  local VM_DIR="$vm_base_dir/$VMNAME_ARG"
  local SNAPSHOT_ROOT_DIR="$VM_CONFIG_BASE_DIR/snapshots" # Centralized snapshot storage
  local VM_SNAPSHOT_DIR="$SNAPSHOT_ROOT_DIR/$VMNAME_ARG"
  local SNAPSHOT_PATH="$VM_SNAPSHOT_DIR/$SNAPSHOT_NAME_ARG"

  mkdir -p "$VM_SNAPSHOT_DIR" || { display_and_log "ERROR" "Failed to create VM snapshot root directory '$VM_SNAPSHOT_DIR'."; exit 1; }

  if [ -d "$SNAPSHOT_PATH" ]; then
    display_and_log "ERROR" "Snapshot '$SNAPSHOT_NAME_ARG' already exists for VM '$VMNAME_ARG'."
    exit 1
  fi

  mkdir -p "$SNAPSHOT_PATH" || { display_and_log "ERROR" "Failed to create snapshot directory '$SNAPSHOT_PATH'."; exit 1; }

  display_and_log "INFO" "Creating snapshot '$SNAPSHOT_NAME_ARG' for VM '$VMNAME_ARG'..."

  local VM_WAS_RUNNING=false
  if is_vm_running "$VMNAME_ARG"; then
    VM_WAS_RUNNING=true
    display_and_log "INFO" "VM '$VMNAME_ARG' is running. Suspending VM for consistent snapshot..."
    if [ "$vm_source" == "bhyve-cli" ]; then
      if ! cmd_suspend "$VMNAME_ARG"; then
        display_and_log "ERROR" "Failed to suspend VM '$VMNAME_ARG'. Aborting snapshot."
        exit 1
      fi
    else # vm-bhyve
      # Use cmd_suspend for vm-bhyve VMs as well
      if ! cmd_suspend "$VMNAME_ARG"; then
        display_and_log "ERROR" "Failed to suspend vm-bhyve VM '$VMNAME_ARG'. Aborting snapshot."
        exit 1
      fi
    fi
    log "VM '$VMNAME_ARG' suspended."
  fi

  start_spinner "Copying disk image(s) for snapshot..."

  if [ "$vm_source" == "bhyve-cli" ]; then
    load_vm_config "$VMNAME_ARG"
    local VM_DISK_PATH="$VM_DIR/$DISK"
    if ! cp "$VM_DISK_PATH" "$SNAPSHOT_PATH/disk.img"; then
      stop_spinner
      display_and_log "ERROR" "Failed to copy disk image for snapshot. Aborting."
      if $VM_WAS_RUNNING; then
        cmd_resume "$VMNAME_ARG"
        log "VM '$VMNAME_ARG' resumed after snapshot failure."
      fi
      exit 1
    fi
    # Copy vm.conf for consistency
    cp "$VM_DIR/vm.conf" "$SNAPSHOT_PATH/vm.conf"
    log "VM configuration copied."
  else # vm-bhyve
    local conf_file="$vm_base_dir/$VMNAME_ARG/$VMNAME_ARG.conf"
    if [ -f "$conf_file" ]; then
      . "$conf_file"
      local DISK_IDX=0
      while true; do
        local type_var="disk${DISK_IDX}_type"
        local name_var="disk${DISK_IDX}_name"
        local DISK_TYPE="${!type_var}"
        if [ -z "$DISK_TYPE" ]; then break; fi
        local DISK_NAME="${!name_var}"
        local DISK_PATH="$vm_base_dir/$VMNAME_ARG/$DISK_NAME"

        if [ "$DISK_TYPE" == "zvol" ]; then
          stop_spinner
          display_and_log "ERROR" "ZFS zvols are not yet supported for snapshotting. Aborting."
          if $VM_WAS_RUNNING; then
            cmd_resume "$VMNAME_ARG"
            log "VM '$VMNAME_ARG' resumed after snapshot failure."
          fi
          exit 1
        fi

        if ! cp "$DISK_PATH" "$SNAPSHOT_PATH/disk${DISK_IDX}.img"; then
          stop_spinner
          display_and_log "ERROR" "Failed to copy disk image $DISK_NAME for snapshot. Aborting."
          if $VM_WAS_RUNNING; then
            cmd_resume "$VMNAME_ARG"
            log "VM '$VMNAME_ARG' resumed after snapshot failure."
          fi
          exit 1
        fi
        DISK_IDX=$((DISK_IDX + 1))
      done
      # Copy vm-bhyve config for consistency
      cp "$conf_file" "$SNAPSHOT_PATH/$VMNAME_ARG.conf"
      log "VM-bhyve configuration copied."
    else
      stop_spinner
      display_and_log "ERROR" "VM-bhyve config file not found for snapshot: $conf_file"
      if $VM_WAS_RUNNING; then
        cmd_resume "$VMNAME_ARG"
        log "VM '$VMNAME_ARG' resumed after snapshot failure."
      fi
      exit 1
    fi
  fi # Added: Closes the if [ "$vm_source" == "bhyve-cli" ] on line 66

  stop_spinner
  log "Disk image(s) copied."

  if $VM_WAS_RUNNING; then
    display_and_log "INFO" "Resuming VM '$VMNAME_ARG' ..."
    if [ "$vm_source" == "bhyve-cli" ]; then
      if ! cmd_resume "$VMNAME_ARG"; then
        display_and_log "ERROR" "Failed to resume VM '$VMNAME_ARG'. Manual intervention may be required."
        exit 1
      fi
    else # vm-bhyve
      # Use cmd_resume for vm-bhyve VMs as well
      if ! cmd_resume "$VMNAME_ARG"; then
        display_and_log "ERROR" "Failed to resume vm-bhyve VM '$VMNAME_ARG'. Manual intervention may be required."
        exit 1
      fi
    fi
    log "VM '$VMNAME_ARG' resumed."
  fi

  display_and_log "INFO" "Snapshot '$SNAPSHOT_NAME_ARG' created successfully for VM '$VMNAME_ARG'."
}
