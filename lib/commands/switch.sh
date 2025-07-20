#!/usr/local/bin/bash

cmd_switch() {
  if [ -z "$1" ]; then
    cmd_switch_usage
    exit 1
  fi

  local SUBCOMMAND="$1"
  shift

  case "$SUBCOMMAND" in
    init)
      cmd_switch_init
      ;;
    add)
      cmd_switch_add "$@"
      ;;
    list)
      cmd_switch_list
      ;;
    destroy)
      cmd_switch_destroy "$@"
      ;;
    delete)
      cmd_switch_delete "$@"
      ;;
    --help|help)
      cmd_switch_usage
      ;;
    *)
      display_and_log "ERROR" "Invalid subcommand for 'switch': $SUBCOMMAND"
      cmd_switch_usage
      exit 1
      ;;
  esac
}


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

# === Subcommand: switch init ===
cmd_switch_init() {
    if [ ! -f "$SWITCH_CONFIG_FILE" ]; then
        display_and_log "INFO" "Switch configuration file not found. Nothing to do."
        return
    fi

    display_and_log "INFO" "Initializing switches from $SWITCH_CONFIG_FILE..."
    while read -r bridge_name phys_if vlan_tag; do
        local args=("--name" "$bridge_name" "--interface" "$phys_if" "--no-save")
        if [ -n "$vlan_tag" ]; then
            args+=("--vlan" "$vlan_tag")
        fi
        cmd_switch_add "${args[@]}"
    done < "$SWITCH_CONFIG_FILE"
    display_and_log "INFO" "Switch initialization complete."
}





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

# === Subcommand: switch remove ===
# This subcommand was removed in a previous refactoring.


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
    echo_message "Removing members from bridge '$BRIDGE_NAME'..."
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

  echo_message "Destroying bridge '$BRIDGE_NAME'..."
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
