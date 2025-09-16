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

  # Get the actual path of the datastore
  local ds_path
  ds_path=$(get_datastore_path "$ds_name")

  if [ -z "$ds_path" ]; then
    display_and_log "ERROR" "Could not determine path for datastore '$ds_name'. Aborting."
    exit 1
  fi

  # Check if the datastore directory contains any VMs
  local vm_count=0
  if [ -d "$ds_path" ]; then
    vm_count=$(find "$ds_path" -maxdepth 1 -mindepth 1 -type d -not -name "templates" | wc -l | tr -d ' ')
  fi

  if [ "$vm_count" -gt 0 ]; then
    display_and_log "WARNING" "Datastore '$ds_name' at '$ds_path' contains $vm_count virtual machine(s)."
    read -rp "Are you sure you want to delete this datastore and ALL its VMs? (y/N): " -n 1 -r
    echo
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
      display_and_log "INFO" "Datastore deletion cancelled."
      exit 0
    fi
  fi

  # Delete the physical datastore directory
  if [ -d "$ds_path" ]; then
    display_and_log "INFO" "Removing physical datastore directory: $ds_path"
    if ! rm -rf "$ds_path"; then
      display_and_log "ERROR" "Failed to remove physical datastore directory: $ds_path"
      exit 1
    fi
  else
    display_and_log "WARNING" "Physical datastore directory '$ds_path' not found. Skipping directory removal."
  fi

  # Remove the datastore entry from the configuration file
  if sed -i '' "/^DATASTORE_${ds_name}=/d" "$MAIN_CONFIG_FILE"; then
    display_and_log "SUCCESS" "Datastore '$ds_name' deleted successfully."
  else
    display_and_log "ERROR" "Failed to delete datastore from configuration file: $MAIN_CONFIG_FILE"
    exit 1
  fi
}