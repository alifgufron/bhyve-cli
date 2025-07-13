#!/usr/local/bin/bash

# === Ensure script is run with Bash ===
if [ -z "$BASH_VERSION" ]; then
  echo_message "[ERROR] This script requires Bash to run. Please execute with 'bash <script_name>' or ensure your shell is Bash."
  exit 1
fi

# === Global Variables ===
CONFIG_DIR="/usr/local/etc/bhyve-cli"
MAIN_CONFIG_FILE="$CONFIG_DIR/bhyve-cli.conf"
VM_CONFIG_BASE_DIR="$CONFIG_DIR/vm.d"
SWITCH_CONFIG_FILE="$CONFIG_DIR/switch.conf"
VERSION="1.1.0"

# These will be loaded from the main config file
ISO_DIR=""
UEFI_FIRMWARE_PATH=""
GLOBAL_LOG_FILE=""

# === Bhyve Binaries Paths ===
BHYVE="/usr/sbin/bhyve"
BHYVECTL="/usr/sbin/bhyvectl"
BHYVELOAD="/usr/sbin/bhyveload"

# === Log Function with Timestamp ===
log() {
  local TIMESTAMP_MESSAGE="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
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
  local TIMESTAMP_MESSAGE="[$(date '+%Y-%m-%d %H:%M:%S')] [$LEVEL] $MESSAGE"
  echo "$MESSAGE" >&2 # Display to console without timestamp or INFO prefix
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

# === Prerequisite Checks ===
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    display_and_log "ERROR" "This script must be run with superuser (root) privileges."
    exit 1
  fi
}

check_kld() {
  if ! kldstat -q -m "$1"; then
    display_and_log "ERROR" "Kernel module '$1.ko' is not loaded. Please run 'kldload $1'."
    exit 1
  fi
}

# === Helper Functions ===
ensure_nmdm_device_nodes() {
  local CONSOLE_DEVICE="$1"
  if [ ! -e "/dev/${CONSOLE_DEVICE}A" ]; then
    log "Creating nmdm device node /dev/${CONSOLE_DEVICE}A"
    mknod "/dev/${CONSOLE_DEVICE}A" c 106 0 || { display_and_log "ERROR" "Failed to create /dev/${CONSOLE_DEVICE}A"; exit 1; }
    chmod 660 "/dev/${CONSOLE_DEVICE}A"
  fi
  if [ ! -e "/dev/${CONSOLE_DEVICE}B" ]; then
    log "Creating nmdm device node /dev/${CONSOLE_DEVICE}B"
    mknod "/dev/${CONSOLE_DEVICE}B" c 106 1 || { display_and_log "ERROR" "Failed to create /dev/${CONSOLE_DEVICE}B"; exit 1; }
    chmod 660 "/dev/${CONSOLE_DEVICE}B"
  fi
}

run_bhyveload() {
  local DATA_PATH="$1"

  display_and_log "INFO" "Loading kernel via bhyveload..."
  $BHYVELOAD -m "$MEMORY" -d "$DATA_PATH" -c stdio "$VMNAME"
  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    display_and_log "ERROR" "bhyveload failed with exit code $exit_code. Cannot proceed."
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

  # Temporarily load VM config to get network details
  local ORIGINAL_VMNAME="$VMNAME"
  local ORIGINAL_CPUS="$CPUS"
  local ORIGINAL_MEMORY="$MEMORY"
  local ORIGINAL_TAP_0="$TAP_0"
  local ORIGINAL_MAC_0="$MAC_0"
  local ORIGINAL_BRIDGE_0="$BRIDGE_0"
  local ORIGINAL_DISK="$DISK"
  local ORIGINAL_DISKSIZE="$DISKSIZE"
  local ORIGINAL_CONSOLE="$CONSOLE"
  local ORIGINAL_LOG="$LOG_FILE"
  local ORIGINAL_AUTOSTART="$AUTOSTART"
  local ORIGINAL_BOOTLOADER_TYPE="$BOOTLOADER_TYPE"

  . "$CONF_FILE_CLEANUP"
  local LOG_FILE_CLEANUP="$VM_DIR_CLEANUP/vm.log" # Set LOG_FILE for this function's scope

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
      ifconfig "$CURRENT_BRIDGE" deletem "$CURRENT_TAP"
      if [ $? -ne 0 ]; then
        log "WARNING: Failed to remove TAP '$CURRENT_TAP' from bridge '$CURRENT_BRIDGE'."
      fi
    fi

    if ifconfig "$CURRENT_TAP" > /dev/null 2>&1; then
      log "Destroying TAP interface '$CURRENT_TAP'..."
      ifconfig "$CURRENT_TAP" destroy
      if [ $? -ne 0 ]; then
        log "WARNING: Failed to destroy TAP interface '$CURRENT_TAP'."
      fi
    fi
    NIC_IDX=$((NIC_IDX + 1))
  done
  log "Network interface cleanup for '$VMNAME_CLEANUP' complete."
  log "Exiting cleanup_vm_network_interfaces function for VM: $VMNAME_CLEANUP"

  # Restore original VM config variables
  VMNAME="$ORIGINAL_VMNAME"
  CPUS="$ORIGINAL_CPUS"
  MEMORY="$ORIGINAL_MEMORY"
  TAP_0="$ORIGINAL_TAP_0"
  MAC_0="$ORIGINAL_MAC_0"
  BRIDGE_0="$ORIGINAL_BRIDGE_0"
  DISK="$ORIGINAL_DISK"
  DISKSIZE="$ORIGINAL_DISKSIZE"
  CONSOLE="$ORIGINAL_CONSOLE"
  LOG_FILE="$ORIGINAL_LOG"
  AUTOSTART="$ORIGINAL_AUTOSTART"
  BOOTLOADER_TYPE="$ORIGINAL_BOOTLOADER_TYPE"
}



# === Function to load main configuration ===
load_config() {
  if [ -f "$MAIN_CONFIG_FILE" ]; then
    . "$MAIN_CONFIG_FILE"
    # Set default log file if not set in config
    GLOBAL_LOG_FILE="${GLOBAL_LOG_FILE:-/var/log/bhyve-cli.log}"
  fi
}

# === Function to check if the script has been initialized ===
check_initialization() {
  if [ "$1" != "init" ] && [ ! -f "$MAIN_CONFIG_FILE" ]; then
    echo_message "
[ERROR] bhyve-cli has not been initialized."
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
  . "$CONF_FILE"
  LOG_FILE="$VM_DIR/vm.log" # Set LOG_FILE after loading config
  BOOTLOADER_TYPE="${BOOTLOADER_TYPE:-bhyveload}" # Default to bhyveload if not set
}

# === Main Usage Function ===
main_usage() {
  echo_message "Usage: $0 <command> [options/arguments]"
  echo_message " "
  echo_message "Available Commands:"
  echo_message "  init          - Initialize bhyve-cli configuration."
  echo_message "  create        - Create a new virtual machine."
  echo_message "  delete        - Delete an existing virtual machine."
  echo_message "  install       - Install an operating system on a VM."
  echo_message "  start         - Start a virtual machine."
  echo_message "  stop          - Stop a running virtual machine."
  echo_message "  console       - Access the console of a VM."
  echo_message "  logs          - Display real-time logs for a VM."
  echo_message "  autostart     - Enable or disable VM autostart on boot."
  echo_message "  modify        - Modify VM configuration (CPU, RAM, network, etc.)."
  echo_message "  clone         - Create a clone of an existing VM."
  echo_message "  info          - Display detailed information about a VM."
  echo_message "  resize-disk   - Resize a VM's disk image."
  echo_message "  export        - Export a VM to an archive file."
  echo_message "  import        - Import a VM from an archive file."
  echo_message "  iso           - Manage ISO images (list and download)."
  echo_message "  status        - Show the status of all virtual machines."
  echo_message "  restart       - Restart a virtual machine."
  echo_message "  switch        - Manage network bridges and physical interfaces."
  echo_message " "
  echo_message "For detailed usage of each command, use: $0 <command> --help"
}

# === Usage Functions for All Commands ===
# === Usage function for init ===
cmd_init_usage() {
  echo_message "Usage: $0 init"
  echo_message "\nDescription:"
  echo_message "  Initializes the bhyve-cli configuration directory and files."
}

# === Usage function for switch init ===
cmd_switch_init_usage() {
  echo_message "Usage: $0 switch init"
  echo_message "\nDescription:"
  echo_message "  Re-initializes all saved switch configurations from the switch config file."
  echo_message "  This is useful for restoring network configuration after a host reboot."
}

# === Usage function for switch add ===
cmd_switch_add_usage() {
  echo_message "Usage: $0 switch add --name <bridge_name> --interface <physical_interface> [--vlan <vlan_tag>]"
  echo_message "\nOptions:"
  echo_message "  --name <bridge_name>         - Name of the bridge or vSwitch."
  echo_message "  --interface <physical_interface> - Parent physical network interface (e.g., em0, igb1)."
  echo_message "  --vlan <vlan_tag>            - Optional. VLAN ID if the parent interface is in trunk mode. A VLAN interface (e.g., vlan100) will be created on top of the physical interface and tagged to the bridge."
}


# === Usage function for switch destroy ===
cmd_switch_destroy_usage() {
  echo_message "Usage: $0 switch destroy <bridge_name>"
  echo_message "\nArguments:"
  echo_message "  <bridge_name> - The name of the bridge to destroy."
}

# === Usage function for switch delete ===
cmd_switch_delete_usage() {
  echo_message "\nUsage: $0 switch delete --member <interface> --from <bridge_name>"
  echo_message "\nOptions:"
  echo_message "  --member <interface> \t- The specific member interface to remove (e.g., tap0, vlan100)."
  echo_message "  --from <bridge_name> \t- The bridge from which to remove the member."
}

# === Usage function for switch ===
cmd_switch_usage() {
  echo_message "Usage: $0 switch [subcommand] [Option] [Arguments]"
  echo_message "\nSubcommands:"
  echo_message "  init        - Re-initialize all saved switch configurations."
  echo_message "  add         - Create a bridge and add a physical interface"

  echo_message "  list        - List all bridge interfaces and their members"
  echo_message "  destroy     - Destroy a bridge and all its members"
  echo_message "  delete      - Remove a specific member from a bridge"
}

# === Usage function for create ===
cmd_create_usage() {
  echo_message "Usage: $0 create --name <vmname> --disk-size <disksize in GB> --switch <bridge_name> [--bootloader <type>]"
  echo_message "\nOptions:"
  echo_message "  --name <vmname>              - Name of the virtual machine."
  echo_message "  --disk-size <size in GB>     - Size of the virtual disk in GB."
  echo_message "  --switch <bridge_name>       - Name of the network bridge to connect the VM to."
  echo_message "  --bootloader <type>          - Optional. Type of bootloader (bhyveload, uefi). Default: bhyveload."
  echo_message "\nExample:"
  echo_message "  $0 create --name vm-bsd --disk-size 40 --switch bridge100"
  echo_message "  $0 create --name vm-uefi --disk-size 60 --switch bridge101 --bootloader uefi"
}

# === Usage function for delete ===
cmd_delete_usage() {
  echo_message "Usage: $0 delete <vmname>"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine to permanently delete."
}

# === Usage function for install ===
cmd_install_usage() {
  echo_message "Usage: $0 install <vmname> [--bootloader <type>]"
  echo_message "\nOptions:"
  echo_message "  --bootloader <type>          - Optional. Override the bootloader type for this installation (bhyveload, uefi)."
}

# === Usage function for start ===
cmd_start_usage() {
  echo_message "Usage: $0 start <vmname>"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine to start."
}

# === Usage function for stop ===
cmd_stop_usage() {
  echo_message "Usage: $0 stop <vmname> [--graceful]"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine to stop."
  echo_message "\nOptions:"
  echo_message "  --graceful  - Attempt a graceful shutdown (ACPI poweroff) before forceful termination."
}

# === Usage function for console ===
cmd_console_usage() {
  echo_message "Usage: $0 console <vmname>"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine to connect to."
}

# === Usage function for logs ===
cmd_logs_usage() {
  echo_message "Usage: $0 logs <vmname>"
  echo_message "
Arguments:"
  echo_message "  <vmname>    - The name of the virtual machine whose logs you want to view."
}

# === Usage function for autostart ===
cmd_autostart_usage() {
  echo_message "Usage: $0 autostart <vmname> <enable|disable>"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine."
  echo_message "  <action>    - 'enable' to set the VM to autostart on boot, or 'disable' to prevent it."
}

# === Usage function for info ===
cmd_info_usage() {
  echo_message "Usage: $0 info <vmname>"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine to display information about."
}

# === Usage function for modify ===
cmd_modify_usage() {
  echo_message "Usage: $0 modify <vmname> [--cpu <num>] [--ram <size>] [--nic <index> --tap <tap_name> --mac <mac_address> --bridge <bridge_name>]"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine to modify."
  echo_message "\nOptions:"
  echo_message "  --cpu <num>                  - Set the number of virtual CPUs for the VM."
  echo_message "  --ram <size>                 - Set the amount of RAM for the VM (e.g., 2G, 4096M)."
  echo_message "  --nic <index>                - Specify the index of the network interface to modify (e.g., 0 for TAP_0). Required when using --tap, --mac, or --bridge."
  echo_message "  --tap <tap_name>             - Assign a new TAP device name to the specified NIC."
  echo_message "  --mac <mac_address>          - Assign a new MAC address to the specified NIC."
  echo_message "  --bridge <bridge_name>       - Connect the specified NIC to a different bridge."
  echo_message "\nExample:"
  echo_message "  $0 modify myvm --cpu 4 --ram 4096M"
  echo_message "  $0 modify myvm --nic 0 --tap tap1 --bridge bridge1"
}

# === Usage function for clone ===
cmd_clone_usage() {
  echo_message "Usage: $0 clone <source_vmname> <new_vmname>"
  echo_message "\nArguments:"
  echo_message "  <source_vmname>    - The name of the existing virtual machine to clone."
  echo_message "  <new_vmname>       - The name for the new cloned virtual machine."
  echo_message "\nExample:"
  echo_message "  $0 clone myvm newvm"
}

# === Usage function for resize-disk ===
cmd_resize_disk_usage() {
  echo_message "Usage: $0 resize-disk <vmname> <new_size_in_GB>"
  echo_message "\nArguments:"
  echo_message "  <vmname>         - The name of the virtual machine whose disk you want to resize."
  echo_message "  <new_size_in_GB> - The new size of the virtual disk in GB. Must be larger than the current size."
  echo_message "\nExample:"
  echo_message "  $0 resize-disk myvm 60"
}

# === Usage function for export ===
cmd_export_usage() {
  echo_message "Usage: $0 export <vmname> <destination_path>"
  echo_message "
Arguments:"
  echo_message "  <vmname>           - The name of the virtual machine to export."
  echo_message "  <destination_path> - The full path including the filename for the exported archive (e.g., /tmp/myvm_backup.tar.gz)."
  echo_message "
Example:"
  echo_message "  $0 export myvm /tmp/myvm_backup.tar.gz"
}

# === Usage function for import ===
cmd_import_usage() {
  echo_message "Usage: $0 import <path_to_vm_archive>"
  echo_message "\nArguments:"
  echo_message "  <path_to_vm_archive> - The full path to the VM archive file to import (e.g., /tmp/myvm_backup.tar.gz)."
  echo_message "\nExample:"
  echo_message "  $0 import /tmp/myvm_backup.tar.gz"
}

# === Usage function for restart ===
cmd_restart_usage() {
  echo_message "Usage: $0 restart <vmname>"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine to restart."
}

# === Usage function for network ===
cmd_network_usage() {
  echo_message "Usage: $0 network [subcommand] [arguments]"
  echo_message "\nSubcommands:"
  echo_message "  add    - Add a network interface to a VM."
  echo_message "  remove - Remove a network interface from a VM."
  echo_message "\nFor detailed usage of each subcommand, use: $0 network <subcommand> --help"
}

# === Usage function for ISO ===
cmd_iso_usage() {
  echo_message "Usage: $0 iso [list | <URL>]"
  echo_message "\nSubcommands:"
  echo_message "  list         - List all ISO images in $ISO_DIR."
  echo_message "  <URL>        - Download an ISO image from the specified URL to $ISO_DIR."
  echo_message "\nExample:"
  echo_message "  $0 iso list"
  echo_message "  $0 iso https://example.com/freebsd.iso"
}

# === Subcommand: iso ===
cmd_iso() {
  if [ -z "$1" ]; then
    cmd_iso_usage
    exit 1
  fi

  local SUBCOMMAND="$1"
  shift

  case "$SUBCOMMAND" in
    list)
      log "Listing ISO files in $ISO_DIR..."
      if [ ! -d "$ISO_DIR" ]; then
        display_and_log "INFO" "ISO directory '$ISO_DIR' not found. Creating it."
        mkdir -p "$ISO_DIR"
      fi
      ISO_LIST=($(find "$ISO_DIR" -type f -name "*.iso" 2>/dev/null))
      if [ ${#ISO_LIST[@]} -eq 0 ]; then
        display_and_log "INFO" "No ISO files found in $ISO_DIR."
      else
        echo_message "\nAvailable ISOs in $ISO_DIR:"
        local count=1
        for iso in "${ISO_LIST[@]}"; do
          local iso_filename=$(basename "$iso")
          local iso_size_bytes=$(stat -f %z "$iso")
          local iso_size_gb=$(echo "scale=2; $iso_size_bytes / (1024 * 1024 * 1024)" | bc)
          echo_message "$((count++)). $iso_filename (${iso_size_gb}GB)"
        done
      fi
      ;;
    http://*|https://*)
      local ISO_URL="$SUBCOMMAND"
      local ISO_FILE="$(basename "$ISO_URL")"
      local ISO_PATH="$ISO_DIR/$ISO_FILE"

      mkdir -p "$ISO_DIR" || { display_and_log "ERROR" "Failed to create ISO directory '$ISO_DIR'."; exit 1; }

      log "Downloading ISO from $ISO_URL to $ISO_PATH..."
      display_and_log "INFO" "Downloading $ISO_FILE... This may take a while."
      fetch "$ISO_URL" -o "$ISO_PATH" || {
        display_and_log "ERROR" "Failed to download ISO from $ISO_URL."
        exit 1
      }
      display_and_log "INFO" "ISO downloaded successfully to $ISO_PATH."
      ;;
    *)
      display_and_log "ERROR" "Invalid subcommand or URL for 'iso': $SUBCOMMAND"
      cmd_iso_usage
      exit 1
      ;;
  esac
}

# === Usage function for network add ===
cmd_network_add_usage() {
  echo_message "Usage: $0 network add --vm <vmname> --switch <bridge_name> [--mac <mac_address>]"
  echo_message "\nOptions:"
  echo_message "  --vm <vmname>                - Name of the virtual machine to add the network interface to."
  echo_message "  --switch <bridge_name>       - Name of the network bridge to connect the new interface to."
  echo_message "  --mac <mac_address>          - Optional. Specific MAC address for the new interface. If omitted, a random one is generated."
  echo_message "\nExample:"
  echo_message "  $0 network add --vm myvm --switch bridge1"
  echo_message "  $0 network add --vm myvm --switch bridge2 --mac 58:9c:fc:00:00:01"
}

# === Usage function for network remove ===
cmd_network_remove_usage() {
  echo_message "Usage: $0 network remove <vmname> <tap_name>"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine to remove the network interface from."
  echo_message "  <tap_name>  - The name of the TAP interface to remove (e.g., tap0, tap1)."
  echo_message "\nExample:"
  echo_message "  $0 network remove myvm tap0"
}


# === Subcommand: switch ===
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

  MEMBER_IF="$PHYS_IF"
  if [ -n "$VLAN_TAG" ]; then
    VLAN_IF="vlan${VLAN_TAG}"
    if ! ifconfig "$VLAN_IF" > /dev/null 2>&1; then
      log_to_global_file "INFO" "Creating VLAN interface '$VLAN_IF'..."
      ifconfig "$VLAN_IF" create
      if [ $? -ne 0 ]; then
        display_and_log "ERROR" "Failed to create VLAN interface '$VLAN_IF'."
        exit 1
      fi
      log_to_global_file "INFO" "Configuring '$VLAN_IF' with tag '$VLAN_TAG' on top of '$PHYS_IF'..."
      ifconfig "$VLAN_IF" vlan "$VLAN_TAG" vlandev "$PHYS_IF"
      if [ $? -ne 0 ]; then
        display_and_log "ERROR" "Failed to configure VLAN interface '$VLAN_IF'."
        exit 1
      fi
      log_to_global_file "INFO" "VLAN interface '$VLAN_IF' successfully configured."
      display_and_log "INFO" "Successfully created interface $VLAN_IF with VLAN $VLAN_TAG and vlandev to $PHYS_IF."
    else
      log_to_global_file "INFO" "VLAN interface '$VLAN_IF' already exists."
    fi
    MEMBER_IF="$VLAN_IF"
  fi

  log_to_global_file "INFO" "Checking bridge '$BRIDGE_NAME'..."
  if ! ifconfig "$BRIDGE_NAME" > /dev/null 2>&1; then
    log_to_global_file "INFO" "Bridge interface '$BRIDGE_NAME' does not exist. Creating..."
    ifconfig bridge create name "$BRIDGE_NAME"
    if [ $? -ne 0 ]; then
      display_and_log "ERROR" "Failed to create bridge '$BRIDGE_NAME'."
      exit 1
    fi
    log_to_global_file "INFO" "Bridge interface '$BRIDGE_NAME' successfully created."
  else
    log_to_global_file "INFO" "Bridge interface '$BRIDGE_NAME' already exists."
  fi

  if ! ifconfig "$BRIDGE_NAME" | grep -qw "$MEMBER_IF"; then
    log_to_global_file "INFO" "Adding '$MEMBER_IF' to bridge '$BRIDGE_NAME'..."
    ifconfig "$BRIDGE_NAME" addm "$MEMBER_IF"
    if [ $? -ne 0 ]; then
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
    echo_message "
WARNING: Bridge '$BRIDGE_NAME' has active members:"
    for MEMBER in $MEMBERS; do
      echo_message "  - $MEMBER"
    done
    echo_message "
Destroying this bridge will also remove all its members and their configurations."
    read -rp "Are you sure you want to destroy bridge '$BRIDGE_NAME' and all its members? (y/n): " CONFIRM_DESTROY
    if ! [[ "$CONFIRM_DESTROY" =~ ^[Yy]$ ]]; then
      echo_message "Bridge destruction cancelled."
      log_to_global_file "INFO" "User cancelled bridge destruction."
      exit 0
    fi
  else
    echo_message "
Bridge '$BRIDGE_NAME' is empty."
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
      ifconfig "$BRIDGE_NAME" deletem "$MEMBER"
      if [ $? -ne 0 ]; then
        echo_message "[WARNING] Failed to remove member '$MEMBER' from bridge '$BRIDGE_NAME'."
        log_to_global_file "WARNING" "Command 'ifconfig \"$BRIDGE_NAME\" deletem \"$MEMBER\"' failed."
      else
        echo_message "  - Member '$MEMBER' removed."
        log_to_global_file "INFO" "Member '$MEMBER' successfully removed from bridge '$BRIDGE_NAME'."
      fi

      if [[ "$MEMBER" =~ ^vlan[0-9]+$ ]]; then
        log_to_global_file "INFO" "Executing: ifconfig \"$MEMBER\" destroy"
        ifconfig "$MEMBER" destroy
        if [ $? -ne 0 ]; then
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
  ifconfig "$BRIDGE_NAME" destroy
  if [ $? -ne 0 ]; then
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
  ifconfig "$BRIDGE_NAME" deletem "$MEMBER_IF"
  if [ $? -ne 0 ]; then
    display_and_log "ERROR" "Failed to remove '$MEMBER_IF' from bridge '$BRIDGE_NAME'."
    exit 1
  fi
  display_and_log "INFO" "Interface '$MEMBER_IF' successfully removed from bridge '$BRIDGE_NAME'."

  # Check if the removed member was a VLAN interface and destroy it
  if [[ "$MEMBER_IF" =~ ^vlan[0-9]+$ ]]; then
    log "Destroying VLAN interface '$MEMBER_IF'..."
    ifconfig "$MEMBER_IF" destroy
    if [ $? -ne 0 ]; then
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
      ifconfig "$BRIDGE_NAME" destroy
      if [ $? -ne 0 ]; then
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







# === Subcommand: create ===
cmd_create() {
  local VMNAME=""
  local DISKSIZE=""
  local VM_BRIDGE=""
  local BOOTLOADER_TYPE="bhyveload" # Default bootloader

  # Parse named arguments
  while (( "$#" )); do
    case "$1" in
      --name)
        shift
        VMNAME="$1"
        ;;
      --disk-size)
        shift
        DISKSIZE="$1"
        ;;
      --switch)
        shift
        VM_BRIDGE="$1"
        ;;
      --bootloader)
        shift
        BOOTLOADER_TYPE="$1"
        ;;
      *)
        display_and_log "ERROR" "Invalid option: $1"
        cmd_create_usage
        exit 1
        ;;
    esac
    shift
  done

  # Validate required arguments
  if [ -z "$VMNAME" ] || [ -z "$DISKSIZE" ] || [ -z "$VM_BRIDGE" ]; then
    cmd_create_usage
    exit 1
  fi

  VM_DIR="$VM_CONFIG_BASE_DIR/$VMNAME"
  CONF="$VM_DIR/vm.conf"

  display_and_log "INFO" "Creating VM directory: $VM_DIR"
  mkdir -p "$VM_DIR" || { display_and_log "ERROR" "Failed to create VM directory '$VM_DIR'."; exit 1; }
  LOG_FILE="$VM_DIR/vm.log" # Set LOG_FILE for create command

  display_and_log "INFO" "Creating VM '$VMNAME' with disk size ${DISKSIZE}GB and connecting to bridge '$VM_BRIDGE'."

  # === Check and create bridge interface if it doesn't exist ===
  if ! ifconfig "$VM_BRIDGE" > /dev/null 2>&1; then
    display_and_log "INFO" "Bridge interface '$VM_BRIDGE' does not exist. Creating..."
    ifconfig bridge create name "$VM_BRIDGE" || { display_and_log "ERROR" "Failed to create bridge '$VM_BRIDGE'."; exit 1; }
    display_and_log "INFO" "Bridge interface '$VM_BRIDGE' successfully created."
  else
    display_and_log "INFO" "Bridge interface '$VM_BRIDGE' already exists."
  fi

  # === Create disk image ===
  display_and_log "INFO" "Creating disk image: $VM_DIR/disk.img with size ${DISKSIZE}GB..."
  truncate -s "${DISKSIZE}G" "$VM_DIR/disk.img" || { display_and_log "ERROR" "Failed to create disk image."; exit 1; }
  display_and_log "INFO" "Disk ${DISKSIZE}GB created: $VM_DIR/disk.img"

  # === Generate unique UUID ===
  UUID=$(uuidgen)
  display_and_log "INFO" "Generated unique UUID: $UUID"

  # === Generate unique MAC address (static prefix, random suffix) ===
  MAC_0="58:9c:fc$(jot -r -w ":%02x" -s "" 3 0 255)"
  display_and_log "INFO" "Generated MAC address for NIC0: $MAC_0"

  # === Safely detect next available TAP & create TAP ===
  NEXT_TAP_NUM=0
  while ifconfig | grep -q "^tap${NEXT_TAP_NUM}:"; do
    NEXT_TAP_NUM=$((NEXT_TAP_NUM + 1))
  done
  TAP_0="tap${NEXT_TAP_NUM}"
  display_and_log "INFO" "Assigning TAP interface: $TAP_0"

  # === Create TAP interface
  display_and_log "INFO" "Creating TAP interface '$TAP_0'..."
  ifconfig "$TAP_0" create || { display_and_log "ERROR" "Failed to create TAP interface '$TAP_0'."; exit 1; }
  display_and_log "INFO" "TAP interface '$TAP_0' successfully created."

  # === Add TAP description according to VM name
  display_and_log "INFO" "Setting TAP description for '$TAP_0'..."
  ifconfig "$TAP_0" description "vmnet/${VMNAME}/0/${VM_BRIDGE}"
  display_and_log "INFO" "TAP description '$TAP_0' set: VM: vmnet/${VMNAME}/0/${VM_BRIDGE}"

  # === Activate TAP
  display_and_log "INFO" "Activating TAP interface '$TAP_0'..."
  ifconfig "$TAP_0" up
  display_and_log "INFO" "TAP '$TAP_0' activated."

  # === Add TAP to bridge
  display_and_log "INFO" "Adding TAP '$TAP_0' to bridge '$VM_BRIDGE'..."
  ifconfig "$VM_BRIDGE" addm "$TAP_0" || { display_and_log "ERROR" "Failed to add TAP '$TAP_0' to bridge '$VM_BRIDGE'."; exit 1; }
  display_and_log "INFO" "TAP '$TAP_0' added to bridge '$VM_BRIDGE'."

  # === Generate unique console name ===
  CONSOLE="nmdm-${VMNAME}.1"
  display_and_log "INFO" "Console device assigned: $CONSOLE"

  # === Create configuration file ===
  display_and_log "INFO" "Creating VM configuration file: $CONF"
  cat > "$CONF" <<EOF
VMNAME=$VMNAME
UUID=$UUID
CPUS=2
MEMORY=2048M
TAP_0=$TAP_0
MAC_0=$MAC_0
BRIDGE_0=$VM_BRIDGE
DISK=disk.img
DISKSIZE=$DISKSIZE
CONSOLE=$CONSOLE
LOG=$LOG_FILE
AUTOSTART=no
BOOTLOADER_TYPE=$BOOTLOADER_TYPE
EOF

  display_and_log "INFO" "Configuration file created: $CONF"
  display_and_log "INFO" "VM '$VMNAME' successfully created."
  echo_message "\nPlease continue by running: $0 install $VMNAME"
}

# === Subcommand: init ===
cmd_init() {
    GLOBAL_LOG_FILE="/var/log/bhyve-cli.log"
    touch "$GLOBAL_LOG_FILE" || { echo_message "[ERROR] Could not create log file at $GLOBAL_LOG_FILE. Please check permissions."; exit 1; }

    if [ -f "$MAIN_CONFIG_FILE" ]; then
        read -rp "Configuration file already exists. Overwrite? (y/n): " choice
        if [[ "$choice" != "y" ]]; then
            exit 0
        fi
    fi

    display_and_log "INFO" "Initializing bhyve-cli..."

    mkdir -p "$CONFIG_DIR"
    mkdir -p "$VM_CONFIG_BASE_DIR"

    read -rp "Enter the full path for storing ISO images [/var/bhyve/iso]: " iso_path
    ISO_DIR=${iso_path:-/var/bhyve/iso}
    mkdir -p "$ISO_DIR"
    display_and_log "INFO" "ISO directory set to: $ISO_DIR"

    UEFI_FIRMWARE_PATH="$CONFIG_DIR/firmware"
    mkdir -p "$UEFI_FIRMWARE_PATH"
    display_and_log "INFO" "UEFI firmware path set to: $UEFI_FIRMWARE_PATH"

    echo "ISO_DIR=\"$ISO_DIR\"" > "$MAIN_CONFIG_FILE"
    echo "UEFI_FIRMWARE_PATH=\"$UEFI_FIRMWARE_PATH\"" >> "$MAIN_CONFIG_FILE"
    echo "GLOBAL_LOG_FILE=\"$GLOBAL_LOG_FILE\"" >> "$MAIN_CONFIG_FILE"

    display_and_log "INFO" "bhyve-cli initialized."
    display_and_log "INFO" "Configuration file created at: $MAIN_CONFIG_FILE"
    echo_message "bhyve-cli initialized successfully."
    echo_message "Configuration file created at: $MAIN_CONFIG_FILE"
}

# === Subcommand: delete ===
cmd_delete() {
  log "Entering cmd_delete function for VM: $1"
  if [ -z "$1" ]; then
    cmd_delete_usage
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  log "Deleting VM '$VMNAME'..."

  # === Stop bhyve if still running ===
  if ps -ax | grep -v grep | grep -c "[b]hyve .* -s .* $VMNAME$" > /dev/null; then
    log "VM is still running. Stopping bhyve process..."
    pkill -f "bhyve.*$VMNAME"
    sleep 1
  fi

  # === Destroy from kernel memory ===
  if $BHYVECTL --vm="$VMNAME" --destroy > /dev/null 2>&1; then
    log "VM destroyed from kernel memory."
  fi

  cleanup_vm_network_interfaces "$VMNAME"

  # === Remove console device files ===
  if [ -e "/dev/${CONSOLE}A" ]; then
    log "Removing console device /dev/${CONSOLE}A"
    rm -f "/dev/${CONSOLE}A"
  fi
  if [ -e "/dev/${CONSOLE}B" ]; then
    log "Removing console device /dev/${CONSOLE}B"
    rm -f "/dev/${CONSOLE}B"
  fi

  # === Delete VM directory ===
  log "Deleting VM directory: $VM_DIR"
  rm -rf "$VM_DIR"
  unset LOG_FILE # Unset LOG_FILE after directory is removed

  # Remove vm.pid file if it exists
  if [ -f "$VM_DIR/vm.pid" ]; then
    rm "$VM_DIR/vm.pid"
    log "Removed vm.pid file."
  fi

  display_and_log "INFO" "VM '$VMNAME' successfully deleted."
  log "Exiting cmd_delete function for VM: $VMNAME"
}

# === Subcommand: restart ===
cmd_restart() {
  log "Entering cmd_restart function for VM: $1"
  if [ -z "$1" ]; then
    cmd_restart_usage
    exit 1
  fi

  local VMNAME="$1"

  display_and_log "INFO" "Restarting VM '$VMNAME'..."
  cmd_stop "$VMNAME" --graceful
  # Give it a moment to fully stop and clean up
  sleep 2
  cmd_start "$VMNAME"
  display_and_log "INFO" "VM '$VMNAME' restart initiated."
  log "Exiting cmd_restart function for VM: $VMNAME"
}

# === Subcommand: install ===
cmd_install() {
  log "Entering cmd_install function for VM: $1"
  local VMNAME=""
  local INSTALL_BOOTLOADER_TYPE="" # Bootloader type for this installation only

  # Parse arguments
  VMNAME="$1"
  shift

  while (( "$#" )); do
    case "$1" in
      --bootloader)
        shift
        INSTALL_BOOTLOADER_TYPE="$1"
        ;;
      *)
        display_and_log "ERROR" "Invalid option for install: $1"
        cmd_install_usage
        exit 1
        ;;
    esac
    shift
  done

  if [ -z "$VMNAME" ]; then
    cmd_install_usage
    exit 1
  fi

  load_vm_config "$VMNAME"

  # Override BOOTLOADER_TYPE if specified for installation
  if [ -n "$INSTALL_BOOTLOADER_TYPE" ]; then
    BOOTLOADER_TYPE="$INSTALL_BOOTLOADER_TYPE"
    log "Overriding bootloader for installation to: $BOOTLOADER_TYPE"
  fi

  ensure_nmdm_device_nodes "$CONSOLE"

  log "Starting VM '$VMNAME' installation..."

  # === Stop bhyve if still active ===
  if ps -ax | grep -v grep | grep -c "[b]hyve .* -s .* $VMNAME$" > /dev/null; then
    log "VM '$VMNAME' is still running. Stopped..."
    pkill -f "bhyve.*$VMNAME"
    sleep 1
  fi

  # === Destroy if still remaining in kernel ===
  if $BHYVECTL --vm="$VMNAME" --destroy > /dev/null 2>&1; then
    log "VM '$VMNAME' was still in memory. Destroyed."
  fi

  # === Select ISO source ===
  echo_message ""
  echo_message "Select ISO source:"
  echo_message "1. Choose existing ISO"
  echo_message "2. Download ISO from URL"
  read -rp "Choice [1/2]: " CHOICE

  local ISO_PATH=""
  case "$CHOICE" in
    1)
      log "Searching for ISO files in $ISO_DIR..."
      ISO_LIST=($(find "$ISO_DIR" -type f -name "*.iso" 2>/dev/null))
      if [ ${#ISO_LIST[@]} -eq 0 ]; then
        display_and_log "WARNING" "No ISO files found in $ISO_DIR!"
        exit 1
      fi
      echo_message "Available ISOs:"
      select iso in "${ISO_LIST[@]}"; do
        if [ -n "$iso" ]; then
          ISO_PATH="$iso"
          break
        fi
      done
      ;;
    2)
      read -rp "Enter ISO URL: " ISO_URL
      ISO_FILE="$(basename "$ISO_URL")"
      ISO_PATH="$ISO_DIR/$ISO_FILE"
      mkdir -p "$ISO_DIR"
      log "Downloading ISO from $ISO_URL"
      fetch "$ISO_URL" -o "$ISO_PATH" || {
        display_and_log "ERROR" "Failed to download ISO"
        exit 1
      }
      ;;
    *)
      display_and_log "ERROR" "Invalid choice"
      exit 1
      ;;
  esac

  if [ -z "$ISO_PATH" ]; then
    display_and_log "ERROR" "No ISO selected."
    exit 1
  fi

  # === Installation Logic ===
  if [ "$BOOTLOADER_TYPE" = "bhyveload" ]; then
    run_bhyveload "$ISO_PATH" || exit 1

    display_and_log "INFO" "Starting VM with nmdm console for installation..."
    $BHYVE -c $CPUS -m $MEMORY -AHP -s 0,hostbridge -s 3:0,virtio-blk,$VM_DIR/$DISK -s 4:0,ahci-cd,$ISO_PATH -s 5:0,virtio-net,$TAP_0 -l com1,/dev/${CONSOLE}A -s 31,lpc "$VMNAME" >> "$LOG_FILE" 2>&1 &
    VM_PID=$!
    echo "$VM_PID" > "$VM_DIR/vm.pid"
    log "Bhyve VM started in background with PID $VM_PID"

    sleep 2 # Give bhyve a moment to start
    echo_message ""
    echo_message ">>> Entering VM '$VMNAME' installation console (exit with ~.)"
    echo_message ">>> IMPORTANT: After shutting down the VM from within, you MUST type '~.' (tilde then dot) to exit this console and allow the script to continue cleanup."
    cu -l /dev/"${CONSOLE}B"

    log "cu session ended. Initiating cleanup..."

    # Explicitly kill bhyve process associated with this VMNAME
    local VM_PIDS_TO_KILL=$(ps -ax | grep "[b]hyve .* $VMNAME$" | awk '{print $1}')
    if [ -n "$VM_PIDS_TO_KILL" ]; then
        local PIDS_STRING=$(echo "$VM_PIDS_TO_KILL" | tr '
' ' ')
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
        log "No bhyve process found for '$VMNAME' to kill."
    fi

    # Now, destroy from kernel memory (important for bhyveload)
    if $BHYVECTL --vm="$VMNAME" --destroy > /dev/null 2>&1; then
        log "VM '$VMNAME' successfully destroyed from kernel memory."
    else
        log "VM '$VMNAME' was not found in kernel memory (already destroyed or never started)."
    fi

    # Kill any lingering cu or tail -f processes
    log "Attempting to stop associated cu process for /dev/${CONSOLE}B..."
    pkill -f "cu -l /dev/${CONSOLE}B" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        log "cu process for /dev/${CONSOLE}B stopped."
    else
        log "No cu process found or failed to stop for /dev/${CONSOLE}B."
    fi

    log "Attempting to stop associated cu process for /dev/${CONSOLE}A..."
    pkill -f "cu -l /dev/${CONSOLE}A" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        log "cu process for /dev/${CONSOLE}A stopped."
    else
        log "No cu process found or failed to stop for /dev/${CONSOLE}A."
    fi

    log "Attempting to stop associated tail -f process for $LOG_FILE..."
    pkill -f "tail -f $LOG_FILE" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        log "tail -f process for $LOG_FILE stopped."
    else
        log "No tail -f process found or failed to stop for $LOG_FILE."
    fi

    # Check the exit status of the bhyve process
    wait "$VM_PID"
    local BHYVE_EXIT_STATUS=$?

    if [ "$BHYVE_EXIT_STATUS" -eq 3 ] || [ "$BHYVE_EXIT_STATUS" -eq 4 ]; then
        display_and_log "ERROR" "Virtual machine '$VMNAME' installer exited with an error (exit code: $BHYVE_EXIT_STATUS). Check VM logs for details."
        exit 1
    else
        log "Bhyve process $VM_PID exited cleanly (status: $BHYVE_EXIT_STATUS)."
    fi
    display_and_log "INFO" "Installation finished. You can now start the VM with: $0 start $VMNAME"

  else
    # --- uefi/GRUB INSTALL ---
    log "Preparing for non-bhyveload installation..."
    local BHYVE_LOADER_CLI_ARG=""
    case "$BOOTLOADER_TYPE" in
      uefi|bootrom)
        local UEFI_FIRMWARE_FOUND=false
        if [ -f "$UEFI_FIRMWARE_PATH" ]; then
          BHYVE_LOADER_CLI_ARG="-l bootrom,$UEFI_FIRMWARE_PATH"
          log "Using uefi firmware from configured path: $UEFI_FIRMWARE_PATH"
          UEFI_FIRMWARE_FOUND=true
        elif [ -f "/usr/local/share/uefi-firmware/BHYVE_UEFI.fd" ]; then
          BHYVE_LOADER_CLI_ARG="-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd"
          log "Using uefi firmware from default system path: /usr/local/share/uefi-firmware/BHYVE_UEFI.fd"
          UEFI_FIRMWARE_FOUND=true
        fi

        if [ "$UEFI_FIRMWARE_FOUND" = false ]; then
          display_and_log "ERROR" "UEFI firmware not found."
          echo_message "Please ensure 'edk2-bhyve' is installed (pkg install edk2-bhyve) or copy a compatible UEFI firmware file to $UEFI_FIRMWARE_PATH."
          exit 1
        fi
        ;;
      grub2-bhyve)
        if [ -f "$VM_DIR/grub.conf" ]; then
          BHYVE_LOADER_CLI_ARG="-l grub,${VM_DIR}/grub.conf"
          log "Using grub2-bhyve with config: ${VM_DIR}/grub.conf"
        else
          display_and_log "ERROR" "grub.conf not found in $VM_DIR."
          exit 1
        fi
        ;;
      *)
        display_and_log "ERROR" "Unsupported bootloader type for ISO installation: $BOOTLOADER_TYPE"
        exit 1
        ;;
    esac

    clear # Clear screen before console

    log "Running bhyve installer in background..."
    $BHYVE -c $CPUS -m $MEMORY -AHP -s 0,hostbridge -s 3:0,virtio-blk,$VM_DIR/$DISK -s 4:0,ahci-cd,$ISO_PATH -s 5:0,virtio-net,$TAP_0 -l com1,/dev/${CONSOLE}A -s 31,lpc ${BHYVE_LOADER_CLI_ARG} "$VMNAME" >> "$LOG_FILE" 2>&1 &
    VM_PID=$!
    echo "$VM_PID" > "$VM_DIR/vm.pid"
    log "Bhyve VM started in background with PID $VM_PID"

    echo_message ">>> Entering VM '$VMNAME' console (exit with ~.)"
    echo_message ">>> IMPORTANT: After shutting down the VM from within, you MUST type '~.' (tilde then dot) to exit this console and allow the script to continue cleanup."
    cu -l /dev/"${CONSOLE}B"

    log "cu session ended. Initiating cleanup..."

    # Explicitly kill bhyve process associated with this VMNAME
    local VM_PIDS_TO_KILL=$(ps -ax | grep "[b]hyve .* $VMNAME$" | awk '{print $1}')
    if [ -n "$VM_PIDS_TO_KILL" ]; then
        local PIDS_STRING=$(echo "$VM_PIDS_TO_KILL" | tr '
' ' ')
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
        log "No bhyve process found for '$VMNAME' to kill."
    fi

    # Now, destroy from kernel memory (important for bhyveload)
    if $BHYVECTL --vm="$VMNAME" --destroy > /dev/null 2>&1; then
        log "VM '$VMNAME' successfully destroyed from kernel memory."
    else
        log "VM '$VMNAME' was not found in kernel memory (already destroyed or never started)."
    fi

    # Kill any lingering cu or tail -f processes
    log "Attempting to stop associated cu process for /dev/${CONSOLE}B..."
    pkill -f "cu -l /dev/${CONSOLE}B" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        log "cu process for /dev/${CONSOLE}B stopped."
    else
        log "No cu process found or failed to stop for /dev/${CONSOLE}B."
    fi

    log "Attempting to stop associated cu process for /dev/${CONSOLE}A..."
    pkill -f "cu -l /dev/${CONSOLE}A" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        log "cu process for /dev/${CONSOLE}A stopped."
    else
        log "No cu process found or failed to stop for /dev/${CONSOLE}A."
    fi

    log "Attempting to stop associated tail -f process for $LOG_FILE..."
    pkill -f "tail -f $LOG_FILE" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        log "tail -f process for $LOG_FILE stopped."
    else
        log "No tail -f process found or failed to stop for $LOG_FILE."
    fi

    # Wait for the bhyve process to exit.
    # Capture its exit status.
    wait "$VM_PID"
    local BHYVE_EXIT_STATUS=$?

    # Check the exit status of the bhyve process
    if [ "$BHYVE_EXIT_STATUS" -eq 3 ] || [ "$BHYVE_EXIT_STATUS" -eq 4 ]; then
        # If bhyve exited due to a fault or error, then display error message
        display_and_log "ERROR" "Virtual machine '$VMNAME' failed to boot or installer exited with an error (exit code: $BHYVE_EXIT_STATUS). Check VM logs for details."
        exit 1
    else
        log "Bhyve process $VM_PID exited cleanly (status: $BHYVE_EXIT_STATUS)."
    fi
    log "Bhyve process $VM_PID exited."
  fi
  log "Exiting cmd_install function for VM: $VMNAME"
}


# === Subcommand: start ===
cmd_start() {
  log "Entering cmd_start function for VM: $1"
  if [ -z "$1" ]; then
    cmd_start_usage
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  display_and_log "INFO" "Loading VM configuration for '$VMNAME'..."
  log "VM Name: $VMNAME"
  log "CPUs: $CPUS"
  log "Memory: $MEMORY"
  log "Disk Image: $VM_DIR/$DISK"
  if [ -f "$VM_DIR/$DISK" ]; then
    log "Disk image '$VM_DIR/$DISK' found."
  else
    display_and_log "ERROR" "Disk image '$VM_DIR/$DISK' not found!"
    exit 1
  fi

  # === Check if bhyve is still running ===
  if ps -ax | grep -v grep | grep -c "[b]hyve .* -s .* $VMNAME$" > /dev/null; then
    display_and_log "INFO" "VM '$VMNAME' is still running. Attempting to stop..."
    pkill -f "bhyve.*$VMNAME"
    sleep 1
  fi

  # === Destroy VM if still remaining in kernel ===
  if $BHYVECTL --vm="$VMNAME" --destroy > /dev/null 2>&1; then
    display_and_log "INFO" "VM '$VMNAME' was still in kernel memory. Destroyed."
  fi

  local NETWORK_ARGS=""
  local NIC_IDX=0
  local DEV_NUM=5 # Starting device number for virtio-net

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

    display_and_log "INFO" "Checking network interface NIC_${NIC_IDX} (TAP: $CURRENT_TAP, MAC: $CURRENT_MAC, Bridge: $CURRENT_BRIDGE)"

    # === Create TAP interface if it doesn't exist ===
    if ! ifconfig "$CURRENT_TAP" > /dev/null 2>&1; then
      display_and_log "INFO" "TAP '$CURRENT_TAP' does not exist. Creating..."
      ifconfig "$CURRENT_TAP" create description "vmnet/${VMNAME}/${NIC_IDX}/${CURRENT_BRIDGE}" || { display_and_log "ERROR" "Failed to create TAP interface '$CURRENT_TAP'"; exit 1; }
      ifconfig "$CURRENT_TAP" up || { display_and_log "ERROR" "Failed to activate TAP interface '$CURRENT_TAP'"; exit 1; }
      display_and_log "INFO" "TAP '$CURRENT_TAP' created and activated."
    else
      ifconfig "$CURRENT_TAP" up || { display_and_log "ERROR" "Failed to activate existing TAP interface '$CURRENT_TAP'"; exit 1; }
      display_and_log "INFO" "TAP '$CURRENT_TAP' already exists and activated."
    fi

    # === Add to bridge if not already a member ===
    if ! ifconfig "$CURRENT_BRIDGE" > /dev/null 2>&1; then
      display_and_log "INFO" "Bridge interface '$CURRENT_BRIDGE' does not exist. Creating..."
      ifconfig bridge create name "$CURRENT_BRIDGE" || { display_and_log "ERROR" "Failed to create bridge '$CURRENT_BRIDGE'"; exit 1; }
      display_and_log "INFO" "Bridge interface '$CURRENT_BRIDGE' successfully created."
    else
      display_and_log "INFO" "Bridge interface '$CURRENT_BRIDGE' already exists."
    fi

    if ! ifconfig "$CURRENT_BRIDGE" | grep -qw "$CURRENT_TAP"; then
      display_and_log "INFO" "Adding TAP '$CURRENT_TAP' to bridge '$CURRENT_BRIDGE'..."
      ifconfig "$CURRENT_BRIDGE" addm "$CURRENT_TAP" || { display_and_log "ERROR" "Failed to add TAP '$CURRENT_TAP' to bridge '$CURRENT_BRIDGE'"; exit 1; }
      display_and_log "INFO" "TAP '$CURRENT_TAP' added to bridge '$CURRENT_BRIDGE'."
    else
      display_and_log "INFO" "TAP '$CURRENT_TAP' already connected to bridge '$CURRENT_BRIDGE'."
    fi

    NETWORK_ARGS+=" -s ${DEV_NUM}:0,virtio-net,\"$CURRENT_TAP\""
    DEV_NUM=$((DEV_NUM + 1))
    NIC_IDX=$((NIC_IDX + 1))
  done


  # === Start Logic ===
  if [ "$BOOTLOADER_TYPE" = "bhyveload" ]; then
    # --- BHYVELOAD START ---
    display_and_log "INFO" "Preparing for bhyveload start..."
    ensure_nmdm_device_nodes "$CONSOLE"
    sleep 1 # Give nmdm devices a moment to be ready
    
    display_and_log "INFO" "Verifying nmdm device nodes:"
    if [ -e "/dev/${CONSOLE}A" ]; then
      display_and_log "INFO" "/dev/${CONSOLE}A exists with permissions: $(stat -f "%Sp" /dev/${CONSOLE}A)"
    else
      display_and_log "ERROR" "/dev/${CONSOLE}A does NOT exist!"
      exit 1
    fi
    if [ -e "/dev/${CONSOLE}B" ]; then
      display_and_log "INFO" "/dev/${CONSOLE}B exists with permissions: $(stat -f "%Sp" /dev/${CONSOLE}B)"
    else
      display_and_log "ERROR" "/dev/${CONSOLE}B does NOT exist!"
      exit 1
    fi

    run_bhyveload "$VM_DIR/$DISK" || exit 1

    local BHYVE_CMD="$BHYVE -c $CPUS -m $MEMORY -AHP -s 0,hostbridge -s 3:0,virtio-blk,$VM_DIR/$DISK $NETWORK_ARGS -l com1,/dev/${CONSOLE}A -s 31,lpc \"$VMNAME\""
    log "Executing bhyve command: $BHYVE_CMD"
    eval "$BHYVE_CMD" >> "$LOG_FILE" 2>&1 &
  else
    # --- uefi/GRUB START ---
    display_and_log "INFO" "Preparing for non-bhyveload start..."
    local BHYVE_LOADER_CLI_ARG=""
    case "$BOOTLOADER_TYPE" in
      uefi|bootrom)
        local UEFI_FIRMWARE_FOUND=false
        if [ -f "$UEFI_FIRMWARE_PATH" ]; then
          BHYVE_LOADER_CLI_ARG="-l bootrom,$UEFI_FIRMWARE_PATH"
          log "Using uefi firmware from configured path: $UEFI_FIRMWARE_PATH"
          UEFI_FIRMWARE_FOUND=true
        elif [ -f "/usr/local/share/uefi-firmware/BHYVE_UEFI.fd" ]; then
          BHYVE_LOADER_CLI_ARG="-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd"
          log "Using uefi firmware from default system path: /usr/local/share/uefi-firmware/BHYVE_UEFI.fd"
          UEFI_FIRMWARE_FOUND=true
        fi

        if [ "$UEFI_FIRMWARE_FOUND" = false ]; then
          display_and_log "ERROR" "UEFI firmware not found."
          echo_message "Please ensure 'edk2-bhyve' is installed (pkg install edk2-bhyve) or copy a compatible UEFI firmware file to $UEFI_FIRMWARE_PATH."
          exit 1
        fi
        ;;
      grub2-bhyve)
        if [ -f "$VM_DIR/grub.conf" ]; then
          BHYVE_LOADER_CLI_ARG="-l grub,${VM_DIR}/grub.conf"
          log "Using grub2-bhyve with config: ${VM_DIR}/grub.conf"
        else
          display_and_log "ERROR" "grub.conf not found in $VM_DIR."
          exit 1
        fi
        ;;
      *)
        display_and_log "ERROR" "Unsupported bootloader type: $BOOTLOADER_TYPE"
        exit 1
        ;;
    esac

    log "Starting VM '$VMNAME'..."
    local BHYVE_CMD="$BHYVE -c $CPUS -m $MEMORY -AHP -s 0,hostbridge -s 3:0,virtio-blk,$VM_DIR/$DISK $NETWORK_ARGS -l com1,/dev/${CONSOLE}A -s 31,lpc ${BHYVE_LOADER_CLI_ARG} \"$VMNAME\""
    log "Executing bhyve command: $BHYVE_CMD"
    eval "$BHYVE_CMD" >> "$LOG_FILE" 2>&1 &
  fi

  BHYVE_PID=$!
  echo "$BHYVE_PID" > "$VM_DIR/vm.pid"

  # Wait a moment
  sleep 1

  display_and_log "INFO" "VM '$VMNAME' started. Please connect to the console using: $0 console $VMNAME"

  if ps -p "$BHYVE_PID" > /dev/null 2>&1; then
    log "VM '$VMNAME' is running with PID $BHYVE_PID"
  else
    display_and_log "ERROR" "Failed to start VM '$VMNAME' - PID not found"
  fi
  log "Exiting cmd_start function for VM: $VMNAME"
}

# === Subcommand: stop ===
cmd_stop() {
  log "Entering cmd_stop function for VM: $1"
  if [ -z "$1" ]; then
    cmd_stop_usage
    exit 1
  fi

  local VMNAME="$1"
  local GRACEFUL_SHUTDOWN=false

  # Parse arguments for graceful shutdown
  local ARGS=()
  for arg in "$@"; do
    if [[ "$arg" == "--graceful" ]]; then
      GRACEFUL_SHUTDOWN=true
    else
      ARGS+=("$arg")
    fi
  done

  # Ensure VMNAME is set from ARGS if it was shifted out by graceful option
  if [ -z "$VMNAME" ] && [ ${#ARGS[@]} -gt 0 ]; then
    VMNAME="${ARGS[0]}"
  fi

  if [ -z "$VMNAME" ]; then
    cmd_stop_usage
    exit 1
  fi

  load_vm_config "$VMNAME"

  log "Stopping VM '$VMNAME'..."

  local VM_RUNNING=false
  if ps -ax | grep -v grep | grep -c "[b]hyve .* -s .* $VMNAME$" > /dev/null; then
    VM_RUNNING=true
    log "VM '$VMNAME' is detected as running."
  else
    log "VM '$VMNAME' is not detected as running by ps."
  fi

  if [ "$GRACEFUL_SHUTDOWN" = true ] && [ "$VM_RUNNING" = true ]; then
    log "Attempting graceful shutdown for VM '$VMNAME'..."
    display_and_log "INFO" "Attempting graceful shutdown for VM '$VMNAME'..."
    $BHYVECTL --vm="$VMNAME" --poweroff
    if [ $? -ne 0 ]; then
      log "WARNING: bhyvectl --poweroff failed for '$VMNAME'. Proceeding with forceful shutdown."
      display_and_log "WARNING" "Graceful shutdown failed. Proceeding with forceful shutdown."
    else
      log "ACPI poweroff signal sent to VM '$VMNAME'. Waiting for VM to shut down..."
      local TIMEOUT=30 # seconds
      local ELAPSED_TIME=0
      local VM_STOPPED=false

      while [ "$ELAPSED_TIME" -lt "$TIMEOUT" ]; do
        if ! ps -ax | grep -v grep | grep -c "[b]hyve .* -s .* $VMNAME$" > /dev/null; then
          log "VM '$VMNAME' has gracefully shut down."
          display_and_log "INFO" "VM '$VMNAME' has gracefully shut down."
          VM_STOPPED=true
          break
        fi
        sleep 1
        ELAPSED_TIME=$((ELAPSED_TIME + 1))
      done

      if [ "$VM_STOPPED" = false ]; then
        log "WARNING: VM '$VMNAME' did not shut down gracefully within $TIMEOUT seconds. Proceeding with forceful termination."
        display_and_log "WARNING" "VM '$VMNAME' did not shut down gracefully. Forcing termination."
      fi
    fi
  fi

  # Forceful termination (if not gracefully stopped or if --graceful not used)
  if [ "$VM_RUNNING" = true ] && [ "$VM_STOPPED" = false ]; then
    log "Initiating forceful termination for VM '$VMNAME'..."
    # === Find the PID of the bhyve process, anchor to end of line for specificity ===
    local VM_PID=""
    if [ -f "$VM_DIR/vm.pid" ]; then
      VM_PID=$(cat "$VM_DIR/vm.pid")
      log "Found VM PID from vm.pid file: $VM_PID"
    else
      VM_PID=$(ps -ax | grep "[b]hyve .* $VMNAME" | awk '{print $1}')
      log "Found VM PID by ps grep: $VM_PID"
    fi

    if [ -n "$VM_PID" ]; then
      # Handle multiple PIDs by not quoting the variable
      log "Sending TERM signal to PID(s): $(echo "$VM_PID" | tr '\n' ' ')"
      kill $VM_PID
      sleep 1 # Wait a moment for the processes to terminate

      # Loop through PIDs to check if they are still running and force kill if necessary
      for pid in $VM_PID; do
        if ps -p "$pid" > /dev/null 2>&1; then
          log "PID $pid still running, forcing KILL..."
          kill -9 "$pid"
          sleep 1
        fi
      done
      log "bhyve process stopped."
    else
      log "No running bhyve process found for '$VMNAME' to kill."
    fi
  fi

  # === Stop associated console (cu) processes ===
  log "Attempting to stop associated cu process for /dev/${CONSOLE}B..."
  pkill -f "cu -l /dev/${CONSOLE}B"
  if [ $? -eq 0 ]; then
    log "cu process for /dev/${CONSOLE}B stopped."
  else
    log "No cu process found or failed to stop for /dev/${CONSOLE}B."
  fi

  log "Attempting to stop associated tail -f process for $LOG_FILE..."
  pkill -f "tail -f $LOG_FILE"
  if [ $? -eq 0 ]; then
    log "tail -f process for $LOG_FILE stopped."
  else
    log "No tail -f process found or failed to stop for $LOG_FILE."
  fi

  # === Always attempt to destroy the VM from the kernel ===
  # This is crucial for bhyveload and for cleaning up zombie VMs
  if $BHYVECTL --vm="$VMNAME" --destroy > /dev/null 2>&1; then
    log "VM '$VMNAME' successfully destroyed from kernel memory."
    display_and_log "INFO" "VM '$VMNAME' successfully stopped."
  else
    log "VM '$VMNAME' was not found in kernel memory (already destroyed or never started)."
    display_and_log "INFO" "VM '$VMNAME' is not running."
  fi

  # Clean up network interfaces after stopping
  cleanup_vm_network_interfaces "$VMNAME"

  # Remove vm.pid file
  if [ -f "$VM_DIR/vm.pid" ]; then
    rm "$VM_DIR/vm.pid"
    log "Removed vm.pid file."
  fi
  log "Exiting cmd_stop function for VM: $VMNAME"
}








# === Subcommand: console ===
cmd_console() {
  if [ -z "$1" ]; then
    cmd_console_usage
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  # === Check console device ===
  DEVICE_B="/dev/${CONSOLE}B"

  if [ ! -e "$DEVICE_B" ]; then
    display_and_log "ERROR" "Console device '$DEVICE_B' not found."
    display_and_log "INFO" "Ensure the VM has been run at least once, or the device has been created."
    exit 1
  fi

  echo_message ">>> Accessing VM '$VMNAME' console"
  echo_message ">>> Exit with ~."

  # === Enter console ===
  cu -l "$DEVICE_B"
}

# === Subcommand: logs ===
cmd_logs() {
  if [ -z "$1" ]; then
    cmd_logs_usage
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  if [ ! -f "$LOG_FILE" ]; then
    display_and_log "ERROR" "Log file for VM '$VMNAME' not found: $LOG_FILE"
    exit 1
  fi

      echo_message ">>> Displaying logs for VM '$VMNAME' (Press Ctrl+C to exit)"
  tail -f "$LOG_FILE"
}

# === Subcommand: status ===
cmd_status() {
  local header_format="%-20s %-10s %-12s %-12s %-12s %-12s %-10s\n"
  local header_line
  printf "$header_format" \
    "VM NAME" \
    "STATUS" \
    "CPU (Set)" \
    "RAM (Set)" \
    "CPU Usage" \
    "RAM Usage" \
    "PID"
  
  # === Generate dynamic separator line ===
  header_line=$(printf "$header_format" \
    "--------------------" \
    "----------" \
    "------------" \
    "------------" \
    "------------" \
    "------------" \
    "----------")
  echo_message "${header_line// /}" # Remove spaces to make it a continuous line

  for VMCONF in "$VM_CONFIG_BASE_DIR"/*/vm.conf; do
    [ -f "$VMCONF" ] || continue
    
    local current_vmname=$(basename "$(dirname "$VMCONF")")
    load_vm_config "$current_vmname" # This will set VMNAME, VM_DIR, and LOG_FILE correctly.
    
    local VMNAME="${VMNAME:-N/A}"
    local CPUS="${CPUS:-N/A}"
    local MEMORY="${MEMORY:-N/A}"
   
    local PID="" # Initialize to empty string

    # Try to get PID from vm.pid file first
    if [ -f "$VM_DIR/vm.pid" ]; then
      local STORED_PID=$(cat "$VM_DIR/vm.pid")
      if [ -n "$STORED_PID" ] && ps -p "$STORED_PID" > /dev/null 2>&1; then
        PID="$STORED_PID"
      fi
    fi

    # If PID is still empty, try to find it with grep
    if [ -z "$PID" ]; then
      local GREPPED_PID=$(ps -ax | grep "[b]hyve .* $VMNAME" | awk '{print $1}')
      if [ -n "$GREPPED_PID" ] && ps -p "$GREPPED_PID" > /dev/null 2>&1; then
        PID="$GREPPED_PID"
      fi
    fi

    local BHYVECTL_STATUS=$($BHYVECTL --vm="$VMNAME" --get-all 2>/dev/null)
    local STATUS="STOPPED"
    local CPU_USAGE="N/A"
    local RAM_USAGE="N/A"

    # Determine overall status
    if [ -n "$PID" ] || [ -n "$BHYVECTL_STATUS" ]; then
        STATUS="RUNNING"
    fi

    # Calculate CPU/RAM usage only if a valid PID is found
    if [ -n "$PID" ]; then
      local PS_INFO=$(ps -p "$PID" -o %cpu,rss= | tail -n 1)
      if [ -n "$PS_INFO" ]; then
        CPU_USAGE=$(echo "$PS_INFO" | awk '{print $1 "%"}')
        local RAM_RSS_KB=$(echo "$PS_INFO" | awk '{print $2}')
        if command -v bc >/dev/null 2>&1; then
          RAM_USAGE=$(echo "scale=0; $RAM_RSS_KB / 1024" | bc)
          RAM_USAGE="${RAM_USAGE}MB"
        else
          RAM_USAGE="${RAM_RSS_KB}KB (bc not found)"
        fi
      fi
    fi

    printf "$header_format" "$VMNAME" "$STATUS" "$CPUS" "$MEMORY" "$CPU_USAGE" "$RAM_USAGE" "$PID"
  done
}

# === Subcommand: autostart ===
cmd_autostart() {
  if [ -z "$1" ] || ( [ "$2" != "enable" ] && [ "$2" != "disable" ] ); then
    cmd_autostart_usage
    exit 1
  fi

  VMNAME="$1"
  ACTION="$2"
  load_vm_config "$VMNAME"

  local CONF_FILE="$VM_DIR/vm.conf"

  if [ "$ACTION" = "enable" ]; then
    log "Enabling autostart for VM '$VMNAME'..."
    sed -i '' 's/^AUTOSTART=.*/AUTOSTART=yes/' "$CONF_FILE"
    display_and_log "INFO" "Autostart enabled for VM '$VMNAME'."
  elif [ "$ACTION" = "disable" ]; then
    log "Disabling autostart for VM '$VMNAME'..."
    sed -i '' 's/^AUTOSTART=.*/AUTOSTART=no/' "$CONF_FILE"
    display_and_log "INFO" "Autostart disabled for VM '$VMNAME'."
  fi
}






# === Subcommand: modify ===
cmd_modify() {
  log "Entering cmd_modify function for VM: $1"
  if [ -z "$1" ]; then
    cmd_modify_usage
    exit 1
  fi

  VMNAME="$1"
  shift
  load_vm_config "$VMNAME"

  local CONF_FILE="$VM_DIR/vm.conf"
  local CPU_NEW=""
  local RAM_NEW=""
  local NIC_TO_MODIFY=""
  local TAP_NEW=""
  local MAC_NEW=""
  local BRIDGE_NEW=""

  # === Check if VM is running ===
  if ps -ax | grep -v grep | grep -c "[b]hyve .* -s .* $VMNAME$" > /dev/null; then
    display_and_log "ERROR" "VM '$VMNAME' is currently running. Please stop the VM before modifying its configuration."
    exit 1
  fi

  while (( "$#" )); do
    case "$1" in
      --cpu)
        shift
        CPU_NEW="$1"
        log "Setting CPU to $CPU_NEW for VM '$VMNAME'."
        sed -i '' "s/^CPUS=.*/CPUS=$CPU_NEW/" "$CONF_FILE"
        ;;
      --ram)
        shift
        RAM_NEW="$1"
        log "Setting RAM to $RAM_NEW for VM '$VMNAME'."
        sed -i '' "s/^MEMORY=.*/MEMORY=$RAM_NEW/" "$CONF_FILE"
        ;;
      --nic)
        shift
        NIC_TO_MODIFY="$1"
        if ! [[ "$NIC_TO_MODIFY" =~ ^[0-9]+$ ]]; then
          display_and_log "ERROR" "Invalid NIC index: $NIC_TO_MODIFY. Must be a number."
          exit 1
        fi
        ;;
      --tap)
        shift
        TAP_NEW="$1"
        if [ -z "$NIC_TO_MODIFY" ]; then
          display_and_log "ERROR" "--nic <index> must be specified before --tap."
          exit 1
        fi
        log "Setting TAP for NIC ${NIC_TO_MODIFY} to $TAP_NEW for VM '$VMNAME'."
        sed -i '' "s/^TAP_${NIC_TO_MODIFY}=.*/TAP_${NIC_TO_MODIFY}=$TAP_NEW/" "$CONF_FILE"
        ;;
      --mac)
        shift
        MAC_NEW="$1"
        if [ -z "$NIC_TO_MODIFY" ]; then
          display_and_log "ERROR" "--nic <index> must be specified before --mac."
          exit 1
        fi
        log "Setting MAC for NIC ${NIC_TO_MODIFY} to $MAC_NEW for VM '$VMNAME'."
        sed -i '' "s/^MAC_${NIC_TO_MODIFY}=.*/MAC_${NIC_TO_MODIFY}=$MAC_NEW/" "$CONF_FILE"
        ;;
      --bridge)
        shift
        BRIDGE_NEW="$1"
        if [ -z "$NIC_TO_MODIFY" ]; then
          display_and_log "ERROR" "--nic <index> must be specified before --bridge."
          exit 1
        fi
        log "Setting BRIDGE for NIC ${NIC_TO_MODIFY} to $BRIDGE_NEW for VM '$VMNAME'."
        sed -i '' "s/^BRIDGE_${NIC_TO_MODIFY}=.*/BRIDGE_${NIC_TO_MODIFY}=$BRIDGE_NEW/" "$CONF_FILE"
        ;;
      *)
        display_and_log "ERROR" "Invalid option: $1"
        echo_message "Usage: $0 modify <vmname> [--cpu <num>] [--ram <size>] [--nic <index> --tap <tap_name> --mac <mac_address> --bridge <bridge_name>]"
        exit 1
        ;;
    esac
    shift
  done

  display_and_log "INFO" "VM '$VMNAME' configuration updated."
  log "Exiting cmd_modify function for VM: $VMNAME"
}

# === Subcommand: clone ===
cmd_clone() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    cmd_clone_usage
    exit 1
  fi

  local SOURCE_VMNAME="$1"
  local NEW_VMNAME="$2"

  local SOURCE_VM_DIR="$VM_CONFIG_BASE_DIR/$SOURCE_VMNAME"
  local NEW_VM_DIR="$VM_CONFIG_BASE_DIR/$NEW_VMNAME"
  local SOURCE_CONF_FILE="$SOURCE_VM_DIR/vm.conf"
  local NEW_CONF_FILE="$NEW_VM_DIR/vm.conf"

  # === Check if source VM exists ===
  if [ ! -d "$SOURCE_VM_DIR" ]; then
    display_and_log "ERROR" "Source VM '$SOURCE_VMNAME' not found: $SOURCE_VM_DIR"
    exit 1
  fi

  # === Check if new VM already exists ===
  if [ -d "$NEW_VM_DIR" ]; then
    display_and_log "ERROR" "Destination VM '$NEW_VMNAME' already exists: $NEW_VM_DIR"
    exit 1
  fi

  # === Load source VM config to get its status ===
  load_vm_config "$SOURCE_VMNAME"

  # === Check if source VM is running ===
  if ps -ax | grep -v grep | grep -c "[b]hyve .* -s .* $SOURCE_VMNAME$" > /dev/null; then
    display_and_log "ERROR" "Source VM '$SOURCE_VMNAME' is currently running. Please stop the VM before cloning."
    exit 1
  fi

  display_and_log "INFO" "Cloning VM '$SOURCE_VMNAME' to '$NEW_VMNAME'..."

  # === Create new VM directory ===
  mkdir -p "$NEW_VM_DIR"
  log "Created new VM directory: $NEW_VM_DIR"

  # === Copy disk image ===
  local SOURCE_DISK_PATH="$SOURCE_VM_DIR/$DISK"
  local NEW_DISK_PATH="$NEW_VM_DIR/$DISK"
  display_and_log "INFO" "Copying disk image from $SOURCE_DISK_PATH to $NEW_DISK_PATH..."
  cp "$SOURCE_DISK_PATH" "$NEW_DISK_PATH"
  if [ $? -ne 0 ]; then
    display_and_log "ERROR" "Failed to copy disk image."
    rm -rf "$NEW_VM_DIR"
    exit 1
  fi
  log "Disk image copied."

  # === Copy config file ===
  cp "$SOURCE_CONF_FILE" "$NEW_CONF_FILE"
  log "Copied configuration file to $NEW_CONF_FILE"

  # === Generate new unique values ===
  local NEW_UUID=$(uuidgen)
  local NEW_CONSOLE="nmdm-${NEW_VMNAME}.1"
  local NEW_LOG_FILE="$NEW_VM_DIR/vm.log"

  # === Update new config file ===
  log "Updating configuration for new VM '$NEW_VMNAME'..."
  sed -i '' "s/^VMNAME=.*/VMNAME=$NEW_VMNAME/" "$NEW_CONF_FILE"
  sed -i '' "s/^UUID=.*/UUID=$NEW_UUID/" "$NEW_CONF_FILE"
  sed -i '' "s/^CONSOLE=.*/CONSOLE=$NEW_CONSOLE/" "$NEW_CONF_FILE"
  sed -i '' "s#^LOG=.*#LOG=$NEW_LOG_FILE#" "$NEW_CONF_FILE"
  sed -i '' "s/^AUTOSTART=.*/AUTOSTART=no/" "$NEW_CONF_FILE" # Cloned VMs should not autostart by default

  # === Update network interfaces ===
  local NIC_IDX=0
  while true; do
    # Check if TAP_ and MAC_ variables exist for the current index in the source config
    if ! grep -q "^TAP_${NIC_IDX}=" "$NEW_CONF_FILE"; then
      break # No more NICs
    fi

    log "Updating NIC_${NIC_IDX} for clone..."

    # Generate new TAP
    local NEXT_TAP_NUM=0
    while ifconfig | grep -q "^tap${NEXT_TAP_NUM}:"; do
      NEXT_TAP_NUM=$((NEXT_TAP_NUM + 1))
    done
    local NEW_TAP="tap${NEXT_TAP_NUM}"
    log "Generated new TAP for NIC_${NIC_IDX}: $NEW_TAP"

    # Generate new MAC
    local NEW_MAC="58:9c:fc$(jot -r -w ":%02x" -s "" 3 0 255)"
    log "Generated new MAC for NIC_${NIC_IDX}: $NEW_MAC"

    # Update the new config file
    sed -i '' "s/^TAP_${NIC_IDX}=.*/TAP_${NIC_IDX}=$NEW_TAP/" "$NEW_CONF_FILE"
    sed -i '' "s/^MAC_${NIC_IDX}=.*/MAC_${NIC_IDX}=$NEW_MAC/" "$NEW_CONF_FILE"

    NIC_IDX=$((NIC_IDX + 1))
  done

  display_and_log "INFO" "VM '$NEW_VMNAME' cloned successfully."
  display_and_log "INFO" "You can now start it with: $0 start $NEW_VMNAME"
}

# === Subcommand: info ===
cmd_info() {
  if [ -z "$1" ]; then
    cmd_info_usage
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  echo_message "----------------------------------------"
  echo_message "VM Information for '$VMNAME':"
  echo_message "----------------------------------------"
  local info_format="  %-15s: %s\n"

  # === Check runtime status first ===
  local PID="" # Initialize to empty string

  # Try to get PID from vm.pid file first
  if [ -f "$VM_DIR/vm.pid" ]; then
    local STORED_PID=$(cat "$VM_DIR/vm.pid")
    if [ -n "$STORED_PID" ] && ps -p "$STORED_PID" > /dev/null 2>&1; then
      PID="$STORED_PID"
    fi
  fi

  # If PID is still empty, try to find it with grep
  if [ -z "$PID" ]; then
    local GREPPED_PID=$(ps -ax | grep "[b]hyve .* $VMNAME" | awk '{print $1}')
    if [ -n "$GREPPED_PID" ] && ps -p "$GREPPED_PID" > /dev/null 2>&1; then
      PID="$GREPPED_PID"
    fi
  fi

  local BHYVECTL_STATUS=$($BHYVECTL --vm="$VMNAME" --get-all 2>/dev/null)
  local STATUS_DISPLAY="STOPPED"
  local CPU_USAGE="N/A"
  local RAM_USAGE="N/A"

  if [ -n "$PID" ] || [ -n "$BHYVECTL_STATUS" ]; then
      STATUS_DISPLAY="RUNNING"
      if [ -n "$PID" ]; then
        STATUS_DISPLAY="RUNNING (PID: $PID)"
      fi
  fi

  if [ -n "$PID" ]; then
    local PS_INFO=$(ps -p "$PID" -o %cpu,rss= | tail -n 1)
    if [ -n "$PS_INFO" ]; then
      CPU_USAGE=$(echo "$PS_INFO" | awk '{print $1 "%"}')
      local RAM_RSS_KB=$(echo "$PS_INFO" | awk '{print $2}')
      if command -v bc >/dev/null 2>&1; then
        RAM_USAGE=$(echo "scale=0; $RAM_RSS_KB / 1024" | bc) # Convert KB to MB
        RAM_USAGE="${RAM_USAGE}MB"
      else
        RAM_USAGE="${RAM_RSS_KB}KB (bc not found)"
      fi
    fi
  fi

  printf "$info_format" "Name" "$VMNAME"
  printf "$info_format" "Status" "$STATUS_DISPLAY" # Moved up
  printf "$info_format" "CPUs" "$CPUS"
  printf "$info_format" "Memory" "$MEMORY"
  printf "$info_format" "Bootloader" "$BOOTLOADER_TYPE" # Added
  printf "$info_format" "Disk Path" "$VM_DIR/$DISK"
  local DISK_USAGE="N/A"
  if [ -f "$VM_DIR/$DISK" ]; then
    DISK_USAGE=$(du -h "$VM_DIR/$DISK" | awk '{print $1}')
  fi
  printf "$info_format" "Disk Used" "$DISK_USAGE"
  local DISK_SET_DISPLAY="${DISKSIZE}G"
  if [ -z "$DISKSIZE" ]; then
    DISK_SET_DISPLAY="N/A"
  fi
  printf "$info_format" "Disk Set" "$DISK_SET_DISPLAY"
  printf "$info_format" "Console" "$CONSOLE"
  printf "$info_format" "Log File" "$LOG_FILE"
  printf "$info_format" "Autostart" "$AUTOSTART"

  if [ "$STATUS_DISPLAY" != "STOPPED" ]; then # Only show CPU/RAM usage if running
    printf "$info_format" "CPU Usage" "$CPU_USAGE"
    printf "$info_format" "RAM Usage" "$RAM_USAGE"
  fi

  echo_message "  ----------------------------------------"
  echo_message "  Network Interfaces:"

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

    echo_message "  Interface ${NIC_IDX}:"
    printf "$info_format" "    TAP_${NIC_IDX}" "$CURRENT_TAP"
    printf "$info_format" "    MAC_${NIC_IDX}" "$CURRENT_MAC"
    printf "$info_format" "    BRIDGE_${NIC_IDX}" "$CURRENT_BRIDGE"
    NIC_IDX=$((NIC_IDX + 1))
  done
  echo_message "----------------------------------------"
}







# === Subcommand: resize-disk ===
cmd_resize_disk() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    cmd_resize_disk_usage
    exit 1
  fi

  VMNAME="$1"
  NEW_SIZE_GB="$2"
  load_vm_config "$VMNAME"

  local DISK_PATH="$VM_DIR/$DISK"

  # === Check if VM is running ===
  if ps -ax | grep -v grep | grep -c "[b]hyve .* -s .* $VMNAME$" > /dev/null; then
    display_and_log "ERROR" "VM '$VMNAME' is currently running. Please stop the VM before resizing its disk."
    exit 1
  fi

  if [ ! -f "$DISK_PATH" ]; then
    display_and_log "ERROR" "Disk image for VM '$VMNAME' not found: $DISK_PATH"
    exit 1
  fi

  # === Get current disk size in GB ===
  CURRENT_SIZE_BYTES=$(stat -f %z "$DISK_PATH")
  CURRENT_SIZE_GB=$((CURRENT_SIZE_BYTES / 1024 / 1024 / 1024))

  if (( NEW_SIZE_GB <= CURRENT_SIZE_GB )); then
    display_and_log "ERROR" "New size ($NEW_SIZE_GB GB) must be greater than current size ($CURRENT_SIZE_GB GB)."
    exit 1
  fi

  log "Resizing disk for VM '$VMNAME' from ${CURRENT_SIZE_GB}GB to ${NEW_SIZE_GB}GB..."
  truncate -s "${NEW_SIZE_GB}G" "$DISK_PATH"
  if [ $? -ne 0 ]; then
    display_and_log "ERROR" "Failed to resize disk image."
    exit 1
  fi
  # === Update DISKSIZE in vm.conf ===
  sed -i '' "s/^DISKSIZE=.*/DISKSIZE=${NEW_SIZE_GB}/" "$CONF_FILE"
  log "Disk resized successfully and vm.conf updated."
  display_and_log "INFO" "Disk for VM '$VMNAME' has been resized to ${NEW_SIZE_GB}GB."
  display_and_log "INFO" "Note: You may need to extend the partition inside the VM operating system."
}


# === Subcommand: export ===
cmd_export() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    cmd_export_usage
    exit 1
  fi

  VMNAME="$1"
  DEST_PATH="$2"
  VM_DIR="$VM_CONFIG_BASE_DIR/$VMNAME"

  if [ ! -d "$VM_DIR" ]; then
    display_and_log "ERROR" "VM '$VMNAME' not found: $VM_DIR"
    exit 1
  fi

  # === Check if VM is running ===
  if ps -ax | grep -v grep | grep -c "[b]hyve .* -s .* $VMNAME$" > /dev/null; then
    display_and_log "ERROR" "VM '$VMNAME' is currently running. Please stop the VM before exporting."
    exit 1
  fi

  log "Exporting VM '$VMNAME' to '$DEST_PATH'..."
  tar -czf "$DEST_PATH" -C "$VM_CONFIG_BASE_DIR" "$VMNAME"
  if [ $? -ne 0 ]; then
    display_and_log "ERROR" "Failed to export VM '$VMNAME'."
    exit 1
  fi
  log "VM '$VMNAME' exported successfully to '$DEST_PATH'."
}

# === Subcommand: import ===
cmd_import() {
  if [ -z "$1" ]; then
    cmd_import_usage
    exit 1
  fi

  local ARCHIVE_PATH="$1"

  if [ ! -f "$ARCHIVE_PATH" ]; then
    display_and_log "ERROR" "Archive file not found: '$ARCHIVE_PATH'"
    exit 1
  fi

  # === Extract VM name from archive path to avoid collisions ===
  local EXTRACTED_DIR_NAME=$(tar -tf "$ARCHIVE_PATH" | head -n 1 | cut -d'/' -f1)
  if [ -z "$EXTRACTED_DIR_NAME" ]; then
      display_and_log "ERROR" "Could not determine VM name from archive."
      exit 1
  fi

  local NEW_VM_DIR="$VM_CONFIG_BASE_DIR/$EXTRACTED_DIR_NAME"

  if [ -d "$NEW_VM_DIR" ]; then
    display_and_log "ERROR" "A VM named '$EXTRACTED_DIR_NAME' already exists. Please remove it or rename the directory in the archive."
    exit 1
  fi

  display_and_log "INFO" "Importing VM from '$ARCHIVE_PATH'..."

  # === Extract the archive ===
  tar -xzf "$ARCHIVE_PATH" -C "$VM_CONFIG_BASE_DIR"
  if [ $? -ne 0 ]; then
    display_and_log "ERROR" "Failed to extract VM archive."
    rm -rf "$NEW_VM_DIR" # Clean up partial extraction
    exit 1
  fi

  local IMPORTED_VMNAME="$EXTRACTED_DIR_NAME"
  load_vm_config "$IMPORTED_VMNAME"

  # === Generate new UUID, MAC, TAP, CONSOLE for the imported VM to avoid conflicts ===
  local NEW_UUID=$(uuidgen)
  local NEW_CONSOLE="nmdm-${IMPORTED_VMNAME}.1"
  local NEW_LOG_FILE="$NEW_VM_DIR/vm.log"

  local CONF_FILE="$NEW_VM_DIR/vm.conf"
  sed -i '' "s/^UUID=.*/UUID=$NEW_UUID/" "$CONF_FILE"
  sed -i '' "s/^CONSOLE=.*/CONSOLE=$NEW_CONSOLE/" "$CONF_FILE"
  sed -i '' "s#^LOG=.*#LOG=$NEW_LOG_FILE#" "$CONF_FILE"

  # === Update network interfaces ===
  local NIC_IDX=0
  while true; do
    if ! grep -q "^TAP_${NIC_IDX}=" "$CONF_FILE"; then
      break # No more NICs
    fi

    local NEXT_TAP_NUM=0
    while ifconfig | grep -q "^tap${NEXT_TAP_NUM}:"; do
      NEXT_TAP_NUM=$((NEXT_TAP_NUM + 1))
    done
    local NEW_TAP="tap${NEXT_TAP_NUM}"
    local NEW_MAC="58:9c:fc$(jot -r -w ":%02x" -s "" 3 0 255)"

    sed -i '' "s/^TAP_${NIC_IDX}=.*/TAP_${NIC_IDX}=$NEW_TAP/" "$CONF_FILE"
    sed -i '' "s/^MAC_${NIC_IDX}=.*/MAC_${NIC_IDX}=$NEW_MAC/" "$CONF_FILE"

    NIC_IDX=$((NIC_IDX + 1))
  done

  display_and_log "INFO" "VM '$IMPORTED_VMNAME' successfully imported."
  display_and_log "INFO" "You may need to review the configuration with '$0 modify $IMPORTED_VMNAME' if the host environment has changed."
}





# === Subcommand: network add ===
cmd_network_add() {
  local VMNAME=""
  local BRIDGE_NAME=""
  local MAC_ADDRESS=""

  # === Parse named arguments ===
  while (( "$#" )); do
    case "$1" in
      --vm)
        shift
        VMNAME="$1"
        ;;
      --switch)
        shift
        BRIDGE_NAME="$1"
        ;;
      --mac)
        shift
        MAC_ADDRESS="$1"
        ;;
      *)
        display_and_log "ERROR" "Invalid option: $1"
        cmd_network_add_usage
        exit 1
        ;;
    esac
    shift
  done

  # === Validate required arguments ===
  if [ -z "$VMNAME" ] || [ -z "$BRIDGE_NAME" ]; then
    cmd_network_add_usage
    exit 1
  fi

  load_vm_config "$VMNAME"

  # === Check if VM is running ===
  if ps -ax | grep -v grep | grep -c "[b]hyve .* -s .* $VMNAME$" > /dev/null; then
    display_and_log "ERROR" "VM '$VMNAME' is currently running. Please stop the VM before adding a network interface."
    exit 1
  fi

  local NIC_IDX=0
  while true; do
    local CURRENT_TAP_VAR="TAP_${NIC_IDX}"
    local CURRENT_TAP="${!CURRENT_TAP_VAR}"
    if [ -z "$CURRENT_TAP" ]; then
      break # Found next available index
    fi
    NIC_IDX=$((NIC_IDX + 1))
  done

  local NEW_TAP
  NEXT_TAP_NUM=0
  while ifconfig | grep -q "^tap${NEXT_TAP_NUM}:"; do
    NEXT_TAP_NUM=$((NEXT_TAP_NUM + 1))
  done
  NEW_TAP="tap${NEXT_TAP_NUM}"

  local NEW_MAC="${MAC_ADDRESS:-58:9c:fc$(jot -r -w ":%02x" -s "" 3 0 255)}"

  local CONF_FILE="$VM_DIR/vm.conf"
  echo "TAP_${NIC_IDX}=$NEW_TAP" >> "$CONF_FILE"
  echo "MAC_${NIC_IDX}=$NEW_MAC" >> "$CONF_FILE"
  echo "BRIDGE_${NIC_IDX}=$BRIDGE_NAME" >> "$CONF_FILE"

  # === Create and configure the TAP interface immediately ===
  log "Creating TAP interface '$NEW_TAP'..."
  ifconfig "$NEW_TAP" create
  if [ $? -ne 0 ]; then
    display_and_log "ERROR" "Failed to create TAP interface '$NEW_TAP'."
    exit 1
  fi
  ifconfig "$NEW_TAP" description "vm-$VMNAME-nic${NIC_IDX}"
  ifconfig "$NEW_TAP" up
  log "TAP interface '$NEW_TAP' created and activated."

  # === Add TAP to bridge ===
  if ! ifconfig "$BRIDGE_NAME" > /dev/null 2>&1; then
    log "Bridge interface '$BRIDGE_NAME' does not exist. Creating..."
    ifconfig bridge create name "$BRIDGE_NAME"
    log "Bridge interface '$BRIDGE_NAME' successfully created."
    display_and_log "INFO" "Switch bridge '$BRIDGE_NAME' successfully created."
  else
    log "Bridge interface '$BRIDGE_NAME' already exists."
  fi

  ifconfig "$BRIDGE_NAME" addm "$NEW_TAP"
  if [ $? -ne 0 ]; then
    display_and_log "ERROR" "Failed to add TAP '$NEW_TAP' to bridge '$BRIDGE_NAME'."
    exit 1
  fi
  log "TAP '$NEW_TAP' added to bridge '$BRIDGE_NAME'."

  log "Added network interface TAP '$NEW_TAP' (MAC: $NEW_MAC) on bridge '$BRIDGE_NAME' to VM '$VMNAME'."
  display_and_log "INFO" "Network interface added to VM '$VMNAME'. Please restart the VM for changes to take effect."
}

# === Subcommand: network remove ===
cmd_network_remove() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    cmd_network_remove_usage
    exit 1
  fi

  VMNAME="$1"
  TAP_TO_REMOVE="$2"

  load_vm_config "$VMNAME"

  # === Check if VM is running ===
  if ps -ax | grep -v grep | grep -c "[b]hyve .* -s .* $VMNAME$" > /dev/null; then
    display_and_log "ERROR" "VM '$VMNAME' is currently running. Please stop the VM before removing a network interface."
    exit 1
  fi

  local CONF_FILE="$VM_DIR/vm.conf"
  local FOUND_NIC_IDX=-1
  local NIC_COUNT=0
  local CURRENT_BRIDGE_OF_TAP_TO_REMOVE=""

  # === Find the index and bridge of the NIC to remove ===
  local NIC_IDX=0
  while true; do
    local CURRENT_TAP_VAR="TAP_${NIC_IDX}"
    local CURRENT_MAC_VAR="MAC_${NIC_IDX}"
    local CURRENT_BRIDGE_VAR="BRIDGE_${NIC_IDX}"

    local CURRENT_TAP="${!CURRENT_TAP_VAR}"
    local CURRENT_MAC="${!CURRENT_MAC_VAR}"
    local CURRENT_BRIDGE="${!CURRENT_BRIDGE_VAR}"

    if [ -z "$CURRENT_TAP" ]; then
      break
    fi
    if [ "$CURRENT_TAP" = "$TAP_TO_REMOVE" ]; then
      FOUND_NIC_IDX=$NIC_IDX
      CURRENT_BRIDGE_OF_TAP_TO_REMOVE="$CURRENT_BRIDGE"
    fi
    NIC_COUNT=$((NIC_COUNT + 1))
    NIC_IDX=$((NIC_IDX + 1))
  done

  if [ "$FOUND_NIC_IDX" -eq -1 ]; then
    display_and_log "ERROR" "Network interface '$TAP_TO_REMOVE' not found for VM '$VMNAME'."
    exit 1
  fi

  # === Remove the lines from vm.conf ===
  sed -i '' "/^TAP_${FOUND_NIC_IDX}=/d" "$CONF_FILE"
  sed -i '' "/^MAC_${FOUND_NIC_IDX}=/d" "$CONF_FILE"
  sed -i '' "/^BRIDGE_${FOUND_NIC_IDX}=/d" "$CONF_FILE"

  # === Remove TAP from bridge and destroy TAP interface immediately ===
  if [ -n "$CURRENT_BRIDGE_OF_TAP_TO_REMOVE" ] && ifconfig "$CURRENT_BRIDGE_OF_TAP_TO_REMOVE" | grep -qw "$TAP_TO_REMOVE"; then
    log "Removing TAP '$TAP_TO_REMOVE' from bridge '$CURRENT_BRIDGE_OF_TAP_TO_REMOVE'..."
    ifconfig "$CURRENT_BRIDGE_OF_TAP_TO_REMOVE" deletem "$TAP_TO_REMOVE"
  fi

  if ifconfig "$TAP_TO_REMOVE" > /dev/null 2>&1; then
    log "Destroying TAP interface '$TAP_TO_REMOVE'..."
    ifconfig "$TAP_TO_REMOVE" destroy
  fi

  # === Re-index remaining NICs if necessary ===
  if [ "$FOUND_NIC_IDX" -lt "$((NIC_COUNT - 1))" ]; then
    log "Re-indexing network interfaces..."
    for (( i = FOUND_NIC_IDX; i < NIC_COUNT - 1; i++ )); do
      local NEXT_NIC_IDX=$((i + 1))

      local OLD_TAP_VAL=$(grep "^TAP_${NEXT_NIC_IDX}=" "$CONF_FILE" | cut -d'=' -f2)
      local OLD_MAC_VAL=$(grep "^MAC_${NEXT_NIC_IDX}=" "$CONF_FILE" | cut -d'=' -f2)
      local OLD_BRIDGE_VAL=$(grep "^BRIDGE_${NEXT_NIC_IDX}=" "$CONF_FILE" | cut -d'=' -f2)

      sed -i '' "s/^TAP_${NEXT_NIC_IDX}=.*/TAP_${i}=${OLD_TAP_VAL}/" "$CONF_FILE"
      sed -i '' "s/^MAC_${NEXT_NIC_IDX}=.*/MAC_${i}=${OLD_MAC_VAL}/" "$CONF_FILE"
      sed -i '' "s/^BRIDGE_${NEXT_NIC_IDX}=.*/BRIDGE_${i}=${OLD_BRIDGE_VAL}/" "$CONF_FILE"
    done
    # Remove the last (now duplicate) entries
    sed -i '' "/^TAP_${NIC_COUNT-1}=/d" "$CONF_FILE"
    sed -i '' "/^MAC_${NIC_COUNT-1}=/d" "$CONF_FILE"
    sed -i '' "/^BRIDGE_${NIC_COUNT-1}=/d" "$CONF_FILE"
  fi

  log "Removed network interface '$TAP_TO_REMOVE' from VM '$VMNAME'."
  display_and_log "INFO" "Network interface removed from VM '$VMNAME'. Please restart the VM for changes to take effect."
}

# === Main Logic ===
check_root
check_kld vmm
check_kld nmdm

check_initialization "$1"
load_config

case "$1" in
  init)
    cmd_init
    exit 0
    ;;
  switch)
    shift
    cmd_switch "$@"
    exit 0
    ;;
  --version)
    echo_message "bhyve-cli.sh version $VERSION"
    exit 0
    ;;
  --help)
    main_usage
    exit 0
    ;;
  create)
    shift
    cmd_create "$@"
    ;;
  delete)
    shift
    cmd_delete "$@"
    ;;
  install)
    shift
    cmd_install "$@"
    ;;
  start)
    shift
    cmd_start "$@"
    ;;
  stop)
    shift
    cmd_stop "$@"
    ;;
  console)
    shift
    cmd_console "$@"
    ;;
  logs)
    shift
    cmd_logs "$@"
    ;;
  status)
    shift
    cmd_status "$@"
    ;;
  autostart)
    shift
    cmd_autostart "$@"
    ;;
  modify)
    shift
    cmd_modify "$@"
    ;;
  clone)
    shift
    cmd_clone "$@"
    ;;
  info)
    shift
    cmd_info "$@"
    ;;
  resize-disk)
    shift
    cmd_resize_disk "$@"
    ;;
  export)
    shift
    cmd_export "$@"
    ;;
  import)
    shift
    cmd_import "$@"
    ;;
  iso)
    shift
    cmd_iso "$@"
    ;;
  restart)
    shift
    cmd_restart "$@"
    ;;
  network)
    shift
    case "$1" in
      add)
        shift
        cmd_network_add "$@"
        ;;
      remove)
        shift
        cmd_network_remove "$@"
        ;;
      *)
        if [ -n "$1" ]; then
        display_and_log "ERROR" "Invalid subcommand for 'network': $1"
    fi
        cmd_network_usage
        exit 1
        ;;
    esac
    ;;
  switch)
    shift
    case "$1" in
      add)
        shift
        cmd_switch_add "$@"
        ;;
      list)
        shift
        cmd_switch_list "$@"
        ;;
      destroy)
        shift
        cmd_switch_destroy "$@"
        ;;
      delete)
        shift
        cmd_switch_delete "$@"
        ;;
      --help)
        cmd_switch_usage
        exit 0
        ;;
      *)
        if [ -n "$1" ]; then
            display_and_log "ERROR" "Invalid subcommand for 'switch': $1"
        fi
        cmd_switch_usage
        exit 1
        ;;
    esac
    ;;
  *)
    if [ -n "$1" ]; then
      echo_message " "
      echo_message "Error: Invalid command: $1"
      echo_message " "
    fi
    main_usage
    exit 1
    ;;
esac
