#!/usr/local/bin/bash

# === Subcommand: vmnet init ===
cmd_vmnet_init() {
  local VMNET_CONFIG_FILE="$CONFIG_DIR/vmnet.conf"

  if [ ! -f "$VMNET_CONFIG_FILE" ] || [ ! -s "$VMNET_CONFIG_FILE" ]; then
    log "Vmnet configuration file not found or empty. Nothing to initialize."
    return
  fi
  display_and_log "INFO" "Initializing vmnet bridges from $VMNET_CONFIG_FILE..."
  while read -r BRIDGE_NAME IP_ADDRESS; do
    local args=('--name' "$BRIDGE_NAME")
    if [ -n "$IP_ADDRESS" ]; then
      args+=('--ip' "$IP_ADDRESS")
    fi
    # Call cmd_vmnet_create without saving to config again
    cmd_vmnet_create "${args[@]}" || display_and_log "WARNING" "Failed to initialize vmnet bridge '$BRIDGE_NAME'."
  done < "$VMNET_CONFIG_FILE"
  display_and_log "INFO" "Vmnet initialization complete."
}
