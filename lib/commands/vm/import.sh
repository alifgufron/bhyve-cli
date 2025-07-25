#!/usr/local/bin/bash

# === Subcommand: import ===
cmd_import() {
  if [ -z "$1" ]; then
    cmd_import_usage
    exit 1
  fi

  local ARCHIVE_PATH="$1"

  # Get the VM name from the archive (assuming it's the top-level directory)
  start_spinner "Checking environment..."

  local VMNAME_IN_ARCHIVE=$(tar -tf "$ARCHIVE_PATH" | head -n 1 | cut -d'/' -f1)

  stop_spinner

  if [ -z "$VMNAME_IN_ARCHIVE" ]; then
    display_and_log "ERROR" "Could not determine VM name from archive '$ARCHIVE_PATH'. Is it a valid VM archive?"
    exit 1
  fi

  local DEST_VM_DIR="$VM_CONFIG_BASE_DIR/$VMNAME_IN_ARCHIVE"

  if [ -d "$DEST_VM_DIR" ]; then
    display_and_log "WARNING" "VM '$VMNAME_IN_ARCHIVE' already exists."
    read -rp "Do you want to overwrite it? (y/n): " OVERWRITE_CHOICE
    if ! [[ "$OVERWRITE_CHOICE" =~ ^[Yy]$ ]]; then
      display_and_log "INFO" "VM import cancelled by user."
      exit 0
    fi
    display_and_log "INFO" "Overwriting existing VM '$VMNAME_IN_ARCHIVE'..."
  fi

  start_spinner "Importing VM from '$ARCHIVE_PATH'..."

  tar -xzf "$ARCHIVE_PATH" -C "$VM_CONFIG_BASE_DIR"

  stop_spinner
  display_and_log "INFO" "VM '$VMNAME_IN_ARCHIVE' imported successfully."
}
