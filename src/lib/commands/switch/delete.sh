#!/usr/local/bin/bash

# === Subcommand: switch delete ===
cmd_switch_delete() {
  local MEMBER_IF=""
  local BRIDGE_NAME=""

  # Parse named arguments
  while (( "$#" )); do
    case "$1" in
      --member)
        shift
        MEMBER_IF="$1"
        ;;
      --from)
        shift
        BRIDGE_NAME="$1"
        ;;
      *)
        display_and_log "ERROR" "Invalid option: $1"
        cmd_switch_delete_usage
        exit 1
        ;;
    esac
    shift
  done

  # Validate required arguments
  if [ -z "$MEMBER_IF" ] || [ -z "$BRIDGE_NAME" ]; then
    cmd_switch_delete_usage
    exit 1
  fi

  log "Checking bridge '$BRIDGE_NAME'..."
  if ! ifconfig "$BRIDGE_NAME" > /dev/null 2>&1; then
    display_and_log "ERROR" "Bridge '$BRIDGE_NAME' not found."
    exit 1
  fi

  log "Checking if '$MEMBER_IF' is a member of '$BRIDGE_NAME'..."
  if ! ifconfig "$BRIDGE_NAME" | grep -qw "$MEMBER_IF"; then
    display_and_log "ERROR" "Interface '$MEMBER_IF' is not a member of bridge '$BRIDGE_NAME'."
    exit 1
  fi

  log "Removing '$MEMBER_IF' from bridge '$BRIDGE_NAME'..."
  if ! ifconfig "$BRIDGE_NAME" deletem "$MEMBER_IF"; then
    display_and_log "ERROR" "Failed to remove '$MEMBER_IF' from bridge '$BRIDGE_NAME'."
    exit 1
  fi
  display_and_log "INFO" "Interface '$MEMBER_IF' successfully removed from bridge '$BRIDGE_NAME'."

  # Check if the removed member was a VLAN interface and destroy it
  if [[ "$MEMBER_IF" =~ ^vlan[0-9]+$ ]]; then
    log "Destroying VLAN interface '$MEMBER_IF'..."
    if ! ifconfig "$MEMBER_IF" destroy; then
      display_and_log "ERROR" "Failed to destroy VLAN interface '$MEMBER_IF'."
      exit 1
    fi
    display_and_log "INFO" "VLAN interface '$MEMBER_IF' successfully destroyed."
  fi

  # Check if bridge is empty after removal
  MEMBERS=$(ifconfig "$BRIDGE_NAME" | grep 'member:' | awk '{print $2}')
  if [ -z "$MEMBERS" ]; then
    read -rp "Bridge '$BRIDGE_NAME' is now empty. Destroy this bridge as well? (y/n): " CONFIRM_DESTROY
    if [[ "$CONFIRM_DESTROY" =~ ^[Yy]$ ]]; then
      log "Destroying bridge '$BRIDGE_NAME'..."
      if ! ifconfig "$BRIDGE_NAME" destroy; then
        display_and_log "ERROR" "Failed to destroy bridge '$BRIDGE_NAME'."
        exit 1
      fi
      display_and_log "INFO" "Bridge '$BRIDGE_NAME' successfully destroyed."
    else
      display_and_log "INFO" "Bridge '$BRIDGE_NAME' not destroyed."
    fi
  else
    display_and_log "INFO" "Bridge '$BRIDGE_NAME' still has members."
  fi
}
