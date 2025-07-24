#!/usr/local/bin/bash

# === Subcommand: vmnet ===
cmd_vmnet() {
  if [ -z "$1" ]; then
    cmd_vmnet_usage
    exit 1
  fi

  local SUBCOMMAND="$1"
  shift

  case "$SUBCOMMAND" in
    create)
      cmd_vmnet_create "$@"
      ;;
    list)
      cmd_vmnet_list "$@"
      ;;
    destroy)
      cmd_vmnet_destroy "$@"
      ;;
    init)
      cmd_vmnet_init "$@"
      ;;
    --help|help)
      cmd_vmnet_usage
      ;;
    *)
      display_and_log "ERROR" "Invalid subcommand for 'vmnet': $SUBCOMMAND"
      cmd_vmnet_usage
      exit 1
      ;;
  esac
}

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

# === Subcommand: vmnet destroy ===
cmd_vmnet_destroy() {
  local BRIDGE_NAME="$1"

  if [ -z "$BRIDGE_NAME" ]; then
    display_and_log "ERROR" "Bridge name is required for vmnet destroy."
    cmd_vmnet_usage
    exit 1
  fi

  log "Attempting to destroy vmnet bridge '$BRIDGE_NAME'..."

  if ! ifconfig "$BRIDGE_NAME" > /dev/null 2>&1; then
    display_and_log "ERROR" "Bridge '$BRIDGE_NAME' not found or already destroyed."
    # Also remove from config if not found
    local VMNET_CONFIG_FILE="$CONFIG_DIR/vmnet.conf"
    sed -i '' "/^$BRIDGE_NAME /d" "$VMNET_CONFIG_FILE" 2>/dev/null
    exit 1
  fi

  MEMBERS=$(ifconfig "$BRIDGE_NAME" | grep 'member:' | awk '{print $2}')
  if [ -n "$MEMBERS" ]; then
    display_and_log "WARNING" "Bridge '$BRIDGE_NAME' has active members. Destroying it will disconnect them."
    read -rp "Are you sure you want to destroy bridge '$BRIDGE_NAME' and its members? (y/n): " CONFIRM_DESTROY
    if ! [[ "$CONFIRM_DESTROY" =~ ^[Yy]$ ]]; then
      echo_message "Bridge destruction cancelled."
      exit 0
    fi
  fi

  if ! ifconfig "$BRIDGE_NAME" destroy; then
    display_and_log "ERROR" "Failed to destroy bridge '$BRIDGE_NAME'."
    exit 1
  fi
  display_and_log "INFO" "Bridge '$BRIDGE_NAME' destroyed successfully."

  # Remove from vmnet configuration
  local VMNET_CONFIG_FILE="$CONFIG_DIR/vmnet.conf"
  sed -i '' "/^$BRIDGE_NAME /d" "$VMNET_CONFIG_FILE"
  display_and_log "INFO" "Vmnet configuration for '$BRIDGE_NAME' removed."
}

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

# === Usage function for vmnet ===
cmd_vmnet_usage() {
  echo_message "Usage: $0 vmnet <subcommand> [options/arguments]"
  echo_message "\nSubcommands:"
  echo_message "  create --name <bridge_name> [--ip <ip_address/cidr>] - Creates a new isolated virtual network bridge."
  echo_message "  list                                                 - Lists all configured vmnet bridges."
  echo_message "  destroy <bridge_name>                                - Destroys an isolated virtual network bridge."
  echo_message "  init                                                 - Initializes all saved vmnet configurations."
  echo_message "\nOptions for create:"
  echo_message "  --name <bridge_name>         - Name of the isolated bridge to create (e.g., myvmnet0)."
  echo_message "  --ip <ip_address/cidr>       - Optional. IP address and CIDR for the bridge interface (e.g., 192.168.1.1/24)."
  echo_message "\nExamples:"
  echo_message "  $0 vmnet create --name myvmnet0 --ip 192.168.1.1/24"
  echo_message "  $0 vmnet list"
  echo_message "  $0 vmnet destroy myvmnet0"
}
