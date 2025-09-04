#!/usr/local/bin/bash

# === Subcommand: export ===
cmd_export() {
  if [ -z "$2" ]; then
    cmd_export_usage
    exit 1
  fi

  local VMNAME="$1"
  local DEST_PATH="$2"
  local ORIGINAL_VM_STATE="stopped" # Default state

  load_vm_config "$VMNAME"

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

  start_spinner "Exporting VM '$VMNAME' to '$DEST_PATH'..."

  if tar -czf "$DEST_PATH" -C "$VM_CONFIG_BASE_DIR" "$VMNAME"; then
    stop_spinner
    display_and_log "INFO" "VM '$VMNAME' exported successfully to '$DEST_PATH'."
  else
    stop_spinner
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
