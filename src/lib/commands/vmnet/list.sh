#!/usr/local/bin/bash

# === Subcommand: vmnet list ===
cmd_vmnet_list() {
  local VMNET_CONFIG_FILE="$CONFIG_DIR/vmnet.conf"

  echo_message "Configured VM Networks:"
  echo_message "---------------------------------"

  if [ ! -f "$VMNET_CONFIG_FILE" ] || [ ! -s "$VMNET_CONFIG_FILE" ]; then
    display_and_log "INFO" "No vmnet configurations found."
    echo_message "---------------------------------"
    return
  fi

  while read -r BRIDGE_NAME IP_ADDRESS; do
    echo_message "Name: $BRIDGE_NAME"
    echo_message "  IP Address: ${IP_ADDRESS:-N/A}"
    if ifconfig "$BRIDGE_NAME" > /dev/null 2>&1; then
      echo_message "  Status:     Active"
      MEMBERS=$(ifconfig "$BRIDGE_NAME" | grep 'member:' | awk '{print $2}')
      if [ -n "$MEMBERS" ]; then
        echo_message "  Members:"
        for MEMBER in $MEMBERS; do
          echo_message "    - $MEMBER"
        done
      else
        echo_message "  Members:    None"
      fi
    else
      echo_message "  Status:     Inactive (Bridge not found)"
    fi
    echo_message "---------------------------------"
  done < "$VMNET_CONFIG_FILE"
}
