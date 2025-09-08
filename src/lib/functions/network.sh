#!/usr/local/bin/bash

# === Helper function to find the next available TAP number ===
get_next_available_tap_num() {
  local USED_TAPS=()

  # Get currently active TAP interfaces
  local ACTIVE_TAPS
  ACTIVE_TAPS=$(ifconfig -l | tr ' ' '\n' | grep '^tap' | sed 's/tap//' | sort -n)
  for tap_num in $ACTIVE_TAPS; do
    USED_TAPS+=("$tap_num")
  done

  # Get TAP interfaces configured in all vm.conf files
  for VMCONF_FILE in "$VM_CONFIG_BASE_DIR"/*/vm.conf; do
    if [ -f "$VMCONF_FILE" ]; then
      local CONFIGURED_TAPS
      CONFIGURED_TAPS=$(grep '^TAP_[0-9]*=' "$VMCONF_FILE" | cut -d'=' -f2 | sed 's/tap//' | sort -n)
      for tap_num in $CONFIGURED_TAPS; do
        USED_TAPS+=("$tap_num")
      done
    fi
  done

  # Sort and get unique numbers
  local UNIQUE_USED_TAPS
  UNIQUE_USED_TAPS=$(printf "%s\n" "${USED_TAPS[@]}" | sort -n -u)

  local NEXT_TAP_NUM=0
  for num in $UNIQUE_USED_TAPS; do
    if [ "$num" -eq "$NEXT_TAP_NUM" ]; then
      NEXT_TAP_NUM=$((NEXT_TAP_NUM + 1))
    else
      break # Found a gap
    fi
  done
  echo "$NEXT_TAP_NUM"
}

# === Helper function to create and configure a TAP interface ===
create_and_configure_tap_interface() {
  local TAP_NAME="$1"
  local MAC_ADDRESS="$2"
  local BRIDGE_NAME="$3"
  local VM_NAME="$4"
  local NIC_IDX="$5"

  log "Attempting to create TAP interface '$TAP_NAME'..."
  local CREATE_TAP_CMD="ifconfig \"$TAP_NAME\" create"
  log "Executing: $CREATE_TAP_CMD"
  ifconfig "$TAP_NAME" create || { display_and_log "ERROR" "Failed to create TAP interface '$TAP_NAME'. Command: '$CREATE_TAP_CMD'"; return 1; }
  log "TAP interface '$TAP_NAME' successfully created."

  log "Setting TAP description for '$TAP_NAME'..."
  local TAP_DESC="vmnet/${VM_NAME}/${NIC_IDX}/${BRIDGE_NAME}"
  local DESC_TAP_CMD="ifconfig \"$TAP_NAME\" description \"$TAP_DESC\""
  log "Executing: $DESC_TAP_CMD"
  ifconfig "$TAP_NAME" description "$TAP_DESC" || { display_and_log "WARNING" "Failed to set description for TAP interface '$TAP_NAME'. Command: '$DESC_TAP_CMD'"; }
  log "TAP description for '$TAP_NAME' set to: '$TAP_DESC'."

  log "Activating TAP interface '$TAP_NAME'..."
  local ACTIVATE_TAP_CMD="ifconfig \"$TAP_NAME\" up"
  log "Executing: $ACTIVATE_TAP_CMD"
  ifconfig "$TAP_NAME" up || { display_and_log "ERROR" "Failed to activate TAP interface '$TAP_NAME'. Command: '$ACTIVATE_TAP_CMD'"; return 1; }
  log "TAP '$TAP_NAME' activated successfully."

  # === Check and create bridge interface if it doesn't exist ===
  if ! ifconfig "$BRIDGE_NAME" > /dev/null 2>&1; then
    log "Bridge interface '$BRIDGE_NAME' does not exist. Attempting to create..."
    local CREATE_BRIDGE_CMD="ifconfig bridge create name \"$BRIDGE_NAME\""
    log "Executing: $CREATE_BRIDGE_CMD"
    ifconfig bridge create name "$BRIDGE_NAME" || { display_and_log "ERROR" "Failed to create bridge '$BRIDGE_NAME'. Command: '$CREATE_BRIDGE_CMD'"; return 1; }
    log "Bridge interface '$BRIDGE_NAME' successfully created."
  else
    log "Bridge interface '$BRIDGE_NAME' already exists. Skipping creation."
  fi

  log "Adding TAP '$TAP_NAME' to bridge '$BRIDGE_NAME'..."
  local ADD_TAP_TO_BRIDGE_CMD="ifconfig \"$BRIDGE_NAME\" addm \"$TAP_NAME\""
  log "Executing: $ADD_TAP_TO_BRIDGE_CMD"
  ifconfig "$BRIDGE_NAME" addm "$TAP_NAME" || { display_and_log "ERROR" "Failed to add TAP '$TAP_NAME' to bridge '$BRIDGE_NAME'. Command: '$ADD_TAP_TO_BRIDGE_CMD'"; return 1; }
  log "TAP '$TAP_NAME' successfully added to bridge '$BRIDGE_NAME'."

  return 0
}

# === Helper function to build network arguments ===
build_network_args() {
  local VMNAME="$1"
  local VM_DIR="$2" # Not directly used here, but might be useful for future expansion
  local NETWORK_ARGS=""
  local NIC_DEV_NUM=10 # Starting device number for virtio-net

  local NIC_IDX=0
  while true; do
    local CURRENT_TAP_VAR="TAP_${NIC_IDX}"
    local CURRENT_MAC_VAR="MAC_${NIC_IDX}"
    local CURRENT_BRIDGE_VAR="BRIDGE_${NIC_IDX}"

    local CURRENT_TAP="${!CURRENT_TAP_VAR}"
    local CURRENT_MAC="${!CURRENT_MAC_VAR}"
    local CURRENT_BRIDGE="${!CURRENT_BRIDGE_VAR}"

    if [ -z "$CURRENT_TAP" ]; then
      break # No more network interfaces configured
    fi

    log "Checking network interface NIC_${NIC_IDX} (TAP: $CURRENT_TAP, MAC: $CURRENT_MAC, Bridge: $CURRENT_BRIDGE)"

    # === Create and configure TAP interface if it doesn't exist or activate if it does ===
    if ! ifconfig "$CURRENT_TAP" > /dev/null 2>&1; then
      if ! create_and_configure_tap_interface "$CURRENT_TAP" "$CURRENT_MAC" "$CURRENT_BRIDGE" "$VMNAME" "$NIC_IDX"; then
        return 1
      fi
    else
      log "TAP '$CURRENT_TAP' already exists. Attempting to activate and ensure bridge connection..."
      local ACTIVATE_TAP_CMD="ifconfig \"$CURRENT_TAP\" up"
      log "Executing: $ACTIVATE_TAP_CMD"
      ifconfig "$CURRENT_TAP" up || { display_and_log "ERROR" "Failed to activate existing TAP interface '$CURRENT_TAP'. Command: '$ACTIVATE_TAP_CMD'"; return 1; }
      log "TAP '$CURRENT_TAP' activated."

      # Ensure bridge exists and TAP is a member
      if ! ifconfig "$CURRENT_BRIDGE" > /dev/null 2>&1; then
        log "Bridge interface '$CURRENT_BRIDGE' does not exist. Attempting to create..."
        local CREATE_BRIDGE_CMD="ifconfig bridge create name \"$CURRENT_BRIDGE\""
        log "Executing: $CREATE_BRIDGE_CMD"
        ifconfig bridge create name "$CURRENT_BRIDGE" || { display_and_log "ERROR" "Failed to create bridge '$CURRENT_BRIDGE'. Command: '$CREATE_BRIDGE_CMD'"; return 1; }
        log "Bridge interface '$CURRENT_BRIDGE' successfully created."
      fi

      if ! ifconfig "$CURRENT_BRIDGE" | grep -qw "$CURRENT_TAP"; then
        log "Adding TAP '$CURRENT_TAP' to bridge '$CURRENT_BRIDGE'...";
        local ADD_TAP_TO_BRIDGE_CMD="ifconfig \"$CURRENT_BRIDGE\" addm \"$CURRENT_TAP\""
        log "Executing: $ADD_TAP_TO_BRIDGE_CMD"
        ifconfig "$CURRENT_BRIDGE" addm "$CURRENT_TAP" || { display_and_log "ERROR" "Failed to add TAP '$CURRENT_TAP' to bridge '$CURRENT_BRIDGE'. Command: '$ADD_TAP_TO_BRIDGE_CMD'"; return 1; }
      else
        log "TAP '$CURRENT_TAP' already connected to bridge '$CURRENT_BRIDGE'."
      fi
    fi

    NETWORK_ARGS+=" -s ${NIC_DEV_NUM}:0,virtio-net,\"$CURRENT_TAP\",mac=\"$CURRENT_MAC\""
    NIC_DEV_NUM=$((NIC_DEV_NUM + 1))
    NIC_IDX=$((NIC_IDX + 1))
  done
  echo "$NETWORK_ARGS"
  return 0
}

# === Function to clean up VM network interfaces ===
cleanup_vm_network_interfaces() {
  log "Entering cleanup_vm_network_interfaces function for VM: $1"
  local VMNAME_CLEANUP="$1"

  if [ -z "$VMNAME_CLEANUP" ]; then
    log "No VM name provided to cleanup_vm_network_interfaces. Aborting."
    return 1
  fi

  log "Cleaning up all network interfaces for VM '$VMNAME_CLEANUP' based on description..."

  # Get a list of all tap interfaces on the system
  local ALL_TAPS
  ALL_TAPS=$(ifconfig -l | tr ' ' '\n' | grep '^tap')

  for tap_if in $ALL_TAPS;
  do
    # For each tap, get its description
    local TAP_DESC
    TAP_DESC=$(ifconfig "$tap_if" | grep 'description:' | sed 's/^[[:space:]]*description: //')

    # Check if the description matches our VM name (e.g., starts with vmnet/vm-1/)
    if [[ "$TAP_DESC" == "vmnet/${VMNAME_CLEANUP}/"* ]]; then
      log "Found matching tap: [$tap_if] with description [$TAP_DESC]"

      # Find which bridge it's a member of
      local bridge_if
      bridge_if=$(ifconfig -a | grep -B 5 "member: ${tap_if}" | grep '^bridge' | cut -d':' -f1)

      if [ -n "$bridge_if" ]; then
        log "Removing TAP '$tap_if' from bridge '$bridge_if'…"
        if ! ifconfig "$bridge_if" deletem "$tap_if"; then
          log "WARNING: Failed to remove TAP '$tap_if' from bridge '$bridge_if'."
        fi
      fi

      log "Destroying TAP interface '$tap_if'…"
      if ! ifconfig "$tap_if" destroy; then
        log "WARNING: Failed to destroy TAP interface '$tap_if'."
      fi
    fi
  done

  log "Network interface cleanup for '$VMNAME_CLEANUP' complete."
  log "Exiting cleanup_vm_network_interfaces function for VM: $VMNAME_CLEANUP"
}

