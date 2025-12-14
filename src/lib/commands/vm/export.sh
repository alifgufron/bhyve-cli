#!/usr/local/bin/bash

# === Subcommand: export ===
cmd_export() {
  local VMNAME=""
  local DEST_DIR=""
  local COMPRESSION_FORMAT="gz" # Default compression
  local ORIGINAL_VM_STATE="stopped" # Default state
  local FORCE_EXPORT=false
  local SUSPEND_EXPORT=false
  local STOP_EXPORT=false
  local EXPORT_ACTION_SET=false # To ensure only one action is specified

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
      --force-export)
        if [ "$EXPORT_ACTION_SET" = true ]; then
          display_and_log "ERROR" "Only one export action (--force-export, --suspend-export, --stop-export) can be specified."
          cmd_export_usage
          exit 1
        fi
        FORCE_EXPORT=true
        EXPORT_ACTION_SET=true
        shift 1
        ;;
      --suspend-export)
        if [ "$EXPORT_ACTION_SET" = true ]; then
          display_and_log "ERROR" "Only one export action (--force-export, --suspend-export, --stop-export) can be specified."
          cmd_export_usage
          exit 1
        fi
        SUSPEND_EXPORT=true
        EXPORT_ACTION_SET=true
        shift 1
        ;;
      --stop-export)
        if [ "$EXPORT_ACTION_SET" = true ]; then
          display_and_log "ERROR" "Only one export action (--force-export, --suspend-export, --stop-export) can be specified."
          cmd_export_usage
          exit 1
        fi
        STOP_EXPORT=true
        EXPORT_ACTION_SET=true
        shift 1
        ;;
      *)
        if [ -z "$VMNAME" ]; then
          VMNAME="$1"
        elif [ -z "$DEST_DIR" ]; then
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

  if [ -z "$VMNAME" ] || [ -z "$DEST_DIR" ]; then
    cmd_export_usage
    exit 1
  fi

  # Create the destination directory if it doesn't exist
  mkdir -p "$DEST_DIR" || { display_and_log "ERROR" "Failed to create destination directory: $DEST_DIR"; exit 1; }

  # Use the centralized find_any_vm function
  local found_vm_info
  found_vm_info=$(find_any_vm "$VMNAME")

  if [ -z "$found_vm_info" ]; then
    display_and_log "ERROR" "VM '$VMNAME' not found in any bhyve-cli or vm-bhyve datastores."
    exit 1
  fi

  # Parse the new format: source:datastore_name:datastore_path
  local vm_source
  local datastore_path
  vm_source=$(echo "$found_vm_info" | cut -d':' -f1)
  datastore_path=$(echo "$found_vm_info" | cut -d':' -f3)
  local vm_dir="$datastore_path/$VMNAME"

  # Construct the final archive path
  local CURRENT_DATE=$(date +%Y_%m_%d)
  local ARCHIVE_PATH="${DEST_DIR}/${VMNAME}_${CURRENT_DATE}.tar.$(get_compression_extension_suffix "$COMPRESSION_FORMAT")"

  # Check if the VM is running
  if is_vm_running "$VMNAME" "$vm_dir"; then
    ORIGINAL_VM_STATE="running"
    local choice="" # Initialize choice variable

    if [ "$FORCE_EXPORT" = true ]; then
      choice=1
      display_and_log "INFO" "Proceeding with live export as requested by --force-export."
    elif [ "$STOP_EXPORT" = true ]; then
      choice=2
      display_and_log "INFO" "Stopping VM for a consistent export as requested by --stop-export..."
      cmd_stop "$VMNAME" --silent
      if ! wait_for_vm_status "$VMNAME" "$vm_dir" "stopped"; then
        display_and_log "ERROR" "Failed to stop VM '$VMNAME'. Aborting export."
        exit 1
      fi
    elif [ "$SUSPEND_EXPORT" = true ]; then
      choice=3
      display_and_log "INFO" "Suspending VM for a consistent export as requested by --suspend-export..."
      cmd_suspend "$VMNAME"
      if ! wait_for_vm_status "$VMNAME" "$vm_dir" "suspended"; then
        display_and_log "ERROR" "Failed to suspend VM '$VMNAME'. Aborting export."
        exit 1
      fi
    else
      # Interactive prompt if no non-interactive option is provided
      echo "[WARNING] VM '$VMNAME' is currently running."
      echo "Exporting a running VM may result in an inconsistent state."
      echo "Choose an option:"
      echo "  1) Proceed with live export (not recommended)"
      echo "  2) Stop the VM, export, and restart it"
      echo "  3) Suspend the VM, export, and resume it"
      echo "  4) Abort the export"
      read -p "Enter your choice [1-4]: " choice
    fi

    case $choice in
      1)
        # Proceed with live export (already handled if --force-export)
        ;;
      2)
        # Stop, export, restart
        if [ "$STOP_EXPORT" != true ]; then # Only if not already handled by --stop-export flag
          cmd_stop "$VMNAME" --silent
          if ! wait_for_vm_status "$VMNAME" "$vm_dir" "stopped"; then
            display_and_log "ERROR" "Failed to stop VM '$VMNAME'. Aborting export."
            exit 1
          fi
        fi
        ;;
      3)
        # Suspend, export, resume
        if [ "$SUSPEND_EXPORT" != true ]; then # Only if not already handled by --suspend-export flag
          cmd_suspend "$VMNAME"
          if ! wait_for_vm_status "$VMNAME" "$vm_dir" "suspended"; then
            display_and_log "ERROR" "Failed to suspend VM '$VMNAME'. Aborting export."
            exit 1
          fi
        fi
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
    # Correctly change directory to the VM's datastore path
    if tar -c $(get_tar_compression_flags "$COMPRESSION_FORMAT") -f "$ARCHIVE_PATH" -C "$datastore_path" "$VMNAME"; then
      EXPORT_SUCCESS=true
    fi
  else # vm-bhyve
    local EXPORT_SUCCESS=true # Initialize to true for vm-bhyve path
    local CONF_FILE_PATH="$vm_dir/$VMNAME.conf"

    if [ ! -f "$CONF_FILE_PATH" ]; then
      display_and_log "ERROR" "VM-bhyve config file not found: $CONF_FILE_PATH"
      EXPORT_SUCCESS=false
    else
      # Create a staging directory inside the destination directory
      local STAGING_PARENT_DIR="$DEST_DIR"
      local TEMP_EXPORT_DIR
      TEMP_EXPORT_DIR=$(mktemp -d -p "$STAGING_PARENT_DIR" staging_${VMNAME}_XXXXXX)
      
      if [ ! -d "$TEMP_EXPORT_DIR" ]; then
          display_and_log "ERROR" "Failed to create staging directory in '$STAGING_PARENT_DIR'."
          EXPORT_SUCCESS=false
      else
          # The structure inside the tarball should just be the VMNAME directory
          local TEMP_VM_DIR="$TEMP_EXPORT_DIR/$VMNAME"
          mkdir -p "$TEMP_VM_DIR"

          # Copy config file
          cp "$CONF_FILE_PATH" "$TEMP_VM_DIR/$VMNAME.conf"

          # Source config to get disk paths
          # shellcheck source=/dev/null
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

            local DISK_PATH="$vm_dir/$DISK_NAME"
            if [ ! -f "$DISK_PATH" ]; then
              display_and_log "ERROR" "Disk image not found: $DISK_PATH. Aborting."
              EXPORT_SUCCESS=false
              break
            fi
            DISK_PATHS+=("$DISK_PATH")
            cp "$DISK_PATH" "$TEMP_VM_DIR/$DISK_NAME"
            DISK_IDX=$((DISK_IDX + 1))
          done

          if $EXPORT_SUCCESS; then
            # Tar the temporary directory. The -C flag changes to the parent of the directory we want to archive.
            if tar -c $(get_tar_compression_flags "$COMPRESSION_FORMAT") -f "$ARCHIVE_PATH" -C "$TEMP_EXPORT_DIR" "$VMNAME"; then
              EXPORT_SUCCESS=true
            else
              EXPORT_SUCCESS=false
            fi
          fi

          # Clean up temporary staging directory
          rm -rf "$TEMP_EXPORT_DIR"
      fi
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