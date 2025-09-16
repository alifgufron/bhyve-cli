#!/usr/local/bin/bash

cmd_switch_add() {
  local BRIDGE_NAME=""
  local PHYS_IF=""
  local VLAN_TAG=""
  local SAVE_CONFIG=true

  # Parse named arguments
  while (( "$#" )); do
    case "$1" in
      --name)
        shift
        BRIDGE_NAME="$1"
        ;;
      --interface)
        shift
        PHYS_IF="$1"
        ;;
      --vlan)
        shift
        VLAN_TAG="$1"
        ;;
      --no-save)
        SAVE_CONFIG=false
        ;;
      *)
        display_and_log "ERROR" "Invalid option: $1"
        cmd_switch_add_usage
        exit 1
        ;;
    esac
    shift
  done

  # Validate required arguments
  if [ -z "$BRIDGE_NAME" ] || [ -z "$PHYS_IF" ]; then
    cmd_switch_add_usage
    exit 1
  fi

  log_to_global_file "INFO" "Checking physical interface '$PHYS_IF'..."
  if ! ifconfig "$PHYS_IF" > /dev/null 2>&1; then
    display_and_log "ERROR" "Physical interface '$PHYS_IF' not found."
    exit 1
  fi

  # Bring up the physical interface
  log_to_global_file "INFO" "Activating physical interface '$PHYS_IF'..."
  if ! ifconfig "$PHYS_IF" up; then
      log_to_global_file "WARNING" "Could not bring up physical interface '$PHYS_IF', it may already be up."
  fi

  MEMBER_IF="$PHYS_IF"
  if [ -n "$VLAN_TAG" ]; then
    VLAN_IF="vlan${VLAN_TAG}"
    if ! ifconfig "$VLAN_IF" > /dev/null 2>&1; then
      log_to_global_file "INFO" "Creating VLAN interface '$VLAN_IF'..."
      if ! ifconfig "$VLAN_IF" create; then
        display_and_log "ERROR" "Failed to create VLAN interface '$VLAN_IF'."
        exit 1
      fi
      log_to_global_file "INFO" "Configuring '$VLAN_IF' with tag '$VLAN_TAG' on top of '$PHYS_IF'..."
      if ! ifconfig "$VLAN_IF" vlan "$VLAN_TAG" vlandev "$PHYS_IF"; then
        display_and_log "ERROR" "Failed to configure VLAN interface '$VLAN_IF'."
        exit 1
      fi
      log_to_global_file "INFO" "VLAN interface '$VLAN_IF' successfully configured."
      display_and_log "INFO" "Successfully created interface $VLAN_IF with VLAN $VLAN_TAG and vlandev to $PHYS_IF."
    else
      log_to_global_file "INFO" "VLAN interface '$VLAN_IF' already exists."
    fi
    MEMBER_IF="$VLAN_IF"
    # Bring up the vlan interface
    log_to_global_file "INFO" "Activating VLAN interface '$MEMBER_IF'..."
    if ! ifconfig "$MEMBER_IF" up; then
        log_to_global_file "WARNING" "Could not bring up vlan interface '$MEMBER_IF', it may already be up."
    fi
  fi

  log_to_global_file "INFO" "Checking bridge '$BRIDGE_NAME'..."
  if ! ifconfig "$BRIDGE_NAME" > /dev/null 2>&1; then
    log_to_global_file "INFO" "Bridge interface '$BRIDGE_NAME' does not exist. Creating..."
    if ! ifconfig "$BRIDGE_NAME" create; then
      display_and_log "ERROR" "Failed to create bridge '$BRIDGE_NAME'."
      exit 1
    fi
    log_to_global_file "INFO" "Bridge interface '$BRIDGE_NAME' successfully created."
  else
    log_to_global_file "INFO" "Bridge interface '$BRIDGE_NAME' already exists."
  fi

  # Bring up the bridge interface
  log_to_global_file "INFO" "Activating bridge interface '$BRIDGE_NAME'..."
  if ! ifconfig "$BRIDGE_NAME" up; then
      log_to_global_file "WARNING" "Could not bring up bridge interface '$BRIDGE_NAME', it may already be up."
  fi

  if ! ifconfig "$BRIDGE_NAME" | grep -qw "$MEMBER_IF"; then
    log_to_global_file "INFO" "Adding '$MEMBER_IF' to bridge '$BRIDGE_NAME'..."
    if ! ifconfig "$BRIDGE_NAME" addm "$MEMBER_IF"; then
      display_and_log "ERROR" "Failed to add '$MEMBER_IF' to bridge '$BRIDGE_NAME'."
      exit 1
    fi
    log_to_global_file "INFO" "Interface '$MEMBER_IF' successfully added to bridge '$BRIDGE_NAME'."
    display_and_log "INFO" "Now interface '$MEMBER_IF' is a member of bridge '$BRIDGE_NAME'."
  else
    log_to_global_file "INFO" "Interface '$MEMBER_IF' is already a member of bridge '$BRIDGE_NAME'."
  fi

  display_and_log "SUCCESS" "Switch '$BRIDGE_NAME' configured successfully."

  # Save switch configuration only if called directly
  if [ "$SAVE_CONFIG" = true ]; then
    touch "$SWITCH_CONFIG_FILE"
    # Check for duplicates before saving
    if ! grep -qxF "$BRIDGE_NAME $PHYS_IF $VLAN_TAG" "$SWITCH_CONFIG_FILE"; then
        echo "$BRIDGE_NAME $PHYS_IF $VLAN_TAG" >> "$SWITCH_CONFIG_FILE"
        log_to_global_file "INFO" "Switch configuration saved to $SWITCH_CONFIG_FILE"
    else
        log_to_global_file "INFO" "Switch configuration for '$BRIDGE_NAME' already exists."
    fi
  fi
}
