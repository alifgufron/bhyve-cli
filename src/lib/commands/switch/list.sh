#!/usr/local/bin/bash

# === Subcommand: switch list ===
cmd_switch_list() {
  echo_message "List of Bridge Interfaces:"
  BRIDGES=$(ifconfig -l | tr ' ' '\n' | grep '^bridge')

  if [ -z "$BRIDGES" ]; then
    display_and_log "INFO" "No bridge interfaces found."
    return
  fi

  # Read switch.conf into an associative array for quick lookup
  declare -A BRIDGE_VLAN_MAP
  if [ -f "$SWITCH_CONFIG_FILE" ]; then
    while read -r bridge_name phys_if vlan_tag; do
      if [ -n "$vlan_tag" ]; then
        BRIDGE_VLAN_MAP["$bridge_name"]="$phys_if"
      fi
    done < "$SWITCH_CONFIG_FILE"
  fi

  # --- NEW LOGIC: Build a map of TAP interfaces to VM names ---
  declare -A TAP_TO_VM_MAP
  for VMCONF_FILE in "$VM_CONFIG_BASE_DIR"/*/vm.conf; do
    if [ -f "$VMCONF_FILE" ]; then
      local VM_NAME_FROM_CONF=$(grep "^VMNAME=" "$VMCONF_FILE" | cut -d'=' -f2)
      local NIC_IDX=0
      while true; do
        local TAP_VAR_NAME="TAP_${NIC_IDX}"
        local TAP_NAME_FROM_CONF=$(grep "^${TAP_VAR_NAME}=" "$VMCONF_FILE" | cut -d'=' -f2)
        if [ -z "$TAP_NAME_FROM_CONF" ]; then
          break
        fi
        TAP_TO_VM_MAP["$TAP_NAME_FROM_CONF"]="$VM_NAME_FROM_CONF"
        NIC_IDX=$((NIC_IDX + 1))
      done
    fi
  done
  # --- END NEW LOGIC ---

  for BRIDGE_IF in $BRIDGES; do
    echo_message "----------------------------------------"
    local DISPLAY_NAME="$BRIDGE_IF"
    if [ -n "${BRIDGE_VLAN_MAP["$BRIDGE_IF"]}" ]; then
      DISPLAY_NAME="$BRIDGE_IF vlandev ${BRIDGE_VLAN_MAP["$BRIDGE_IF"]}"
    fi
    echo_message "Name: $DISPLAY_NAME"
    MEMBERS=$(ifconfig "$BRIDGE_IF" | grep 'member:' | awk '{print $2}')
    if [ -n "$MEMBERS" ]; then
      echo_message "  Members:"
      for MEMBER in $MEMBERS; do
        local VM_INFO=""
        if [[ "$MEMBER" =~ ^tap[0-9]+$ ]]; then # Check if it's a TAP interface
          if [ -n "${TAP_TO_VM_MAP["$MEMBER"]}" ]; then
            VM_INFO=" [vmnet/${TAP_TO_VM_MAP["$MEMBER"]}]"
          fi
        fi
        echo_message "  - $MEMBER$VM_INFO"
      done
    else
      echo_message "  No members."
    fi
  done
  echo_message "----------------------------------------"
}