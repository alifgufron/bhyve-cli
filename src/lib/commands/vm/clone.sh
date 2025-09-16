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
  local found_source_vm
  found_source_vm=$(find_vm_in_datastores "$SOURCE_VMNAME")

  local SOURCE_VM_DIR=""
  local SOURCE_CONF_FILE=""
  local SOURCE_VM_DATASTORE_NAME=""

  if [ -n "$found_source_vm" ]; then
    SOURCE_VM_DATASTORE_NAME=$(echo "$found_source_vm" | head -n 1 | cut -d':' -f1)
    SOURCE_VM_DIR=$(echo "$found_source_vm" | head -n 1 | cut -d':' -f2)/"$SOURCE_VMNAME"
    SOURCE_CONF_FILE="$SOURCE_VM_DIR/vm.conf"
  else
    # Check vm-bhyve directories for source VM
    local vm_bhyve_dirs
    vm_bhyve_dirs=$(get_vm_bhyve_dir)

    local source_vm_found_in_vm_bhyve=false
    if [ -n "$vm_bhyve_dirs" ]; then
      for datastore_pair in $vm_bhyve_dirs; do
        local current_ds_name=$(echo "$datastore_pair" | cut -d':' -f1)
        local current_ds_path=$(echo "$datastore_pair" | cut -d':' -f2)
        
        if [ -d "$current_ds_path/$SOURCE_VMNAME" ]; then
          display_and_log "ERROR" "Cloning vm-bhyve VMs is not directly supported by bhyve-cli. Please use vm-bhyve's cloning mechanism."
          exit 1
        fi
      done
    fi
    display_and_log "ERROR" "Source VM '$SOURCE_VMNAME' not found in any bhyve-cli datastores."
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
  if is_vm_running "$SOURCE_VMNAME"; then
    ORIGINAL_VM_STATE=$(get_vm_status "$(get_vm_pid "$SOURCE_VMNAME")")
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
  cp -a "$SOURCE_VM_DIR/." "$NEW_VM_DIR/" || {
    stop_spinner
    display_and_log "ERROR" "Failed to copy VM files."
    rm -rf "$NEW_VM_DIR"
    exit 1
  }
  rm -f "$NEW_VM_DIR/vm.pid" # Ensure vm.pid is not copied
  rm -f "$NEW_VM_DIR/vm.log" # Ensure vm.log is not copied
  stop_spinner

  # Load source VM config to get details for new config
  # Temporarily load source config to get values
  local ORIGINAL_VMNAME="$VMNAME"
  local ORIGINAL_VM_DIR="$VM_DIR"
  local ORIGINAL_CONF_FILE="$CONF_FILE"
  local ORIGINAL_LOG_FILE="$LOG_FILE"

  VMNAME="$SOURCE_VMNAME"
  VM_DIR="$SOURCE_VM_DIR"
  CONF_FILE="$SOURCE_CONF_FILE"
  LOG_FILE="$SOURCE_VM_DIR/vm.log"
  load_vm_config "$SOURCE_VMNAME" "$SOURCE_VM_DIR" # Pass SOURCE_VM_DIR as custom_datastore_path

  # Generate new UUID
  local NEW_UUID=$(uuidgen)

  # Generate new MAC addresses for all NICs
  local NIC_IDX=0
  local NEW_MAC_ADDRESSES=()
  while grep -q "^MAC_${NIC_IDX}=" "$NEW_CONF_FILE"; do
    NEW_MAC_ADDRESSES+=("58:9c:fc$(jot -r -w ":%02x" -s "" 3 0 255)")
    NIC_IDX=$((NIC_IDX + 1))
  done

  # Generate new TAP numbers for all NICs
  local NEW_TAP_NUMS=()
  local TAP_BASE_NUM=$(get_next_available_tap_num)
  for (( i=0; i<NIC_IDX; i++ )); do
    NEW_TAP_NUMS+=("tap$((TAP_BASE_NUM + i))")
  done

  # Update new vm.conf file
  log "Updating new VM configuration file: $NEW_CONF_FILE"
  sed -i '' "s/^VMNAME=.*/VMNAME=${NEW_VMNAME}/" "$NEW_CONF_FILE"
  sed -i '' "s/^UUID=.*/UUID=${NEW_UUID}/" "$NEW_CONF_FILE"
  sed -i '' "s/^CONSOLE=.*/CONSOLE=nmdm-${NEW_VMNAME}.1/" "$NEW_CONF_FILE"
  sed -i '' "s|^LOG=.*|LOG=${NEW_VM_DIR}/vm.log|" "$NEW_CONF_FILE"

  for (( i=0; i<NIC_IDX; i++ )); do
    sed -i '' "s/^TAP_${i}=.*/TAP_${i}=${NEW_TAP_NUMS[$i]}/" "$NEW_CONF_FILE"
    sed -i '' "s/^MAC_${i}=.*/MAC_${i}=${NEW_MAC_ADDRESSES[$i]}/" "$NEW_CONF_FILE"
  done

  # Restore original VM config variables
  VMNAME="$ORIGINAL_VMNAME"
  VM_DIR="$ORIGINAL_VM_DIR"
  CONF_FILE="$ORIGINAL_CONF_FILE"
  LOG_FILE="$ORIGINAL_LOG_FILE"

  display_and_log "INFO" "VM '$SOURCE_VMNAME' successfully cloned to '$NEW_VMNAME'."
  # Resume VM if it was suspended before cloning
  if [ "$SHOULD_RESUME_AFTER_CLONE" = true ]; then
    display_and_log "INFO" "Resuming VM '$SOURCE_VMNAME' after cloning..."
    cmd_resume "$SOURCE_VMNAME" || display_and_log "WARNING" "Failed to resume VM '$SOURCE_VMNAME'. Please resume manually."
  fi
}
