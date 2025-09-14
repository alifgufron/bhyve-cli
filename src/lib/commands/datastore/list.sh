#!/usr/local/bin/bash

# === Subcommand: datastore list ===
cmd_datastore_list() {
  printf "% -20s % -s\n" "NAME" "PATH"

  # The main config file is already loaded by the dispatcher, so variables are available.

  # 1. Display the default datastore
  if [ -n "$VM_CONFIG_BASE_DIR" ]; then
    printf "% -20s % -s\n" "default" "$VM_CONFIG_BASE_DIR"
  fi

  # 2. Find and display additional datastores
  # grep for DATASTORE_ variables, remove comments, and process them
  grep -E '^DATASTORE_[A-Za-z0-9_]+' "$MAIN_CONFIG_FILE" | while IFS= read -r line || [[ -n "$line" ]]; do
    # Remove potential comments from the line
    local clean_line
    clean_line=$(echo "$line" | sed 's/#.*//')

    # Skip if line becomes empty after comment removal
    [ -z "$clean_line" ] && continue

    local name
    local path
    # Extract name: remove DATASTORE_ prefix and the =... part
    name=$(echo "$clean_line" | cut -d'=' -f1 | sed 's/DATASTORE_//')
    # Extract path: everything after the first = 
    path=$(echo "$clean_line" | cut -d'=' -f2- | tr -d '"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    printf "% -20s % -s\n" "$name" "$path"
  done
}