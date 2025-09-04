#!/usr/local/bin/bash

# === Subcommand: switch destroy ===
cmd_switch_destroy() {
  if [ -z "$1" ]; then
    cmd_switch_destroy_usage
    exit 1
  fi

  local BRIDGE_NAME="$1"

  log_to_global_file "INFO" "Initiating destruction of bridge '$BRIDGE_NAME'."
  if ! ifconfig "$BRIDGE_NAME" > /dev/null 2>&1; then
    echo_message "[ERROR] Bridge '$BRIDGE_NAME' not found."
    log_to_global_file "ERROR" "Bridge '$BRIDGE_NAME' not found. Aborting destruction."
    exit 1
  fi

  MEMBERS=$(ifconfig "$BRIDGE_NAME" | grep 'member:' | awk '{print $2}')

  if [ -n "$MEMBERS" ]; then
    echo_message "\nWARNING: Bridge '$BRIDGE_NAME' has active members:"
    for MEMBER in $MEMBERS; do
      echo_message "  - $MEMBER"
    done
    echo_message "\nDestroying this bridge will also remove all its members and their configurations."
    read -rp "Are you sure you want to destroy bridge '$BRIDGE_NAME' and all its members? (y/n): " CONFIRM_DESTROY
    if ! [[ "$CONFIRM_DESTROY" =~ ^[Yy]$ ]]; then
      echo_message "Bridge destruction cancelled."
      log_to_global_file "INFO" "User cancelled bridge destruction."
      exit 0
    fi
  else
    echo_message "\nBridge '$BRIDGE_NAME' is empty."
    read -rp "Are you sure you want to destroy bridge '$BRIDGE_NAME'? (y/n): " CONFIRM_DESTROY
    if ! [[ "$CONFIRM_DESTROY" =~ ^[Yy]$ ]]; then
      echo_message "Bridge destruction cancelled."
      log_to_global_file "INFO" "User cancelled bridge destruction."
      exit 0
    fi
  fi

  if [ -n "$MEMBERS" ]; then
    echo_message "Removing members from bridge '$BRIDGE_NAME'...
"
    for MEMBER in $MEMBERS; do
      log_to_global_file "INFO" "Executing: ifconfig \"$BRIDGE_NAME\" deletem \"$MEMBER\""
      if ! ifconfig "$BRIDGE_NAME" deletem "$MEMBER"; then
        echo_message "[WARNING] Failed to remove member '$MEMBER' from bridge '$BRIDGE_NAME'."
        log_to_global_file "WARNING" "Command 'ifconfig \"$BRIDGE_NAME\" deletem \"$MEMBER\"' failed."
      else
        echo_message "  - Member '$MEMBER' removed."
        log_to_global_file "INFO" "Member '$MEMBER' successfully removed from bridge '$BRIDGE_NAME'."
      fi

      if [[ "$MEMBER" =~ ^vlan[0-9]+$ ]]; then
        log_to_global_file "INFO" "Executing: ifconfig \"$MEMBER\" destroy"
        if ! ifconfig "$MEMBER" destroy; then
          echo_message "[WARNING] Failed to destroy VLAN interface '$MEMBER'."
          log_to_global_file "WARNING" "Command 'ifconfig \"$MEMBER\" destroy' failed."
        else
          echo_message "  - VLAN interface '$MEMBER' destroyed."
          log_to_global_file "INFO" "VLAN interface '$MEMBER' successfully destroyed."
        fi
      fi
    done
  fi

  echo_message "Destroying bridge '$BRIDGE_NAME'...
"
  log_to_global_file "INFO" "Executing: ifconfig \"$BRIDGE_NAME\" destroy"
  if ! ifconfig "$BRIDGE_NAME" destroy; then
    echo_message "[ERROR] Failed to destroy bridge '$BRIDGE_NAME'."
    log_to_global_file "ERROR" "Command 'ifconfig \"$BRIDGE_NAME\" destroy' failed."
    exit 1
  fi
  echo_message "Bridge '$BRIDGE_NAME' successfully destroyed."
  log_to_global_file "INFO" "Bridge '$BRIDGE_NAME' successfully destroyed."

  if [ -f "$SWITCH_CONFIG_FILE" ]; then
    log_to_global_file "INFO" "Removing configuration line for '$BRIDGE_NAME' from $SWITCH_CONFIG_FILE."
    sed -i '' "/^$BRIDGE_NAME /d" "$SWITCH_CONFIG_FILE"
  fi
}