#!/usr/local/bin/bash

# === Log Function with Timestamp ===
log() {
  local TIMESTAMP_MESSAGE
  TIMESTAMP_MESSAGE="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
  # Write to VM-specific log file if LOG_FILE is set
  if [ -n "$LOG_FILE" ]; then
    echo "$TIMESTAMP_MESSAGE" >> "$LOG_FILE"
  fi
  # Always write to global log file for verbose debugging
  echo "$TIMESTAMP_MESSAGE" >> "$GLOBAL_LOG_FILE"
}

# === Function to echo messages to console without timestamp ===
echo_message() {
  echo -e "$1" >&2
}

# === Function to display message to console with timestamp and log to file ===
display_and_log() {
  local LEVEL="$1"
  local MESSAGE="$2"
  local TIMESTAMP_MESSAGE
  TIMESTAMP_MESSAGE="[$(date '+%Y-%m-%d %H:%M:%S')] [$LEVEL] $MESSAGE"
  echo "$MESSAGE" >&2 # === Display to console without timestamp or INFO prefix ===
  # Write to VM-specific log file if LOG_FILE is set
  if [ -n "$LOG_FILE" ]; then
    echo "$TIMESTAMP_MESSAGE" >> "$LOG_FILE"
  fi
  # Always write to global log file
  echo "$TIMESTAMP_MESSAGE" >> "$GLOBAL_LOG_FILE"
}

# === Function to write to global log file only ===
log_to_global_file() {
  local LEVEL="$1"
  local MESSAGE="$2"
  if [ -n "$GLOBAL_LOG_FILE" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$LEVEL] $MESSAGE" >> "$GLOBAL_LOG_FILE"
  fi
}

# === Spinner Functions ===
_spinner_chars='|/-\'
_spinner_pid=

start_spinner() {
  local message="$1"
  echo -n "$message"
  (
    while :; do
      for (( i=0; i<${#_spinner_chars}; i++ )); do
        echo -ne "${_spinner_chars:$i:1}"
        echo -ne "\b"
        sleep 0.1
      done
    done
  ) &
  _spinner_pid=$!
  trap stop_spinner EXIT
}

stop_spinner() {
  if [[ -n "$_spinner_pid" ]]; then
    kill "$_spinner_pid" >/dev/null 2>&1
    wait "$_spinner_pid" 2>/dev/null
    echo -ne "\n"
  fi
}

# === Prerequisite Checks ===
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo_message "ERROR This script must be run with superuser (root) privileges."
    exit 1
  fi
}

check_kld() {
  if ! kldstat -q -m "$1"; then
    display_and_log "ERROR" "Kernel module '$1.ko' is not loaded. Please run 'kldload $1'."
    exit 1
  fi
}

# === Helper function to check if a VM is running ===
is_vm_running() {
  local VMNAME_CHECK="$1"
  get_vm_pid "$VMNAME_CHECK" > /dev/null
  return $?
}

# === Helper functions for VM PID file management ===
get_vm_pid() {
  local VMNAME_GET_PID="$1"
  local VM_DIR_GET_PID="$VM_CONFIG_BASE_DIR/$VMNAME_GET_PID"
  local PID=""
  if [ -f "$VM_DIR_GET_PID/vm.pid" ]; then
    PID=$(cat "$VM_DIR_GET_PID/vm.pid")
    if [ -n "$PID" ] && ps -p "$PID" > /dev/null 2>&1; then
      echo "$PID"
      return 0
    fi
  fi
  # Fallback to pgrep if vm.pid is not found or invalid
  PID=$(pgrep -f "bhyve .* $VMNAME_GET_PID$")
  if [ -n "$PID" ] && ps -p "$PID" > /dev/null 2>&1; then
    echo "$PID"
    return 0
  fi
  return 1 # PID not found
}

save_vm_pid() {
  local VMNAME_SAVE_PID="$1"
  local PID_TO_SAVE="$2"
  local VM_DIR_SAVE_PID="$VM_CONFIG_BASE_DIR/$VMNAME_SAVE_PID"
  echo "$PID_TO_SAVE" > "$VM_DIR_SAVE_PID/vm.pid"
}

delete_vm_pid() {
  local VMNAME_DELETE_PID="$1"
  local VM_DIR_DELETE_PID="$VM_CONFIG_BASE_DIR/$VMNAME_DELETE_PID"
  if [ -f "$VM_DIR_DELETE_PID/vm.pid" ]; then
    rm "$VM_DIR_DELETE_PID/vm.pid"
  fi
}

# === Function to clean up VM processes ===
cleanup_vm_processes() {
  log "Entering cleanup_vm_processes for VM: $1"
  local VM_NAME_CLEANUP="$1"
  local CONSOLE_DEVICE_CLEANUP="$2"
  local LOG_FILE_CLEANUP="$3"

  # Explicitly kill bhyve process associated with this VMNAME
  local VM_PIDS_TO_KILL
  VM_PIDS_TO_KILL=$(get_vm_pid "$VM_NAME_CLEANUP")
  if [ -n "$VM_PIDS_TO_KILL" ]; then
      local PIDS_STRING
  PIDS_STRING=$(echo "$VM_PIDS_TO_KILL" | tr '\n' ' ')
      log "Sending TERM signal to bhyve PID(s): $PIDS_STRING"
      kill $VM_PIDS_TO_KILL
      sleep 1 # Give it a moment to terminate

      for pid_to_check in $VM_PIDS_TO_KILL; do
          if ps -p "$pid_to_check" > /dev/null 2>&1; then
              log "PID $pid_to_check still running, forcing KILL..."
              kill -9 "$pid_to_check"
              sleep 1
          fi
      done
      log "bhyve process(es) stopped."
  else
      log "No bhyve process found for '$VM_NAME_CLEANUP' to kill."
  fi

  # Now, destroy from kernel memory
  if $BHYVECTL --vm="$VM_NAME_CLEANUP" --destroy > /dev/null 2>&1; then
      log "VM '$VM_NAME_CLEANUP' successfully destroyed from kernel memory."
  else
      log "VM '$VM_NAME_CLEANUP' was not found in kernel memory (already destroyed or never started)."
  fi

  # Kill any lingering cu or tail -f processes
  log "Attempting to stop associated cu processes for /dev/${CONSOLE_DEVICE_CLEANUP}B and /dev/${CONSOLE_DEVICE_CLEANUP}A..."
  pkill -f "cu -l /dev/${CONSOLE_DEVICE_CLEANUP}B" > /dev/null 2>&1
  pkill -f "cu -l /dev/${CONSOLE_DEVICE_CLEANUP}A" > /dev/null 2>&1

  # Only kill tail -f process if it's not the global log file and is not empty
  if [ -n "$LOG_FILE_CLEANUP" ] && [ "$LOG_FILE_CLEANUP" != "$GLOBAL_LOG_FILE" ]; then
    log "Attempting to stop associated tail -f process for $LOG_FILE_CLEANUP..."
    pkill -f "tail -f $LOG_FILE_CLEANUP" > /dev/null 2>&1
  else
    log "Skipping termination of tail -f for global log file or empty log path: $LOG_FILE_CLEANUP."
  fi
  log "Exiting cleanup_vm_processes for VM: $VM_NAME_CLEANUP"
}

# === Helper Functions ===
ensure_nmdm_device_nodes() {
  local CONSOLE_DEVICE="$1"
  if [ ! -e "/dev/${CONSOLE_DEVICE}A" ]; then
    log "Creating nmdm device node /dev/${CONSOLE_DEVICE}A"
    mknod "/dev/${CONSOLE_DEVICE}A" c 106 0
    local MKNOD_A_EXIT_CODE=$?
    if [ $MKNOD_A_EXIT_CODE -ne 0 ]; then
      display_and_log "ERROR" "Failed to create /dev/${CONSOLE_DEVICE}A (mknod exit code: $MKNOD_A_EXIT_CODE)"; exit 1;
    fi
    chmod 660 "/dev/${CONSOLE_DEVICE}A"
    local CHMOD_A_EXIT_CODE=$?
    if [ $CHMOD_A_EXIT_CODE -ne 0 ]; then
      display_and_log "ERROR" "Failed to set permissions for /dev/${CONSOLE_DEVICE}A (chmod exit code: $CHMOD_A_EXIT_CODE)"; exit 1;
    fi
    log "Created /dev/${CONSOLE_DEVICE}A. Permissions: $(stat -f "%Sp" "/dev/${CONSOLE_DEVICE}A")"
  fi
  if [ ! -e "/dev/${CONSOLE_DEVICE}B" ]; then
    log "Creating nmdm device node /dev/${CONSOLE_DEVICE}B"
    mknod "/dev/${CONSOLE_DEVICE}B" c 106 1
    local MKNOD_B_EXIT_CODE=$?
    if [ $MKNOD_B_EXIT_CODE -ne 0 ]; then
      display_and_log "ERROR" "Failed to create /dev/${CONSOLE_DEVICE}B (mknod exit code: $MKNOD_B_EXIT_CODE)"; exit 1;
    fi
    chmod 660 "/dev/${CONSOLE_DEVICE}B"
    local CHMOD_B_EXIT_CODE=$?
    if [ $CHMOD_B_EXIT_CODE -ne 0 ]; then
      display_and_log "ERROR" "Failed to set permissions for /dev/${CONSOLE_DEVICE}B (chmod exit code: $CHMOD_B_EXIT_CODE)"; exit 1;
    fi
    log "Created /dev/${CONSOLE_DEVICE}B. Permissions: $(stat -f "%Sp" "/dev/${CONSOLE_DEVICE}B")"
  fi
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
  ifconfig "$TAP_NAME" create || { log_to_global_file "ERROR" "Failed to create TAP interface '$TAP_NAME'. Command: '$CREATE_TAP_CMD'"; return 1; }
  log "TAP interface '$TAP_NAME' successfully created."

  log "Setting TAP description for '$TAP_NAME'..."
  local TAP_DESC="vmnet/${VM_NAME}/${NIC_IDX}/${BRIDGE_NAME}"
  local DESC_TAP_CMD="ifconfig \"$TAP_NAME\" description \"$TAP_DESC\""
  log "Executing: $DESC_TAP_CMD"
  ifconfig "$TAP_NAME" description "$TAP_DESC" || { log_to_global_file "WARNING" "Failed to set description for TAP interface '$TAP_NAME'. Command: '$DESC_TAP_CMD'"; }
  log "TAP description for '$TAP_NAME' set to: '$TAP_DESC'."

  log "Activating TAP interface '$TAP_NAME'..."
  local ACTIVATE_TAP_CMD="ifconfig \"$TAP_NAME\" up"
  log "Executing: $ACTIVATE_TAP_CMD"
  ifconfig "$TAP_NAME" up || { log_to_global_file "ERROR" "Failed to activate TAP interface '$TAP_NAME'. Command: '$ACTIVATE_TAP_CMD'"; return 1; }
  log "TAP '$TAP_NAME' activated successfully."

  # === Check and create bridge interface if it doesn't exist ===
  if ! ifconfig "$BRIDGE_NAME" > /dev/null 2>&1; then
    log "Bridge interface '$BRIDGE_NAME' does not exist. Attempting to create..."
    local CREATE_BRIDGE_CMD="ifconfig bridge create name \"$BRIDGE_NAME\""
    log "Executing: $CREATE_BRIDGE_CMD"
    ifconfig bridge create name "$BRIDGE_NAME" || { log_to_global_file "ERROR" "Failed to create bridge '$BRIDGE_NAME'. Command: '$CREATE_BRIDGE_CMD'"; return 1; }
    log "Bridge interface '$BRIDGE_NAME' successfully created."
  else
    log "Bridge interface '$BRIDGE_NAME' already exists. Skipping creation."
  fi

  log "Adding TAP '$TAP_NAME' to bridge '$BRIDGE_NAME'..."
  local ADD_TAP_TO_BRIDGE_CMD="ifconfig \"$BRIDGE_NAME\" addm \"$TAP_NAME\""
  log "Executing: $ADD_TAP_TO_BRIDGE_CMD"
  ifconfig "$BRIDGE_NAME" addm "$TAP_NAME" || { log_to_global_file "ERROR" "Failed to add TAP '$TAP_NAME' to bridge '$BRIDGE_NAME'. Command: '$ADD_TAP_TO_BRIDGE_CMD'"; return 1; }
  log "TAP '$TAP_NAME' successfully added to bridge '$BRIDGE_NAME'."

  return 0
}

# === Helper function to build disk arguments ===
build_disk_args() {
  local VM_DIR="$1"
  local DISK_ARGS=""
  local DISK_DEV_NUM=3 # Starting device number for virtio-blk

  local CURRENT_DISK_IDX=0
  while true; do
    local CURRENT_DISK_VAR="DISK"
    if [ "$CURRENT_DISK_IDX" -gt 0 ]; then
      CURRENT_DISK_VAR="DISK_${CURRENT_DISK_IDX}"
    fi
    local CURRENT_DISK_FILENAME="${!CURRENT_DISK_VAR}"

    if [ -z "$CURRENT_DISK_FILENAME" ]; then
      break # No more disks configured
    fi

    local CURRENT_DISK_PATH="$VM_DIR/$CURRENT_DISK_FILENAME"
    if [ ! -f "$CURRENT_DISK_PATH" ]; then
      display_and_log "ERROR" "Disk image '$CURRENT_DISK_PATH' not found!"
      echo "" # Return empty string for DISK_ARGS
      echo "1" # Indicate error for next_dev_num (arbitrary non-zero to signal error)
      return 1
    fi
    DISK_ARGS+=" -s ${DISK_DEV_NUM}:0,virtio-blk,\""$CURRENT_DISK_PATH"\""
    DISK_DEV_NUM=$((DISK_DEV_NUM + 1))
    CURRENT_DISK_IDX=$((CURRENT_DISK_IDX + 1))
  done
  echo "$DISK_ARGS"
  echo "$DISK_DEV_NUM" # Echo the next available device number
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
        local CREATE_BRIDGE_CMD="ifconfig bridge create name \"$BRIDGE_NAME\""
        log "Executing: $CREATE_BRIDGE_CMD"
        ifconfig bridge create name "$BRIDGE_NAME" || { display_and_log "ERROR" "Failed to create bridge '$CURRENT_BRIDGE'. Command: '$CREATE_BRIDGE_CMD'"; return 1; }
        log "Bridge interface '$BRIDGE_NAME' successfully created."
      fi

      if ! ifconfig "$CURRENT_BRIDGE" | grep -qw "$CURRENT_TAP"; then
        log "Adding TAP '$CURRENT_TAP' to bridge '$CURRENT_BRIDGE'...";
        local ADD_TAP_TO_BRIDGE_CMD="ifconfig \"$BRIDGE_NAME\" addm \"$CURRENT_TAP\""
        log "Executing: $ADD_TAP_TO_BRIDGE_CMD"
        ifconfig "$BRIDGE_NAME" addm "$CURRENT_TAP" || { display_and_log "ERROR" "Failed to add TAP '$CURRENT_TAP' to bridge '$CURRENT_BRIDGE'. Command: '$ADD_TAP_TO_BRIDGE_CMD'"; return 1; }
      else
        log "TAP '$CURRENT_TAP' already connected to bridge '$CURRENT_BRIDGE'."
      fi
    fi

    NETWORK_ARGS+=" -s ${NIC_DEV_NUM}:0,virtio-net,\""$CURRENT_TAP"\",mac=\""$CURRENT_MAC"\""
    NIC_DEV_NUM=$((NIC_DEV_NUM + 1))
    NIC_IDX=$((NIC_IDX + 1))
  done
  echo "$NETWORK_ARGS"
  return 0
}

run_bhyveload() {
  local DATA_PATH="$1"
  local QUIET_LOAD="${2:-false}" # New optional parameter

  if [ "$QUIET_LOAD" = true ]; then
    log "Loading kernel via bhyveload (quiet mode)..."
    $BHYVELOAD -m "$MEMORY" -d "$DATA_PATH" -c stdio "$VMNAME" > /dev/null 2>&1
  else
    display_and_log "INFO" "Loading kernel via bhyveload..."
    $BHYVELOAD -m "$MEMORY" -d "$DATA_PATH" -c stdio "$VMNAME"
  fi
  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo_message "[ERROR] bhyveload failed with exit code $exit_code. Cannot proceed."
    $BHYVECTL --vm="$VMNAME" --destroy > /dev/null 2>&1
    return 1
  fi
  log "bhyveload completed successfully."
  return 0
}



# === Function to clean up VM network interfaces ===
cleanup_vm_network_interfaces() {
  log "Entering cleanup_vm_network_interfaces function for VM: $1"
  local VMNAME_CLEANUP="$1"
  local VM_DIR_CLEANUP="$VM_CONFIG_BASE_DIR/$VMNAME_CLEANUP"
  local CONF_FILE_CLEANUP="$VM_DIR_CLEANUP/vm.conf"

  if [ ! -f "$CONF_FILE_CLEANUP" ]; then
    log "VM config file not found for $VMNAME_CLEANUP. Skipping network cleanup."
    return
  fi

  log "Cleaning up network interfaces for VM '$VMNAME_CLEANUP'..."

  local NIC_IDX=0
  while true; do
    local CURRENT_TAP_VAR="TAP_${NIC_IDX}"
    local CURRENT_BRIDGE_VAR="BRIDGE_${NIC_IDX}"

    local CURRENT_TAP="${!CURRENT_TAP_VAR}"
    local CURRENT_BRIDGE="${!CURRENT_BRIDGE_VAR}"

    if [ -z "$CURRENT_TAP" ]; then
      break # No more network interfaces configured
    fi

    if ifconfig "$CURRENT_BRIDGE" | grep -qw "$CURRENT_TAP"; then
      log "Removing TAP '$CURRENT_TAP' from bridge '$CURRENT_BRIDGE'..."
      if ! ifconfig "$CURRENT_BRIDGE" deletem "$CURRENT_TAP"; then
        log "WARNING: Failed to remove TAP '$CURRENT_TAP' from bridge '$CURRENT_BRIDGE'."
      fi
    fi

    if ifconfig "$CURRENT_TAP" > /dev/null 2>&1; then
      log "Destroying TAP interface '$CURRENT_TAP'..."
      if ! ifconfig "$CURRENT_TAP" destroy; then
        log "WARNING: Failed to destroy TAP interface '$CURRENT_TAP'."
      fi
    fi
    NIC_IDX=$((NIC_IDX + 1))
  done
  log "Network interface cleanup for '$VMNAME_CLEANUP' complete."
  log "Exiting cleanup_vm_network_interfaces function for VM: $VMNAME_CLEANUP"
}



# === Function to load main configuration ===
load_config() {
  if [ -f "$MAIN_CONFIG_FILE" ]; then
      # shellcheck disable=SC1090
    . "$MAIN_CONFIG_FILE"
  fi
  # Set default log file if not set in config
  GLOBAL_LOG_FILE="${GLOBAL_LOG_FILE:-/var/log/bhyve-cli.log}"
  VM_CONFIG_BASE_DIR="${VM_CONFIG_BASE_DIR:-$CONFIG_DIR/vm.d}" # Ensure default if not in config
}

# === Function to check if the script has been initialized ===
check_initialization() {
  if [ "$1" != "init" ] && [ ! -f "$MAIN_CONFIG_FILE" ]; then
    echo_message "\n[ERROR] bhyve-cli has not been initialized."
    echo_message "Please run the command '$0 init' to generate the required configuration files."
    exit 1
  fi
}


# === Function to load VM configuration ===
load_vm_config() {
  VMNAME="$1"
  VM_DIR="$VM_CONFIG_BASE_DIR/$VMNAME"
  CONF_FILE="$VM_DIR/vm.conf"

  if [ ! -f "$CONF_FILE" ]; then
    display_and_log "ERROR" "VM configuration '$VMNAME' not found: $CONF_FILE"
    exit 1
  fi
    # shellcheck disable=SC1090
  . "$CONF_FILE"
  LOG_FILE="$VM_DIR/vm.log" # Set LOG_FILE after loading config
  BOOTLOADER_TYPE="${BOOTLOADER_TYPE:-bhyveload}" # Default to bhyveload if not set
}
