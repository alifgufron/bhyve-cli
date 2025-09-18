#!/usr/local/bin/bash

# === Subcommand: clone ===
cmd_clone() {
  local SOURCE_VMNAME=""
  local NEW_VMNAME=""
  local DATASTORE_NAME="default" # Default datastore for the new VM

  # Parse named arguments
  while (( "$#" )); do
    case "$1" in
      --source)
        shift
        SOURCE_VMNAME="$1"
        ;;
      --new-name)
        shift
        NEW_VMNAME="$1"
        ;;
      --datastore)
        shift
        DATASTORE_NAME="$1"
        ;;
      * )
        display_and_log "ERROR" "Invalid option: $1"
        cmd_clone_usage
        exit 1
        ;;
    esac
    shift
  done

  if [ -z "$SOURCE_VMNAME" ] || [ -z "$NEW_VMNAME" ]; then
    cmd_clone_usage
    exit 1
  fi

  # Find Source VM across all datastores
  local found_source_vm_info
  found_source_vm_info=$(find_any_vm "$SOURCE_VMNAME")

  if [ -z "$found_source_vm_info" ]; then
    display_and_log "ERROR" "Source VM '$SOURCE_VMNAME' not found in any bhyve-cli or vm-bhyve datastores."
    exit 1
  fi

  local source_vm_source
  local source_datastore_path
  source_vm_source=$(echo "$found_source_vm_info" | cut -d':' -f1)
  source_datastore_path=$(echo "$found_source_vm_info" | cut -d':' -f3)
  local SOURCE_VM_DIR="$source_datastore_path/$SOURCE_VMNAME"

  # Check if source VM is a vm-bhyve instance
  if [ "$source_vm_source" == "vm-bhyve" ]; then
    display_and_log "ERROR" "Cloning vm-bhyve VMs is not directly supported by bhyve-cli. Please use vm-bhyve's cloning mechanism."
    exit 1
  fi

  # Get the absolute path for the destination datastore
  local NEW_VM_BASE_PATH
  NEW_VM_BASE_PATH=$(get_datastore_path "$DATASTORE_NAME")
  if [ -z "$NEW_VM_BASE_PATH" ]; then
    display_and_log "ERROR" "Destination datastore '$DATASTORE_NAME' not found. Please check 'datastore list'."
    exit 1
  fi

  local NEW_VM_DIR="$NEW_VM_BASE_PATH/$NEW_VMNAME"
  local NEW_CONF_FILE="$NEW_VM_DIR/vm.conf"

  local SHOULD_RESUME_AFTER_CLONE=false
  local ORIGINAL_VM_STATE="stopped" # To track if VM was running/suspended before clone

  # Load source VM config to get its current state
  load_vm_config "$SOURCE_VMNAME" "$SOURCE_VM_DIR"

  if is_vm_running "$SOURCE_VMNAME" "$SOURCE_VM_DIR"; then
    ORIGINAL_VM_STATE=$(get_vm_status "$(get_vm_pid "$SOURCE_VMNAME" "$SOURCE_VM_DIR")")
    display_and_log "WARNING" "Source VM '$SOURCE_VMNAME' is $ORIGINAL_VM_STATE."
    echo_message "Do you want to:"
    echo_message "  1) Stop VM and proceed with clone"
    echo_message "  2) Suspend VM and proceed with clone (will resume after clone)"
    echo_message "  3) Abort clone operation"
    read -rp "Enter your choice [1-3]: " CLONE_CHOICE

    case "$CLONE_CHOICE" in
      1)
        display_and_log "INFO" "Stopping VM '$SOURCE_VMNAME' before cloning..."
        cmd_stop "$SOURCE_VMNAME" --silent || { display_and_log "ERROR" "Failed to stop VM '$SOURCE_VMNAME'. Aborting clone."; exit 1; }
        sleep 2 # Give it a moment to ensure it's stopped
        ;;
      2)
        display_and_log "INFO" "Suspending VM '$SOURCE_VMNAME' before cloning..."
        cmd_suspend "$SOURCE_VMNAME" || { display_and_log "ERROR" "Failed to suspend VM '$SOURCE_VMNAME'. Aborting clone."; exit 1; }
        SHOULD_RESUME_AFTER_CLONE=true # Set flag to resume later
        ;;
      3)
        display_and_log "INFO" "Clone operation aborted by user."
        exit 0
        ;;
      *)
        display_and_log "ERROR" "Invalid choice. Aborting clone operation."
        exit 1
        ;;
    esac
  fi

  if [ -d "$NEW_VM_DIR" ]; then
    display_and_log "ERROR" "Destination VM '$NEW_VMNAME' already exists."
    exit 1
  fi

  display_and_log "INFO" "Cloning VM '$SOURCE_VMNAME' to '$NEW_VMNAME'..."
  start_spinner "Copying VM files..."

  mkdir -p "$NEW_VM_DIR" || { display_and_log "ERROR" "Failed to create destination VM directory '$NEW_VM_DIR'."; exit 1; }

  # Copy all files from source VM directory to new VM directory
  # This includes vm.conf and disk images
  cp -a "$SOURCE_VM_DIR/." "$NEW_VM_DIR/" || {
    stop_spinner
    display_and_log "ERROR" "Failed to copy VM files."
    rm -rf "$NEW_VM_DIR"
    exit 1
  }
  rm -f "$NEW_VM_DIR/vm.pid" # Ensure vm.pid is not copied
  rm -f "$NEW_VM_DIR/vm.log" # Ensure vm.log is not copied
  stop_spinner

  # Load the new VM's config to modify it
  load_vm_config "$NEW_VMNAME" "$NEW_VM_DIR"

  # Generate new UUID
  local NEW_UUID=$(uuidgen)

  # Update new vm.conf file
  log "Updating new VM configuration file: $NEW_CONF_FILE"
  sed -i '' "s/^VMNAME=.*/VMNAME=${NEW_VMNAME}/" "$NEW_CONF_FILE"
  sed -i '' "s/^UUID=.*/UUID=${NEW_UUID}/" "$NEW_CONF_FILE"
  sed -i '' "s/^CONSOLE=.*/CONSOLE=nmdm-${NEW_VMNAME}.1/" "$NEW_CONF_FILE"
  sed -i '' "s|^LOG=.*|LOG=${NEW_VM_DIR}/vm.log|" "$NEW_CONF_FILE"

  # Regenerate MAC addresses for all NICs
  local NIC_IDX=0
  while grep -q "^BRIDGE_${NIC_IDX}=" "$NEW_CONF_FILE"; do
    local NEW_MAC_ADDR=$(generate_mac_address)
    sed -i '' "s/^MAC_${NIC_IDX}=.*/MAC_${NIC_IDX}=${NEW_MAC_ADDR}/" "$NEW_CONF_FILE"
    log "Generated new MAC for NIC${NIC_IDX}: ${NEW_MAC_ADDR}"
    NIC_IDX=$((NIC_IDX + 1))
  done

  display_and_log "INFO" "VM '$SOURCE_VMNAME' successfully cloned to '$NEW_VMNAME'."
  # Resume VM if it was suspended before cloning
  if [ "$SHOULD_RESUME_AFTER_CLONE" = true ]; then
    display_and_log "INFO" "Resuming VM '$SOURCE_VMNAME' after cloning..."
    cmd_resume "$SOURCE_VMNAME" || display_and_log "WARNING" "Failed to resume VM '$SOURCE_VMNAME'. Please resume manually."
  fi
}