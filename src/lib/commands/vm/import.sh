#!/usr/local/bin/bash

# === Subcommand: import ===
cmd_import() {
  local ARCHIVE_PATH=""
  local NEW_VM_NAME=""
  local DATASTORE_NAME="default"

  # Parse arguments
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --datastore)
        if [ -z "$2" ]; then
          display_and_log "ERROR" "Missing argument for --datastore."
          cmd_import_usage
          exit 1
        fi
        DATASTORE_NAME="$2"
        shift 2
        ;;
      *)
        if [ -z "$ARCHIVE_PATH" ]; then
          ARCHIVE_PATH="$1"
        elif [ -z "$NEW_VM_NAME" ]; then
          NEW_VM_NAME="$1"
        else
          display_and_log "ERROR" "Too many arguments: $1"
          cmd_import_usage
          exit 1
        fi
        shift 1
        ;;
    esac
  done

  if [ -z "$ARCHIVE_PATH" ]; then
    cmd_import_usage
    exit 1
  fi

  # Get the absolute path for the selected datastore
  local datastore_path
  datastore_path=$(get_datastore_path "$DATASTORE_NAME")
  if [ -z "$datastore_path" ]; then
    display_and_log "ERROR" "Datastore '$DATASTORE_NAME' not found. Please check 'datastore list'."
    exit 1
  fi

  # Get the VM name from the archive (assuming it's the top-level directory)
  start_spinner "Checking archive..."
  local VMNAME_IN_ARCHIVE
  VMNAME_IN_ARCHIVE=$(tar -tf "$ARCHIVE_PATH" 2>/dev/null | head -n 1 | cut -d'/' -f1)
  stop_spinner

  if [ -z "$VMNAME_IN_ARCHIVE" ]; then
    display_and_log "ERROR" "Could not determine VM name from archive '$ARCHIVE_PATH'. Is it a valid VM archive?"
    exit 1
  fi

  local FINAL_VM_NAME="${NEW_VM_NAME:-$VMNAME_IN_ARCHIVE}"
  local DEST_VM_DIR="$datastore_path/$FINAL_VM_NAME"

  # Check if a VM with the final name already exists anywhere
  local existing_vm_info
  existing_vm_info=$(find_any_vm "$FINAL_VM_NAME")
  if [ -n "$existing_vm_info" ]; then
    display_and_log "WARNING" "VM '$FINAL_VM_NAME' already exists."
    read -rp "Do you want to overwrite it? (y/n): " OVERWRITE_CHOICE
    if ! [[ "$OVERWRITE_CHOICE" =~ ^[Yy]$ ]]; then
      display_and_log "INFO" "VM import cancelled by user."
      exit 0
    fi
    display_and_log "INFO" "Overwriting existing VM '$FINAL_VM_NAME'..."

    # If overwriting, check if the VM is running and stop it first.
    local existing_vm_dir="$(echo "$existing_vm_info" | cut -d':' -f3)/$FINAL_VM_NAME"
    if is_vm_running "$FINAL_VM_NAME" "$existing_vm_dir"; then
      display_and_log "INFO" "Stopping running VM '$FINAL_VM_NAME' before overwrite..."
      cmd_stop "$FINAL_VM_NAME" --silent
      if ! wait_for_vm_status "$FINAL_VM_NAME" "$existing_vm_dir" "stopped"; then
        display_and_log "ERROR" "Failed to stop running VM '$FINAL_VM_NAME'. Aborting import."
        exit 1
      fi
      display_and_log "INFO" "VM stopped successfully."
    fi
    # Remove the old directory before importing the new one
    rm -rf "$existing_vm_dir"
  fi

  start_spinner "Importing VM from '$ARCHIVE_PATH'..."

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
      stop_spinner
      display_and_log "ERROR" "Unsupported archive format: .$ARCHIVE_EXTENSION"
      rm -rf "$TEMP_EXTRACT_DIR"
      exit 1
      ;;
  esac

  if [ $result -ne 0 ]; then
      stop_spinner
      display_and_log "ERROR" "Failed to extract archive '$ARCHIVE_PATH'. Tar exit code: $result"
      rm -rf "$TEMP_EXTRACT_DIR"
      exit 1
  fi

  # Move the extracted VM to its final destination
  # Ensure parent directory exists
  mkdir -p "$datastore_path"
  mv "$TEMP_EXTRACT_DIR/$VMNAME_IN_ARCHIVE" "$DEST_VM_DIR" || {
    stop_spinner
    display_and_log "ERROR" "Failed to move extracted VM from '$TEMP_EXTRACT_DIR/$VMNAME_IN_ARCHIVE' to '$DEST_VM_DIR'."
    rm -rf "$TEMP_EXTRACT_DIR"
    exit 1
  }
  rm -rf "$TEMP_EXTRACT_DIR" # Clean up temporary directory

  # Clean up vm.pid and vm.log if they were imported from an older archive
  [ -f "$DEST_VM_DIR/vm.pid" ] && rm "$DEST_VM_DIR/vm.pid"
  [ -f "$DEST_VM_DIR/vm.log" ] && rm "$DEST_VM_DIR/vm.log"

  local VM_CONF_FILE="$DEST_VM_DIR/vm.conf"
  # Update VMNAME, CONSOLE, and LOG in vm.conf
  if [ -f "$VM_CONF_FILE" ]; then
    # Update VMNAME
    sed -i '' "s/^VMNAME=.*/VMNAME=$FINAL_VM_NAME/" "$VM_CONF_FILE"
    # Update CONSOLE
    sed -i '' "s/^CONSOLE=nmdm-.*/CONSOLE=nmdm-$FINAL_VM_NAME.1/" "$VM_CONF_FILE"
    # Update LOG path to its new location
    sed -i '' "s|^LOG=.*|LOG=$DEST_VM_DIR/vm.log|" "$VM_CONF_FILE"
    log "Updated vm.conf for new name and location: $FINAL_VM_NAME"
  fi

  # Update TAP interfaces to ensure uniqueness
  display_and_log "INFO" "Updating TAP interfaces for '$FINAL_VM_NAME'..."
  if [ -f "$VM_CONF_FILE" ]; then
    local NIC_INDEX=0
    while true; do
      local TAP_VAR="TAP_${NIC_INDEX}"
      local CURRENT_TAP_LINE=$(grep "^${TAP_VAR}=" "$VM_CONF_FILE")

      if [ -z "$CURRENT_TAP_LINE" ]; then
        break # No more TAP interfaces found
      fi

      local OLD_TAP_DEVICE=$(echo "$CURRENT_TAP_LINE" | cut -d'=' -f2)
      local NEW_TAP_NUM=$(get_next_available_tap_num)
      local NEW_TAP_DEVICE="tap${NEW_TAP_NUM}"

      if [ "$OLD_TAP_DEVICE" != "$NEW_TAP_DEVICE" ]; then
        sed -i '' "s|^${TAP_VAR}=${OLD_TAP_DEVICE}$|${TAP_VAR}=${NEW_TAP_DEVICE}|" "$VM_CONF_FILE"
        display_and_log "INFO" "Updated ${TAP_VAR} from '$OLD_TAP_DEVICE' to '$NEW_TAP_DEVICE'."
      fi

      NIC_INDEX=$((NIC_INDEX + 1))
    done
  fi

  stop_spinner
  display_and_log "INFO" "VM '$FINAL_VM_NAME' imported successfully into datastore '$DATASTORE_NAME'."
}