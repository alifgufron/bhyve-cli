#!/usr/local/bin/bash

# === Subcommand: snapshot create ===
cmd_snapshot_create() {
  local VMNAME_ARG="$1"
  local SNAPSHOT_NAME_ARG=""

  # If a snapshot name is provided, use it. Otherwise, generate one.
  if [ -n "$2" ]; then
    SNAPSHOT_NAME_ARG="$2"
  else
    SNAPSHOT_NAME_ARG="$(date +'%Y%m%d-%H%M%S')"
    display_and_log "INFO" "No snapshot name provided. Generating: $SNAPSHOT_NAME_ARG"
  fi

  if [ -z "$VMNAME_ARG" ]; then
    cmd_snapshot_usage
    exit 1
  fi

  # Use the centralized find_any_vm function to determine the VM source
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
  local vm_dir="$datastore_path/$VMNAME_ARG"

  # --- Logic for all VMs (bhyve-cli and vm-bhyve) ---
  local SNAPSHOT_ROOT_DIR="$datastore_path/snapshots" # Snapshot storage within VM's datastore
  local VM_SNAPSHOT_DIR="$SNAPSHOT_ROOT_DIR/$VMNAME_ARG"
  local SNAPSHOT_PATH="$VM_SNAPSHOT_DIR/$SNAPSHOT_NAME_ARG"

  mkdir -p "$VM_SNAPSHOT_DIR" || { display_and_log "ERROR" "Failed to create VM snapshot root directory '$VM_SNAPSHOT_DIR'."; exit 1; }
  log "Created VM snapshot root directory: $VM_SNAPSHOT_DIR"

  if [ -d "$SNAPSHOT_PATH" ]; then
    display_and_log "ERROR" "Snapshot '$SNAPSHOT_NAME_ARG' already exists for VM '$VMNAME_ARG'."
    exit 1
  fi

  mkdir -p "$SNAPSHOT_PATH" || { display_and_log "ERROR" "Failed to create snapshot directory '$SNAPSHOT_PATH'."; exit 1; }
  log "Created snapshot directory: $SNAPSHOT_PATH"

  # Check for zstd availability
  if ! command -v zstd >/dev/null 2>&1; then
    display_and_log "ERROR" "zstd command not found. Please install zstd to enable snapshot compression."
    exit 1
  fi

  display_and_log "INFO" "Creating snapshot '$SNAPSHOT_NAME_ARG' for VM '$VMNAME_ARG'..."

  local VM_WAS_RUNNING=false
  # Correctly check if VM is running using the full vm_dir path
  if is_vm_running "$VMNAME_ARG" "$vm_dir"; then
    VM_WAS_RUNNING=true
    display_and_log "INFO" "VM '$VMNAME_ARG' is running. Suspending VM for consistent snapshot..."
    # cmd_suspend is already fixed and can find the VM on its own
    if ! cmd_suspend "$VMNAME_ARG"; then
      display_and_log "ERROR" "Failed to suspend VM '$VMNAME_ARG'. Aborting snapshot."
      rm -rf "$SNAPSHOT_PATH"
      exit 1
    fi
    log "VM '$VMNAME_ARG' suspended."
  fi

  start_spinner "Copying disk image(s) for snapshot..."

  # Load the VM config to get disk details
  # Load the VM config to get disk details
  load_vm_config "$VMNAME_ARG" "$vm_dir"

  # --- Copy Disks ---
  local DISK_IDX=0
  while true; do
    local CURRENT_DISK_VAR="DISK_${DISK_IDX}"
    local CURRENT_DISK_FILENAME="${!CURRENT_DISK_VAR}"
    if [ -z "$CURRENT_DISK_FILENAME" ]; then break; fi

    local VM_DISK_PATH="$vm_dir/$CURRENT_DISK_FILENAME"
    local SNAPSHOT_DISK_PATH="$SNAPSHOT_PATH/$CURRENT_DISK_FILENAME"

    if [ ! -f "$VM_DISK_PATH" ]; then
        log "WARNING: Disk file '$VM_DISK_PATH' not found, skipping."
        DISK_IDX=$((DISK_IDX + 1))
        continue
    fi

    if ! cp "$VM_DISK_PATH" "$SNAPSHOT_DISK_PATH"; then
      stop_spinner
      display_and_log "ERROR" "Failed to copy disk image '$CURRENT_DISK_FILENAME' for snapshot. Aborting."
      rm -rf "$SNAPSHOT_PATH"
      if $VM_WAS_RUNNING; then
        cmd_resume "$VMNAME_ARG"
        log "VM '$VMNAME_ARG' resumed after snapshot failure."
      fi
      exit 1
    fi
    log "Copied disk image: $CURRENT_DISK_FILENAME to $SNAPSHOT_DISK_PATH"

    # Compress the copied disk image
    log "Compressing '$SNAPSHOT_DISK_PATH' with zstd..."
    if ! zstd -q "$SNAPSHOT_DISK_PATH" -o "$SNAPSHOT_DISK_PATH.zst"; then
      stop_spinner
      display_and_log "ERROR" "Failed to compress disk image '$CURRENT_DISK_FILENAME' with zstd. Aborting."
      rm -rf "$SNAPSHOT_PATH"
      if $VM_WAS_RUNNING; then
        cmd_resume "$VMNAME_ARG"
        log "VM '$VMNAME_ARG' resumed after snapshot failure."
      fi
      exit 1
    fi
    rm "$SNAPSHOT_DISK_PATH" # Remove uncompressed copy
    log "Compressed '$SNAPSHOT_DISK_PATH.zst'. Original removed."

    # Update vm.conf in snapshot to point to the .zst file
    sed -i '' "s|${CURRENT_DISK_FILENAME}|${CURRENT_DISK_FILENAME}.zst|" "$SNAPSHOT_PATH/vm.conf"
    log "Updated vm.conf in snapshot to reference .zst file."

    DISK_IDX=$((DISK_IDX + 1))
  done

  # Copy vm.conf for consistency
  cp "$vm_dir/vm.conf" "$SNAPSHOT_PATH/vm.conf"
  log "VM configuration copied."

  stop_spinner
  log "Disk image(s) copied."

  if $VM_WAS_RUNNING; then
    display_and_log "INFO" "Resuming VM '$VMNAME_ARG' ..."
    # cmd_resume is already fixed and can find the VM on its own
    if ! cmd_resume "$VMNAME_ARG"; then
      display_and_log "ERROR" "Failed to resume VM '$VMNAME_ARG'. Manual intervention may be required."
    fi
    log "VM '$VMNAME_ARG' resumed."
  fi

  display_and_log "INFO" "Snapshot '$SNAPSHOT_NAME_ARG' created successfully for VM '$VMNAME_ARG'."
}