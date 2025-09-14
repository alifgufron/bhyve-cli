#!/usr/local/bin/bash

# === Subcommand: datastore delete ===
cmd_datastore_delete() {
  local ds_name="$1"

  # --- Validation ---
  if [ -z "$ds_name" ]; then
    display_and_log "ERROR" "Usage: $0 datastore delete <name>"
    exit 1
  fi

  if [ "$ds_name" == "default" ]; then
    display_and_log "ERROR" "The 'default' datastore cannot be deleted."
    exit 1
  fi

  # Check if datastore exists before trying to delete
  if ! grep -q -E "^DATASTORE_${ds_name}=" "$MAIN_CONFIG_FILE"; then
    display_and_log "ERROR" "Datastore '$ds_name' not found."
    exit 1
  fi

  # --- Execution ---
  display_and_log "INFO" "Deleting datastore '$ds_name'..."

  # Use sed to delete the line. The script is expected to run as root.
  if sed -i '' "/^DATASTORE_${ds_name}=/d" "$MAIN_CONFIG_FILE"; then
    display_and_log "SUCCESS" "Datastore '$ds_name' deleted successfully."
  else
    display_and_log "ERROR" "Failed to delete datastore from configuration file: $MAIN_CONFIG_FILE"
    exit 1
  fi
}