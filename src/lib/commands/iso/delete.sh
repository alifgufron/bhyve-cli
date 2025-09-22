#!/usr/local/bin/bash

# === Subcommand: iso delete ===
cmd_iso_delete() {
  if [ "$1" = "--help" ] || [ -z "$1" ]; then
    cmd_iso_usage
    exit 1
  fi
  local ISO_FILENAME="$1"
  if [ -z "$ISO_FILENAME" ]; then
    display_and_log "ERROR" "Missing ISO filename for delete command."
    cmd_iso_usage
    exit 1
  fi
  local ISO_PATH="$ISO_DIR/$ISO_FILENAME"
  if [ ! -f "$ISO_PATH" ]; then
    display_and_log "ERROR" "ISO file '$ISO_FILENAME' not found in '$ISO_DIR'."
    exit 1
  fi
  read -rp "Are you sure you want to delete '$ISO_FILENAME'? (y/n): " CONFIRM_DELETE
  if ! [[ "$CONFIRM_DELETE" =~ ^[Yy]$ ]]; then
    echo_message "ISO deletion cancelled."
    exit 0
  fi
  log "Deleting ISO file: $ISO_PATH..."
  if rm "$ISO_PATH"; then
    display_and_log "INFO" "ISO file '$ISO_FILENAME' deleted successfully."
  else
    display_and_log "ERROR" "Failed to delete ISO file '$ISO_FILENAME'."
    exit 1
  fi
}
