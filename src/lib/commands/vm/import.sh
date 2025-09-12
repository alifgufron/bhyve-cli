#!/usr/local/bin/bash

# === Subcommand: import ===
cmd_import() {
  if [ -z "$1" ]; then
    cmd_import_usage
    exit 1
  fi

  local ARCHIVE_PATH="$1"
  local NEW_VM_NAME="$2" # Optional new VM name

  # Get the VM name from the archive (assuming it's the top-level directory)
  start_spinner "Checking archive..."

  local VMNAME_IN_ARCHIVE=$(tar -tf "$ARCHIVE_PATH" | head -n 1 | cut -d'/' -f1)

  stop_spinner

  if [ -z "$VMNAME_IN_ARCHIVE" ]; then
    display_and_log "ERROR" "Could not determine VM name from archive '$ARCHIVE_PATH'. Is it a valid VM archive?"
    exit 1
  fi

  local FINAL_VM_NAME="${NEW_VM_NAME:-$VMNAME_IN_ARCHIVE}"
  local DEST_VM_DIR="$VM_CONFIG_BASE_DIR/$FINAL_VM_NAME"

  if [ -d "$DEST_VM_DIR" ]; then
    display_and_log "WARNING" "VM '$FINAL_VM_NAME' already exists."
    read -rp "Do you want to overwrite it? (y/n): " OVERWRITE_CHOICE
    if ! [[ "$OVERWRITE_CHOICE" =~ ^[Yy]$ ]]; then
      display_and_log "INFO" "VM import cancelled by user."
      exit 0
    fi
    display_and_log "INFO" "Overwriting existing VM '$FINAL_VM_NAME'..."

    # If overwriting, check if the VM is running and stop it first.
    if is_vm_running "$FINAL_VM_NAME"; then
      display_and_log "INFO" "Stopping running VM '$FINAL_VM_NAME' before overwrite..."
      cmd_stop "$FINAL_VM_NAME" --silent
      if is_vm_running "$FINAL_VM_NAME"; then
        display_and_log "ERROR" "Failed to stop running VM '$FINAL_VM_NAME'. Aborting import."
        exit 1
      fi
      display_and_log "INFO" "VM stopped successfully."
    fi
  fi

  start_spinner "Importing VM from '$ARCHIVE_PATH'வுகளை..."

  local ARCHIVE_EXTENSION="${ARCHIVE_PATH##*.}"
  # Extract to a temporary directory first to allow renaming
  local TEMP_EXTRACT_DIR
  TEMP_EXTRACT_DIR=$(mktemp -d -t bhyve-cli-import-XXXXXX)

  local result=0
  case "$ARCHIVE_EXTENSION" in
    zst)
      zstd -dc "$ARCHIVE_PATH" | tar -xf - -C "$TEMP_EXTRACT_DIR"
      result=${PIPESTATUS[1]}
      ;;
    gz)
      gzip -dc "$ARCHIVE_PATH" | tar -xf - -C "$TEMP_EXTRACT_DIR"
      result=${PIPESTATUS[1]}
      ;;
    bz2)
      bzip2 -dc "$ARCHIVE_PATH" | tar -xf - -C "$TEMP_EXTRACT_DIR"
      result=${PIPESTATUS[1]}
      ;;
    xz)
      xz -dc "$ARCHIVE_PATH" | tar -xf - -C "$TEMP_EXTRACT_DIR"
      result=${PIPESTATUS[1]}
      ;;
    tar)
      tar -xf "$ARCHIVE_PATH" -C "$TEMP_EXTRACT_DIR"
      result=$?
      ;;
    *)
      stop_spinner_on_failure
      display_and_log "ERROR" "Unsupported archive format: .$ARCHIVE_EXTENSION"
      rm -rf "$TEMP_EXTRACT_DIR"
      exit 1
      ;;
  esac

  if [ $result -ne 0 ]; then
      stop_spinner_on_failure
      display_and_log "ERROR" "Failed to extract archive '$ARCHIVE_PATH'. Tar exit code: $result"
      rm -rf "$TEMP_EXTRACT_DIR"
      exit 1
  fi

  # Move the extracted VM to its final destination
  mv "$TEMP_EXTRACT_DIR/$VMNAME_IN_ARCHIVE" "$DEST_VM_DIR" || {
    stop_spinner_on_failure
    display_and_log "ERROR" "Failed to move extracted VM from '$TEMP_EXTRACT_DIR/$VMNAME_IN_ARCHIVE' to '$DEST_VM_DIR'."
    rm -rf "$TEMP_EXTRACT_DIR"
    exit 1
  }
  rm -rf "$TEMP_EXTRACT_DIR" # Clean up temporary directory

  # Clean up vm.pid and vm.log if they were imported from an older archive
  if [ -f "$DEST_VM_DIR/vm.pid" ]; then
    rm "$DEST_VM_DIR/vm.pid"
    display_and_log "INFO" "Removed old vm.pid from '$DEST_VM_DIR'."
  fi
  if [ -f "$DEST_VM_DIR/vm.log" ]; then
    rm "$DEST_VM_DIR/vm.log"
    display_and_log "INFO" "Removed old vm.log from '$DEST_VM_DIR'."
  fi

  # Update VMNAME, CONSOLE, and LOG in vm.conf if a new name was provided
  if [ -n "$NEW_VM_NAME" ] && [ "$NEW_VM_NAME" != "$VMNAME_IN_ARCHIVE" ]; then
    local VM_CONF_FILE="$DEST_VM_DIR/vm.conf"
    local VM_BHYVE_CONF_FILE="$DEST_VM_DIR/$VMNAME_IN_ARCHIVE.conf"

    if [ -f "$VM_CONF_FILE" ]; then
      # bhyve-cli native VM
      # Update VMNAME
      sed -i '' "s/^VMNAME=.*/VMNAME=$FINAL_VM_NAME/" "$VM_CONF_FILE"
      display_and_log "INFO" "Updated VMNAME in '$VM_CONF_FILE' to '$FINAL_VM_NAME'."

      # Update CONSOLE
      sed -i '' "s/^CONSOLE=nmdm-$VMNAME_IN_ARCHIVE.1/CONSOLE=nmdm-$FINAL_VM_NAME.1/" "$VM_CONF_FILE"
      display_and_log "INFO" "Updated CONSOLE in '$VM_CONF_FILE' to 'nmdm-$FINAL_VM_NAME.1'."

      # Update LOG path
      sed -i '' "s|^LOG=$VM_CONFIG_BASE_DIR/$VMNAME_IN_ARCHIVE/vm.log|LOG=$VM_CONFIG_BASE_DIR/$FINAL_VM_NAME/vm.log|" "$VM_CONF_FILE"
      display_and_log "INFO" "Updated LOG path in '$VM_CONF_FILE' to '$VM_CONFIG_BASE_DIR/$FINAL_VM_NAME/vm.log'."

    elif [ -f "$VM_BHYVE_CONF_FILE" ]; then
      # vm-bhyve VM - rename its config file
      mv "$VM_BHYVE_CONF_FILE" "$DEST_VM_DIR/$FINAL_VM_NAME.conf"
      display_and_log "INFO" "Renamed vm-bhyve config file to '$DEST_VM_DIR/$FINAL_VM_NAME.conf'."
    fi
  fi

  # Update TAP interfaces to ensure uniqueness
  display_and_log "INFO" "Updating TAP interfaces for '$FINAL_VM_NAME'..."
  local NIC_INDEX=0
  while true; do
    local TAP_VAR="TAP_${NIC_INDEX}"
    local CURRENT_TAP_LINE=$(grep "^${TAP_VAR}=" "$DEST_VM_DIR/vm.conf")

    if [ -z "$CURRENT_TAP_LINE" ]; then
      # No more TAP interfaces found
      break
    fi

    local OLD_TAP_DEVICE=$(echo "$CURRENT_TAP_LINE" | cut -d'=' -f2)
    local NEW_TAP_NUM=$(get_next_available_tap_num)
    local NEW_TAP_DEVICE="tap${NEW_TAP_NUM}"

    if [ "$OLD_TAP_DEVICE" != "$NEW_TAP_DEVICE" ]; then
      sed -i '' "s|^${TAP_VAR}=${OLD_TAP_DEVICE}$|${TAP_VAR}=${NEW_TAP_DEVICE}|" "$DEST_VM_DIR/vm.conf"
      display_and_log "INFO" "Updated ${TAP_VAR} from '$OLD_TAP_DEVICE' to '$NEW_TAP_DEVICE'."
    fi

    NIC_INDEX=$((NIC_INDEX + 1))
  done

  stop_spinner
  display_and_log "INFO" "VM '$FINAL_VM_NAME' imported successfully."
}
