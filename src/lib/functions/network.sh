#!/usr/local/bin/bash

# === Helper function to generate a random MAC address ===
generate_mac_address() {
  echo "58:9c:fc$(jot -r -w ":%02x" -s "" 3 0 255)"
}

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
  for VMCONF_FILE in "$VM_CONFIG_BASE_DIR"/*/vm.conf;
  do
    if [ -f "$VMCONF_FILE" ]; then
      local CONFIGURED_TAPS
      CONFIGURED_TAPS=$(grep '^TAP_[0-9]*=' "$VMCONF_FILE" | cut -d'=' -f2 | sed 's/tap//' | sort -n)
      for tap_num in $CONFIGURED_TAPS;
      do
        USED_TAPS+=("$tap_num")
      done
    fi
  done

  # Sort and get unique numbers
  local UNIQUE_USED_TAPS
  UNIQUE_USED_TAPS=$(printf "%s\n" "${USED_TAPS[@]}" | sort -n -u)

  local NEXT_TAP_NUM=0
  for num in $UNIQUE_USED_TAPS;
  do
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
  local VM_DIR="$2"
  local NETWORK_ARGS=""
  local NIC_DEV_NUM=10 # Starting PCI slot for virtio-net

  local NIC_IDX=0
  while true; do
    local CURRENT_BRIDGE_VAR="BRIDGE_${NIC_IDX}"
    local CURRENT_MAC_VAR="MAC_${NIC_IDX}"
    local CURRENT_NIC_TYPE_VAR="NIC_${NIC_IDX}_TYPE"

    local CURRENT_BRIDGE="${!CURRENT_BRIDGE_VAR}"
    local CURRENT_MAC="${!CURRENT_MAC_VAR}"
    local CURRENT_NIC_TYPE="${!CURRENT_NIC_TYPE_VAR:-virtio-net}" # Default to virtio-net

    # If there's no bridge defined for this index, we assume no more NICs.
    if [ -z "$CURRENT_BRIDGE" ]; then
      break
    fi

    # If there's no MAC, something is wrong with the config.
    if [ -z "$CURRENT_MAC" ]; then
        display_and_log "ERROR" "MAC address for NIC${NIC_IDX} is not defined in vm.conf for $VMNAME. Cannot configure network."
        return 1
    fi

    log "Configuring network interface NIC${NIC_IDX} (Bridge: $CURRENT_BRIDGE, MAC: $CURRENT_MAC, Type: $CURRENT_NIC_TYPE)"

    # --- Dynamic TAP Interface Assignment ---
    local NEXT_TAP_NUM
    NEXT_TAP_NUM=$(get_next_available_tap_num)
    local CURRENT_TAP="tap${NEXT_TAP_NUM}"
    log "Assigning dynamically available TAP interface: $CURRENT_TAP"

    # --- Create and Configure TAP ---
    if ! create_and_configure_tap_interface "$CURRENT_TAP" "$CURRENT_MAC" "$CURRENT_BRIDGE" "$VMNAME" "$NIC_IDX"; then
        display_and_log "ERROR" "Failed to create or configure TAP interface $CURRENT_TAP for NIC${NIC_IDX}."
        return 1
    fi

    NETWORK_ARGS+=" -s ${NIC_DEV_NUM}:0,${CURRENT_NIC_TYPE},${CURRENT_TAP},mac=${CURRENT_MAC}"
    NIC_DEV_NUM=$((NIC_DEV_NUM + 1))
    NIC_IDX=$((NIC_IDX + 1))
  done

  echo "$NETWORK_ARGS"
  return 0
}

# === Function to clean up VM network interfaces ===
cleanup_vm_network_interfaces() {
  local VMNAME_CLEANUP="$1"
  if [ -z "$VMNAME_CLEANUP" ]; then
    log "cleanup_vm_network_interfaces called without a VM name. Aborting."
    return 1
  fi

  log "Cleaning up network interfaces for VM: $VMNAME_CLEANUP"

  # Find tap interfaces based on their description, which is more reliable
  local TAP_INTERFACES
  TAP_INTERFACES=$(ifconfig -a | grep -B 1 "description: vmnet/${VMNAME_CLEANUP}/" | grep '^tap' | cut -d':' -f1)

  if [ -z "$TAP_INTERFACES" ]; then
    log "No lingering tap interfaces found for $VMNAME_CLEANUP."
    return 0
  fi

  for tap_if in $TAP_INTERFACES; do
    log "Found lingering tap interface: $tap_if. Destroying..."
    ifconfig "$tap_if" destroy >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      log "Successfully destroyed tap interface: $tap_if"
    else
      log "Warning: Failed to destroy tap interface: $tap_if"
    fi
  done
  log "Network interface cleanup for VM '$VMNAME_CLEANUP' complete."
}
