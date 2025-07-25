#!/usr/local/bin/bash

# === Subcommand: vmnet destroy ===
cmd_vmnet_destroy() {
  local BRIDGE_NAME="$1"

  if [ -z "$BRIDGE_NAME" ]; then
    display_and_log "ERROR" "Bridge name is required for vmnet destroy."
    cmd_vmnet_usage
    exit 1
  fi

  log "Attempting to destroy vmnet bridge '$BRIDGE_NAME'..."

  if ! ifconfig "$BRIDGE_NAME" > /dev/null 2>&1; then
    display_and_log "ERROR" "Bridge '$BRIDGE_NAME' not found or already destroyed."
    # Also remove from config if not found
    local VMNET_CONFIG_FILE="$CONFIG_DIR/vmnet.conf"
    sed -i '' "/^$BRIDGE_NAME /d" "$VMNET_CONFIG_FILE" 2>/dev/null
    exit 1
  fi

  MEMBERS=$(ifconfig "$BRIDGE_NAME" | grep 'member:' | awk '{print $2}')
  if [ -n "$MEMBERS" ]; then
    display_and_log "WARNING" "Bridge '$BRIDGE_NAME' has active members. Destroying it will disconnect them."
    read -rp "Are you sure you want to destroy bridge '$BRIDGE_NAME' and its members? (y/n): " CONFIRM_DESTROY
    if ! [[ "$CONFIRM_DESTROY" =~ ^[Yy]$ ]]; then
      echo_message "Bridge destruction cancelled."
      exit 0
    fi
  fi

  if ! ifconfig "$BRIDGE_NAME" destroy; then
    display_and_log "ERROR" "Failed to destroy bridge '$BRIDGE_NAME'."
    exit 1
  fi
  display_and_log "INFO" "Bridge '$BRIDGE_NAME' destroyed successfully."

  # Remove from vmnet configuration
  local VMNET_CONFIG_FILE="$CONFIG_DIR/vmnet.conf"
  sed -i '' "/^$BRIDGE_NAME /d" "$VMNET_CONFIG_FILE"
  display_and_log "INFO" "Vmnet configuration for '$BRIDGE_NAME' removed."
}
