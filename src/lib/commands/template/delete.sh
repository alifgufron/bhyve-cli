#!/usr/local/bin/bash

# === Subcommand: template delete ===
cmd_template_delete() {
  if [ "$1" = "--help" ] || [ -z "$1" ]; then
    cmd_template_usage
    exit 1
  fi

  local TEMPLATE_NAME="$1"
  local TEMPLATE_PATH="$VM_CONFIG_BASE_DIR/templates/$TEMPLATE_NAME"

  if [ ! -d "$TEMPLATE_PATH" ]; then
    display_and_log "ERROR" "Template '$TEMPLATE_NAME' not found."
    exit 1
  fi

  read -rp "Are you sure you want to delete template '$TEMPLATE_NAME'? (y/n): " CONFIRM_DELETE
  if ! [[ "$CONFIRM_DELETE" =~ ^[Yy]$ ]]; then
    echo_message "Template deletion cancelled."
    exit 0
  fi

  display_and_log "INFO" "Deleting template '$TEMPLATE_NAME' ..."
  start_spinner "Deleting template files..."
  if ! rm -rf "$TEMPLATE_PATH"; then
    stop_spinner
    display_and_log "ERROR" "Failed to delete template files. Manual cleanup may be required."
    exit 1
  fi
  stop_spinner
  display_and_log "INFO" "Template '$TEMPLATE_NAME' deleted successfully."
}
