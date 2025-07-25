#!/usr/local/bin/bash

# === Subcommand: vmnet create ===
cmd_vmnet_create() {
  local BRIDGE_NAME=""
  local IP_ADDRESS=""

  while (( "$#" )); do
    case "$1" in
      --name)
        shift
        BRIDGE_NAME="$1"
        ;;
      --ip)
        shift
        IP_ADDRESS="$1"
        ;;
      *)
        display_and_log "ERROR" "Invalid option for vmnet create: $1"
        cmd_vmnet_usage
        exit 1
        ;;
    esac
    shift
  done

  if [ -z "$BRIDGE_NAME" ]; then
    display_and_log "ERROR" "Bridge name is required for vmnet create."
    cmd_vmnet_usage
    exit 1
  fi

  log "Attempting to create vmnet bridge '$BRIDGE_NAME'..."

  if ifconfig "$BRIDGE_NAME" > /dev/null 2>&1; then
    display_and_log "ERROR" "Bridge '$BRIDGE_NAME' already exists."
    exit 1
  fi

  if ! ifconfig bridge create name "$BRIDGE_NAME"; then
    display_and_log "ERROR" "Failed to create bridge '$BRIDGE_NAME'."
    exit 1
  fi
  display_and_log "INFO" "Bridge '$BRIDGE_NAME' created successfully."

  if [ -n "$IP_ADDRESS" ]; then
    log "Assigning IP address '$IP_ADDRESS' to bridge '$BRIDGE_NAME'..."
    if ! ifconfig "$BRIDGE_NAME" inet "$IP_ADDRESS" up; then
      display_and_log "ERROR" "Failed to assign IP address '$IP_ADDRESS' to bridge '$BRIDGE_NAME'."
      # Clean up bridge if IP assignment fails
      ifconfig "$BRIDGE_NAME" destroy > /dev/null 2>&1
      exit 1
    fi
    display_and_log "INFO" "IP address '$IP_ADDRESS' assigned to bridge '$BRIDGE_NAME'."
  else
    if ! ifconfig "$BRIDGE_NAME" up; then
      display_and_log "ERROR" "Failed to bring up bridge '$BRIDGE_NAME'."
      ifconfig "$BRIDGE_NAME" destroy > /dev/null 2>&1
      exit 1
    fi
    display_and_log "INFO" "Bridge '$BRIDGE_NAME' brought up."
  fi

  # Save vmnet configuration for persistence
  local VMNET_CONFIG_FILE="$CONFIG_DIR/vmnet.conf"
  echo "$BRIDGE_NAME $IP_ADDRESS" >> "$VMNET_CONFIG_FILE"
  display_and_log "INFO" "Vmnet configuration saved to $VMNET_CONFIG_FILE."
}
