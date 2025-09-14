#!/usr/local/bin/bash

# === Subcommand: datastore add ===
cmd_datastore_add() {
  local ds_name="$1"
  local ds_path="$2"

  # --- Validation ---
  if [ -z "$ds_name" ] || [ -z "$ds_path" ]; then
    display_and_log "ERROR" "Usage: $0 datastore add <name> <path>"
    exit 1
  fi

  # Check for invalid characters in name
  if [[ ! "$ds_name" =~ ^[A-Za-z0-9_]+$ ]]; then
    display_and_log "ERROR" "Datastore name can only contain letters, numbers, and underscores."
    exit 1
  fi

  # Check if datastore already exists
  if grep -q -E "^DATASTORE_${ds_name}=" "$MAIN_CONFIG_FILE"; then
    display_and_log "ERROR" "Datastore '$ds_name' already exists."
    exit 1
  fi

  # --- Execution ---
  display_and_log "INFO" "Adding datastore '$ds_name' with path '$ds_path'..."

  # Create the physical directory if it doesn't exist
  if [ ! -d "$ds_path" ]; then
    display_and_log "INFO" "Creating physical datastore directory: $ds_path"
    mkdir -p "$ds_path" || {
      display_and_log "ERROR" "Failed to create physical datastore directory '$ds_path'. Please check permissions."
      exit 1
    }
  else
    display_and_log "INFO" "Physical datastore directory '$ds_path' already exists. Skipping creation."
  fi

  # Append to config file. The script is expected to run as root.
  if echo "DATASTORE_${ds_name}=${ds_path}" >> "$MAIN_CONFIG_FILE"; then
    display_and_log "SUCCESS" "Datastore '$ds_name' added successfully."
  else
    display_and_log "ERROR" "Failed to write to configuration file: $MAIN_CONFIG_FILE"
    exit 1
  fi
}