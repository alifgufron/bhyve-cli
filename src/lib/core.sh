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
    _spinner_pid=
    trap - EXIT # Clear the trap
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
  local VM_DIR_CHECK="$2"
  get_vm_pid "$VMNAME_CHECK" "$VM_DIR_CHECK" > /dev/null
  return $?
}

# === Helper functions for VM PID file management ===
get_vm_pid() {
  local VMNAME_GET_PID="$1"
  local VM_DIR_GET_PID="$2"
  local PID=""

  if [ -z "$VM_DIR_GET_PID" ]; then
      log_to_global_file "ERROR" "get_vm_pid called without a VM directory for $VMNAME_GET_PID."
      return 1
  fi

  if [ -f "$VM_DIR_GET_PID/vm.pid" ]; then
    PID=$(cat "$VM_DIR_GET_PID/vm.pid")
    if [ -n "$PID" ] && ps -p "$PID" > /dev/null 2>&1; then
      echo "$PID"
      return 0
    fi
  fi
  # Fallback to pgrep if vm.pid is not found or invalid
  PID=$(pgrep -f "bhyve: $VMNAME_GET_PID\[")
  if [ -n "$PID" ] && ps -p "$PID" > /dev/null 2>&1; then
    echo "$PID"
    return 0
  fi
  return 1 # PID not found
}

save_vm_pid() {
  local VMNAME_SAVE_PID="$1"
  local PID_TO_SAVE="$2"
  local VM_DIR_SAVE_PID="$3"

  if [ -z "$VM_DIR_SAVE_PID" ]; then
      log_to_global_file "ERROR" "save_vm_pid called without a VM directory for $VMNAME_SAVE_PID."
      return
  fi
  echo "$PID_TO_SAVE" > "$VM_DIR_SAVE_PID/vm.pid"
}

delete_vm_pid() {
  local VMNAME_DELETE_PID="$1"
  local VM_DIR_DELETE_PID="$2"

  if [ -z "$VM_DIR_DELETE_IDEL" ]; then
      log_to_global_file "ERROR" "delete_vm_pid called without a VM directory for $VMNAME_DELETE_PID."
      return
  fi

  if [ -f "$VM_DIR_DELETE_IDEL/vm.pid" ]; then
    rm "$VM_DIR_DELETE_IDEL/vm.pid"
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

  log "Attempting to create TAP interface '$TAP_NAME'ப்பான"
  local CREATE_TAP_CMD="ifconfig \"$TAP_NAME\" create"
  log "Executing: $CREATE_TAP_CMD"
  ifconfig "$TAP_NAME" create || { log_to_global_file "ERROR" "Failed to create TAP interface '$TAP_NAME'. Command: '$CREATE_TAP_CMD'"; return 1; }
  log "TAP interface '$TAP_NAME' successfully created."

  log "Setting TAP description for '$TAP_NAME'ப்பான"
  local TAP_DESC="vmnet/${VM_NAME}/${NIC_IDX}/${BRIDGE_NAME}"
  local DESC_TAP_CMD="ifconfig \"$TAP_NAME\" description \"$TAP_DESC\""
  log "Executing: $DESC_TAP_CMD"
  ifconfig "$TAP_NAME" description "$TAP_DESC" || { log_to_global_file "WARNING" "Failed to set description for TAP interface '$TAP_NAME'. Command: '$DESC_TAP_CMD'"; }
  log "TAP description for '$TAP_NAME' set to: '$TAP_DESC'."

  log "Activating TAP interface '$TAP_NAME'ப்பான"
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

  log "Adding TAP '$TAP_NAME' to bridge '$BRIDGE_NAME'ப்பான"
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
    local CURRENT_DISK_TYPE_VAR="DISK_${CURRENT_DISK_IDX}_TYPE"

    if [ "$CURRENT_DISK_IDX" -gt 0 ]; then
      CURRENT_DISK_VAR="DISK_${CURRENT_DISK_IDX}"
    fi
    local CURRENT_DISK_FILENAME="${!CURRENT_DISK_VAR}"
    local DISK_TYPE="${!CURRENT_DISK_TYPE_VAR:-virtio-blk}" # Default to virtio-blk

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
    DISK_ARGS+=" -s ${DISK_DEV_NUM}:0,${DISK_TYPE},\""$CURRENT_DISK_PATH"\""
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
  local CREATED_TAPS=() # Array to store dynamically created TAP interfaces

  local NIC_IDX=0
  while true; do
    local CURRENT_BRIDGE_VAR="BRIDGE_${NIC_IDX}"
    local CURRENT_NIC_TYPE_VAR="NIC_${NIC_IDX}_TYPE"
    local CURRENT_MAC_VAR="MAC_${NIC_IDX}" # New: Read static MAC from vm.conf

    local CURRENT_BRIDGE="${!CURRENT_BRIDGE_VAR}"
    local CURRENT_NIC_TYPE="${!CURRENT_NIC_TYPE_VAR:-virtio-net}" # Default to virtio-net
    local STATIC_MAC="${!CURRENT_MAC_VAR}" # Read static MAC

    if [ -z "$CURRENT_BRIDGE" ]; then
      break # No more network interfaces configured
    fi

    local MAC_TO_USE=""
    if [ -n "$STATIC_MAC" ]; then
      MAC_TO_USE="$STATIC_MAC"
      log "Using static MAC address for NIC_${NIC_IDX}: $STATIC_MAC"
    else
      MAC_TO_USE="58:9c:fc$(jot -r -w ":%02x" -s "" 3 0 255)"
      log "Generating dynamic MAC address for NIC_${NIC_IDX}: $MAC_TO_USE"
    fi

    # Dynamically generate TAP name
    local NEXT_TAP_NUM=$(get_next_available_tap_num)
    local DYNAMIC_TAP_NAME="tap${NEXT_TAP_NUM}"

    log "Creating network interface NIC_${NIC_IDX} (TAP: $DYNAMIC_TAP_NAME, MAC: $MAC_TO_USE, Bridge: $CURRENT_BRIDGE, Type: $CURRENT_NIC_TYPE)"

    if ! create_and_configure_tap_interface "$DYNAMIC_TAP_NAME" "$MAC_TO_USE" "$CURRENT_BRIDGE" "$VMNAME" "$NIC_IDX"; then
      # If creation fails, clean up any TAPs already created in this call
      for tap in "${CREATED_TAPS[@]}"; do
        ifconfig "$tap" destroy > /dev/null 2>&1
      done
      return 1
    fi
    CREATED_TAPS+=("$DYNAMIC_TAP_NAME")

    NETWORK_ARGS+=" -s ${NIC_DEV_NUM}:0,${CURRENT_NIC_TYPE},\"$DYNAMIC_TAP_NAME\",mac=\" $MAC_TO_USE\""
    NIC_DEV_NUM=$((NIC_DEV_NUM + 1))
    NIC_IDX=$((NIC_IDX + 1))
  done
  echo "$NETWORK_ARGS"
  echo "${CREATED_TAPS[@]}" # Return the list of created TAPs
  return 0
}


run_bhyveload() {
  local DATA_PATH="$1"
  local QUIET_LOAD="${2:-false}" # Default to false (interactive) if not provided

  # In 'install' mode (QUIET_LOAD=false), we need an interactive console.
  # In 'start' mode (QUIET_LOAD=true), we just load and exit.
  if [ "$QUIET_LOAD" = false ]; then
    display_and_log "INFO" "Loading kernel via bhyveload for installation..."
    $BHYVELOAD -m "$MEMORY" -d "$DATA_PATH" -c stdio "$VMNAME"
  else
    log "Loading kernel via bhyveload (quiet mode)..."
    # When quiet, we don't want any output, just load the kernel from disk.
    $BHYVELOAD -m "$MEMORY" -d "$DATA_PATH" "$VMNAME" > /dev/null 2>&1
  fi

  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    log_to_global_file "ERROR" "bhyveload for $VMNAME failed with exit code $exit_code. Data path: $DATA_PATH"
    display_and_log "ERROR" "bhyveload failed with exit code $exit_code. Cannot proceed."
    $BHYVECTL --vm="$VMNAME" --destroy > /dev/null 2>&1
    return 1
  fi
  log "bhyveload completed successfully."
  return 0
}




# === Helper function to format bytes into human-readable format ===
format_bytes() {
    local bytes=$1
    if (( bytes < 1024 )); then
        echo "${bytes}B"
    elif (( bytes < 1024 * 1024 )); then
        printf "%.2fK" $(echo "$bytes / 1024" | bc -l)
    elif (( bytes < 1024 * 1024 * 1024 )); then
        printf "%.2fM" $(echo "$bytes / (1024 * 1024)" | bc -l)
    else
        printf "%.2fG" $(echo "$bytes / (1024 * 1024 * 1024)" | bc -l)
    fi
}

# === Helper function to format etime into a more readable format ===
format_etime() {
    local etime=$1
    local days=0
    local hours=0
    local mins=0
    local secs=0

    if [[ $etime == *-* ]]; then
        days=$(echo $etime | cut -d- -f1)
        etime=$(echo $etime | cut -d- -f2)
    fi

    local parts=$(echo $etime | tr ':' ' ')
    read -ra time_parts <<< "$parts"

    if [ ${#time_parts[@]} -eq 3 ]; then
        hours=${time_parts[0]}
        mins=${time_parts[1]}
        secs=${time_parts[2]}
    elif [ ${#time_parts[@]} -eq 2 ]; then
        mins=${time_parts[0]}
        secs=${time_parts[1]}
    else
        secs=${time_parts[0]}
    fi

    local formatted_time=""
    if [ "$days" -gt 0 ]; then
        formatted_time="${days}d"
    fi
    printf -v rhours "%02d" "$((10#$hours))"
    printf -v rmins "%02d" "$((10#$mins))"
    printf -v rsecs "%02d" "$((10#$secs))"
    formatted_time="${formatted_time}${rhours}:${rmins}:${rsecs}"
    echo "$formatted_time"
}


# === Function to load main configuration ===
load_config() {
  if [ -f "$MAIN_CONFIG_FILE" ]; then
      # shellcheck disable=SC1090
    . "$MAIN_CONFIG_FILE"
  fi
  # Set default log file if not set in config
  GLOBAL_LOG_FILE="${GLOBAL_LOG_FILE:-\/var\/log\/bhyve-cli.log}"
  VM_CONFIG_BASE_DIR="${VM_CONFIG_BASE_DIR:-\$CONFIG_DIR\/vm.d}" # Ensure default if not in config
}

# === Function to check if the script has been initialized ===
check_initialization() {
  if [ "$1" != "init" ] && [ ! -f "$MAIN_CONFIG_FILE" ]; then
    echo_message "\n[ERROR] bhyve-cli has not been initialized."
    echo_message "Please run the command '$(basename "$0") init' to generate the required configuration files."
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
