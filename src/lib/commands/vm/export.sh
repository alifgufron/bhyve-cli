#!/usr/local/bin/bash

# === Subcommand: export ===
cmd_export() {
  local VMNAME=""
  local DEST_DIR="" # Renamed from DEST_PATH
  local COMPRESSION_FORMAT="gz" # Default compression
  local ORIGINAL_VM_STATE="stopped" # Default state

  # Parse arguments
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --compression)
        if [ -z "$2" ]; then
          display_and_log "ERROR" "Missing argument for --compression."
          cmd_export_usage
          exit 1
        fi
        COMPRESSION_FORMAT="$2"
        shift 2
        ;;
      *)
        if [ -z "$VMNAME" ]; then
          VMNAME="$1"
        elif [ -z "$DEST_DIR" ]; then # Use DEST_DIR
          DEST_DIR="$1"
        else
          display_and_log "ERROR" "Too many arguments: $1"
          cmd_export_usage
          exit 1
        fi
        shift 1
        ;;
    esac
  done

  if [ -z "$VMNAME" ] || [ -z "$DEST_DIR" ]; then # Use DEST_DIR
    cmd_export_usage
    exit 1
  fi

  # Create the destination directory if it doesn't exist
  mkdir -p "$DEST_DIR" || { display_and_log "ERROR" "Failed to create destination directory: $DEST_DIR"; exit 1; }

  # Construct the final archive path
  local ARCHIVE_PATH="${DEST_DIR}/${VMNAME}.tar.$(get_compression_extension_suffix "$COMPRESSION_FORMAT")"

  # Detect VM source
  local vm_source=""
  local vm_base_dir=""
  if [ -d "$VM_CONFIG_BASE_DIR/$VMNAME" ]; then
    vm_source="bhyve-cli"
    vm_base_dir="$VM_CONFIG_BASE_DIR"
    load_vm_config "$VMNAME"
  else
    local vm_bhyve_base_dir
    vm_bhyve_base_dir=$(get_vm_bhyve_dir)
    if [ -n "$vm_bhyve_base_dir" ] && [ -d "$vm_bhyve_base_dir/$VMNAME" ]; then
      vm_source="vm-bhyve"
      vm_base_dir="$vm_bhyve_base_dir"
    fi
  fi

  if [ -z "$vm_source" ]; then
    display_and_log "ERROR" "VM '$VMNAME' not found in bhyve-cli or vm-bhyve directories."
    exit 1
  fi

  # Check if the VM is running
  if is_vm_running "$VMNAME"; then
    ORIGINAL_VM_STATE="running"
    echo "[WARNING] VM '$VMNAME' is currently running."
    echo "Exporting a running VM may result in an inconsistent state."
    echo "Choose an option:"
    echo "  1) Proceed with live export (not recommended)"
    echo "  2) Stop the VM, export, and restart it"
    echo "  3) Suspend the VM, export, and resume it"
    echo "  4) Abort the export"
    read -p "Enter your choice [1-4]: " choice

    case $choice in
      1)
        # Proceed with live export
        display_and_log "INFO" "Proceeding with live export as requested."
        ;;
      2)
        # Stop, export, restart
        display_and_log "INFO" "Stopping VM for a consistent export..."
        cmd_stop "$VMNAME" --silent
        if is_vm_running "$VMNAME"; then
            display_and_log "ERROR" "Failed to stop VM '$VMNAME'. Aborting export."
            exit 1
        fi
        ;;
      3)
        # Suspend, export, resume
        display_and_log "INFO" "Suspending VM for a consistent export..."
        cmd_suspend "$VMNAME"
        # We need to check if suspend was successful. Assuming it is for now.
        # A better check would be to see if the bhyve process is paused.
        ;;
      4)
        # Abort
        display_and_log "INFO" "Export aborted by user."
        exit 0
        ;;
      *)
        display_and_log "ERROR" "Invalid choice. Aborting export."
        exit 1
        ;;
    esac
  fi

  start_spinner "Exporting VM '$VMNAME' to '$ARCHIVE_PATH'..."

  local EXPORT_SUCCESS=false

  if [ "$vm_source" == "bhyve-cli" ]; then
    if tar $(get_tar_compression_flags "$COMPRESSION_FORMAT") -f "$ARCHIVE_PATH" -C "$VM_CONFIG_BASE_DIR" "$VMNAME"; then
      EXPORT_SUCCESS=true
    fi
  else # vm-bhyve
    local EXPORT_SUCCESS=true # Initialize to true for vm-bhyve path
    local VM_VM_DIR="$vm_base_dir/$VMNAME" # e.g., /opt/bhvye/mrtg
    local CONF_FILE_PATH="$VM_VM_DIR/$VMNAME.conf"

    if [ ! -f "$CONF_FILE_PATH" ]; then
      display_and_log "ERROR" "VM-bhyve config file not found: $CONF_FILE_PATH"
      EXPORT_SUCCESS=false
    else
      # Create a temporary directory for packaging
      local TEMP_EXPORT_DIR=$(mktemp -d -t bhyve-cli-export-XXXXXX)
      local TEMP_VM_DIR="$TEMP_EXPORT_DIR/$VMNAME"
      mkdir -p "$TEMP_VM_DIR"

      # Copy config file
      cp "$CONF_FILE_PATH" "$TEMP_VM_DIR/$VMNAME.conf"

      # Source config to get disk paths
      . "$CONF_FILE_PATH"

      local DISK_PATHS=()
      local DISK_IDX=0
      while true; do
        local type_var="disk${DISK_IDX}_type"
        local name_var="disk${DISK_IDX}_name"
        local DISK_TYPE="${!type_var}"
        if [ -z "$DISK_TYPE" ]; then break; fi
        local DISK_NAME="${!name_var}"

        if [ "$DISK_TYPE" == "zvol" ]; then
          display_and_log "ERROR" "ZFS zvols are not yet supported for export. Aborting."
          EXPORT_SUCCESS=false
          break
        fi

        local DISK_PATH="$VM_VM_DIR/$DISK_NAME"
        if [ ! -f "$DISK_PATH" ]; then
          display_and_log "ERROR" "Disk image not found: $DISK_PATH. Aborting."
          EXPORT_SUCCESS=false
          break
        fi
        DISK_PATHS+=("$DISK_PATH")
        cp "$DISK_PATH" "$TEMP_VM_DIR/$DISK_NAME"
        DISK_IDX=$((DISK_IDX + 1))
      done

      if $EXPORT_SUCCESS; then # Only proceed if no errors so far (e.g., zvol or missing disk)
        # Tar the temporary directory
        if tar $(get_tar_compression_flags "$COMPRESSION_FORMAT") -f "$ARCHIVE_PATH" -C "$TEMP_EXPORT_DIR" "$VMNAME"; then
          EXPORT_SUCCESS=true
        else
          EXPORT_SUCCESS=false
        fi
      fi

      # Clean up temporary directory
      rm -rf "$TEMP_EXPORT_DIR"
    fi
  fi

  stop_spinner
  if $EXPORT_SUCCESS; then
    display_and_log "INFO" "VM '$VMNAME' exported successfully to '$ARCHIVE_PATH'."
  else
    display_and_log "ERROR" "Failed to export VM '$VMNAME'."
  fi


  # Restart or resume the VM if it was running
  if [ "$ORIGINAL_VM_STATE" = "running" ]; then
    case $choice in
      2)
        display_and_log "INFO" "Restarting VM '$VMNAME'..."
        cmd_start "$VMNAME" --suppress-console-message
        ;;
      3)
        display_and_log "INFO" "Resuming VM '$VMNAME'..."
        cmd_resume "$VMNAME"
        ;;
    esac
  fi
}
