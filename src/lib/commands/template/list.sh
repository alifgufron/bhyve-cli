#!/usr/local/bin/bash

# === Subcommand: template list ===
cmd_template_list() {
  if [ "$1" = "--help" ]; then
    cmd_template_usage
    exit 0
  fi
  local TEMPLATE_BASE_DIR="$VM_CONFIG_BASE_DIR/templates"

  if [ ! -d "$TEMPLATE_BASE_DIR" ] || [ -z "$(ls -A "$TEMPLATE_BASE_DIR")" ]; then
    display_and_log "INFO" "No VM templates found."
    exit 0
  fi

  echo_message "Available VM Templates:"
  echo_message "---------------------------------"
  local count=0
  for TEMPLATE_PATH in "$TEMPLATE_BASE_DIR"/*/; do
    if [ -d "$TEMPLATE_PATH" ]; then
      local TEMPLATE_NAME=$(basename "$TEMPLATE_PATH")
      echo_message "- $TEMPLATE_NAME"
      count=$((count + 1))
    fi
  done

  if [ "$count" -eq 0 ]; then
    display_and_log "INFO" "No VM templates found."
  fi
  echo_message "---------------------------------"
}
