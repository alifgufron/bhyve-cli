#!/usr/local/bin/bash

# === Subcommand: snapshot list ===
cmd_snapshot_list() {
  if [ -z "$1" ]; then
    cmd_snapshot_usage
    exit 1
  fi

  local VMNAME="$1"
  local SNAPSHOT_DIR="$VM_CONFIG_BASE_DIR/snapshots/$VMNAME"

  if [ ! -d "$SNAPSHOT_DIR" ] || [ -z "$(ls -A "$SNAPSHOT_DIR")" ]; then
    display_and_log "INFO" "No snapshots found for VM '$VMNAME'."
    exit 0
  fi

  echo_message "Snapshots for VM '$VMNAME':"
  echo_message "---------------------------------"
  local count=0
  for SNAPSHOT_PATH in "$SNAPSHOT_DIR"/*/; do
    if [ -d "$SNAPSHOT_PATH" ]; then
      local SNAPSHOT_NAME=$(basename "$SNAPSHOT_PATH")
      echo_message "- $SNAPSHOT_NAME"
      count=$((count + 1))
    fi
  done

  if [ "$count" -eq 0 ]; then
    display_and_log "INFO" "No snapshots found for VM '$VMNAME'."
  fi
  echo_message "---------------------------------"
}
