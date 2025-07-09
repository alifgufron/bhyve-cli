#!/usr/local/bin/bash

# === Pastikan script dijalankan dengan Bash ===
if [ -z "$BASH_VERSION" ]; then
  echo_message "[ERROR] This script requires Bash to run. Please execute with 'bash <script_name>' or ensure your shell is Bash."
  exit 1
fi

# === Variabel dasar global ===
BASEPATH="/home/admin/vm-bhvye"
ISO_DIR="$BASEPATH/iso"
VERSION="1.0.0"
#BRIDGE="bridge100"

# === Fungsi log dengan timestamp ===
log() {
  # Log messages will always be written to the VM's specific log file with a timestamp.
  if [ -n "$LOG_FILE" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
  else
    # Fallback to stderr if LOG_FILE is not set, still with timestamp for consistency in 'log' function
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >&2
  fi
}

# === Function to echo messages to console without timestamp ===
echo_message() {
  echo -e "$1" >&2
}

# === Fungsi untuk memuat konfigurasi VM ===
load_vm_config() {
  VMNAME="$1"
  VM_DIR="$BASEPATH/vm/$VMNAME"
  CONF_FILE="$VM_DIR/vm.conf"

  if [ ! -f "$CONF_FILE" ]; then
    echo_message "[ERROR] VM configuration '$VMNAME' not found: $CONF_FILE"
    exit 1
  fi
  . "$CONF_FILE"
  LOG_FILE="$VM_DIR/vm.log" # Set LOG_FILE after loading config
}

# === Main usage function ===
main_usage() {
  echo_message "Usage: $0 <command> [options/arguments]"
  echo_message " "
  echo_message "Available Commands:"
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
  echo_message "  network       - Manage network interfaces for a VM."
  echo_message "  status        - Show the status of all virtual machines."
  echo_message "  switch        - Manage network bridges and physical interfaces."
  echo_message " "
  echo_message "For detailed usage of each command, use: $0 <command> --help"
}

# === Usage functions for all commands ===
# === Usage function for switch add ===
cmd_switch_add_usage() {
  echo_message "Usage: $0 switch add --name <bridge_name> --interface <physical_interface> [--vlan <vlan_tag>]"
  echo_message "\nOption:"
  echo_message "  --name <bridge_name>         - Name of the bridge or vSwitch."
  echo_message "  --interface <physical_interface> - Parent physical network interface (e.g., em0, igb1)."
  echo_message "  --vlan <vlan_tag>            - Optional. VLAN ID if the parent interface is in trunk mode. A VLAN interface (e.g., vlan100) will be created on top of the physical interface"
  echo_message "  and tagged to the bridge."
}

# === Usage function for switch remove ===
cmd_switch_remove_usage() {
  echo_message "Usage: $0 switch remove --name <bridge_name> --interface <physical_interface> [--vlan <vlan_tag>]"
  echo_message "\nOption:"
  echo_message "  --name <bridge_name>         - Name of the bridge or vSwitch."
  echo_message "  --interface <physical_interface> - Physical network interface to remove."
  echo_message "  --vlan <vlan_tag>            - Optional. VLAN ID if the interface to be removed is a VLAN interface. The corresponding VLAN interface (e.g., vlan100) will also be destroyed."
}

# === Usage function for switch ===
cmd_switch_usage() {
  echo_message "Usage: $0 switch [subcommand] [Option] [Arguments]"
  echo_message "\nSubcommands:\n  add    - Create a bridge and add a physical interface\n  list   - List all bridge interfaces and their members\n  remove - Remove a physical interface from a bridge"
}

# === Usage function for create ===
cmd_create_usage() {
  echo_message "Usage: $0 create <vmname> <disksize in GB> <bridge_name>"
  echo_message "Example:\n  $0 create vm-bsd 40 bridge100"
}

# === Usage function for delete ===
cmd_delete_usage() {
  echo_message "Usage: $0 delete <vmname>"
}

# === Usage function for install ===
cmd_install_usage() {
  echo_message "Usage: $0 install <vmname>"
}

# === Usage function for start ===
cmd_start_usage() {
  echo_message "Usage: $0 start <vmname>"
}

# === Usage function for stop ===
cmd_stop_usage() {
  echo_message "Usage: $0 stop <vmname>"
}

# === Usage function for console ===
cmd_console_usage() {
  echo_message "Usage: $0 console <vmname>"
}

# === Usage function for logs ===
cmd_logs_usage() {
  echo_message "Usage: $0 logs <vmname>"
}

# === Usage function for autostart ===
cmd_autostart_usage() {
  echo_message "Usage: $0 autostart <vmname> <enable|disable>"
}

# === Usage function for info ===
cmd_info_usage() {
  echo_message "Usage: $0 info <vmname>"
}

# === Usage function for modify ===
cmd_modify_usage() {
  echo_message "Usage: $0 modify <vmname> [--cpu <num>] [--ram <size>] [--nic <index> --tap <tap_name> --mac <mac_address> --bridge <bridge_name>]"
  echo_message "Example:\n  $0 modify myvm --cpu 4 --ram 4096M\n  $0 modify myvm --nic 0 --tap tap1 --bridge bridge1"
}

# === Usage function for clone ===
cmd_clone_usage() {
  echo_message "Usage: $0 clone <source_vmname> <new_vmname>"
  echo_message "Example:\n  $0 clone myvm newvm"
}

# === Usage function for resize-disk ===
cmd_resize_disk_usage() {
  echo_message "Usage: $0 resize-disk <vmname> <new_size_in_GB>"
  echo_message "Example:\n  $0 resize-disk myvm 60"
}

# === Usage function for export ===
cmd_export_usage() {
  echo_message "Usage: $0 export <vmname> <destination_path>"
  echo_message "Example:\n  $0 export myvm /tmp/myvm_backup.tar.gz"
}

# === Usage function for import ===
cmd_import_usage() {
  echo_message "Usage: $0 import <path_to_vm_archive>"
  echo_message "Example:\n  $0 import /tmp/myvm_backup.tar.gz"
}

# === Usage function for network ===
cmd_network_usage() {
  echo_message "Usage: $0 network [subcommand] [arguments]"
  echo_message "\nSubcommands:"
  echo_message "  add    - Add a network interface to a VM."
  echo_message "  remove - Remove a network interface from a VM."
  echo_message "\nFor detailed usage of each subcommand, use: $0 network <subcommand> --help"
}

# === Usage function for network add ===
cmd_network_add_usage() {
  echo_message "Usage: $0 network add --vm <vmname> --switch <bridge_name> [--mac <mac_address>]"
  echo_message "
  Note: A unique TAP interface (e.g., tap0, tap1) will be automatically assigned."
  echo_message "
Example:"
  echo_message "  $0 network add --vm myvm --switch bridge1"
  echo_message "  $0 network add --vm myvm --switch bridge2 --mac 58:9c:fc:00:00:01"
  echo_message "
Options:"
  echo_message "  --vm     - name vm"
  echo_message "  --switch - name switch"
  echo_message "  --mac    - MAC address (optional)"
}

# === Usage function for network remove ===
cmd_network_remove_usage() {
  echo_message "Usage: $0 network remove <vmname> <tap_name>"
  echo_message "Example:\n  $0 network remove myvm tap0"
}


cmd_switch_add() {
  local BRIDGE_NAME=""
  local PHYS_IF=""
  local VLAN_TAG=""

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
      *)
        echo_message "[ERROR] Invalid option: $1"
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

  log "Checking physical interface '$PHYS_IF'..."
  if ! ifconfig "$PHYS_IF" > /dev/null 2>&1; then
    echo_message "[ERROR] Physical interface '$PHYS_IF' not found."
    exit 1
  fi

  MEMBER_IF="$PHYS_IF"
  if [ -n "$VLAN_TAG" ]; then
    VLAN_IF="vlan${VLAN_TAG}"
    log "Creating VLAN interface '$VLAN_IF'..."
    ifconfig "$VLAN_IF" create
    if [ $? -ne 0 ]; then
      echo_message "[ERROR] Failed to create VLAN interface '$VLAN_IF'."
      exit 1
    fi
    log "Configuring '$VLAN_IF' with tag '$VLAN_TAG' on top of '$PHYS_IF'..."
    ifconfig "$VLAN_IF" vlan "$VLAN_TAG" vlandev "$PHYS_IF"
    if [ $? -ne 0 ]; then
      echo_message "[ERROR] Failed to configure VLAN interface '$VLAN_IF'."
      exit 1
    fi
    log "VLAN interface '$VLAN_IF' successfully configured."
    MEMBER_IF="$VLAN_IF"
  fi

  log "Checking bridge '$BRIDGE_NAME'..."
  if ! ifconfig "$BRIDGE_NAME" > /dev/null 2>&1; then
    log "Bridge interface '$BRIDGE_NAME' does not exist. Creating..."
    ifconfig bridge create name "$BRIDGE_NAME"
    if [ $? -ne 0 ]; then
      echo_message "[ERROR] Failed to create bridge '$BRIDGE_NAME'."
      exit 1
    fi
    log "Bridge interface '$BRIDGE_NAME' successfully created."
  else
    log "Bridge interface '$BRIDGE_NAME' already exists."
  fi

  log "Adding '$MEMBER_IF' to bridge '$BRIDGE_NAME'..."
  ifconfig "$BRIDGE_NAME" addm "$MEMBER_IF"
  if [ $? -ne 0 ]; then
    echo_message "[ERROR] Failed to add '$MEMBER_IF' to bridge '$BRIDGE_NAME'."
    exit 1
  fi
  log "Interface '$MEMBER_IF' successfully added to bridge '$BRIDGE_NAME'."
  echo_message "Bridge '$BRIDGE_NAME' now has member '$MEMBER_IF'."
}







# === Subcommand: switch list ===
cmd_switch_list() {
  echo_message "List of Bridge Interfaces:"
  BRIDGES=$(ifconfig -l | tr ' ' '\n' | grep '^bridge')

  if [ -z "$BRIDGES" ]; then
    echo_message "No bridge interfaces found."
    return
  fi

  for BRIDGE_IF in $BRIDGES; do
    echo_message "----------------------------------------"
    echo_message "Bridge: $BRIDGE_IF"
    MEMBERS=$(ifconfig "$BRIDGE_IF" | grep 'member:' | awk '{print $2}')
    if [ -n "$MEMBERS" ]; then
      echo_message "  Members:"
      for MEMBER in $MEMBERS; do
        echo_message "    - $MEMBER"
      done
    else
      echo_message "  No members."
    fi
  done
  echo_message "----------------------------------------"
}

# === Subcommand: switch remove ===
cmd_switch_remove() {
  local BRIDGE_NAME=""
  local PHYS_IF=""
  local VLAN_TAG=""

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
      *)
        echo_message "[ERROR] Invalid option: $1" >&2
        cmd_switch_remove_usage
        exit 1
        ;;
    esac
    shift
  done

  # Validate required arguments
  if [ -z "$BRIDGE_NAME" ] || [ -z "$PHYS_IF" ]; then
    cmd_switch_remove_usage
    exit 1
  fi

  log "Checking bridge '$BRIDGE_NAME'..."
  if ! ifconfig "$BRIDGE_NAME" > /dev/null 2>&1; then
    echo_message "[ERROR] Bridge '$BRIDGE_NAME' not found."
    exit 1
  fi

  MEMBER_IF="$PHYS_IF"
  if [ -n "$VLAN_TAG" ]; then
    MEMBER_IF="vlan${VLAN_TAG}"
  fi

  log "Checking if '$MEMBER_IF' is a member of '$BRIDGE_NAME'..."
  if ! ifconfig "$BRIDGE_NAME" | grep -qw "$MEMBER_IF"; then
    echo_message "[ERROR] Interface '$MEMBER_IF' is not a member of bridge '$BRIDGE_NAME'."
    exit 1
  fi

  log "Removing '$MEMBER_IF' from bridge '$BRIDGE_NAME'..."
  ifconfig "$BRIDGE_NAME" deletem "$MEMBER_IF"
  if [ $? -ne 0 ]; then
    echo_message "[ERROR] Failed to remove '$MEMBER_IF' from bridge '$BRIDGE_NAME'."
    exit 1
  fi
  log "Interface '$MEMBER_IF' successfully removed from bridge '$BRIDGE_NAME'."

  if [ -n "$VLAN_TAG" ]; then
    log "Destroying VLAN interface '$MEMBER_IF'..."
    ifconfig "$MEMBER_IF" destroy
    if [ $? -ne 0 ]; then
      echo_message "[ERROR] Failed to destroy VLAN interface '$MEMBER_IF'."
      exit 1
    fi
    log "VLAN interface '$MEMBER_IF' successfully destroyed."
  fi

  # Check if bridge is empty after removal
  MEMBERS=$(ifconfig "$BRIDGE_NAME" | grep 'member:' | awk '{print $2}')
  if [ -z "$MEMBERS" ]; then
    read -rp "Bridge '$BRIDGE_NAME' is now empty. Destroy this bridge as well? (y/n): " CONFIRM_DESTROY
    if [[ "$CONFIRM_DESTROY" =~ ^[Yy]$ ]]; then
      log "Destroying bridge '$BRIDGE_NAME'..."
      ifconfig "$BRIDGE_NAME" destroy
      if [ $? -ne 0 ]; then
        echo_message "[ERROR] Failed to destroy bridge '$BRIDGE_NAME'."
        exit 1
      fi
      log "Bridge '$BRIDGE_NAME' successfully destroyed."
    else
      log "Bridge '$BRIDGE_NAME' not destroyed."
    fi
  else
    echo_message "Bridge '$BRIDGE_NAME' still has members."
  fi
}











# === Subcommand: create ===
cmd_create() {
  if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    cmd_create_usage
    exit 1
  fi

  VMNAME="$1"
  DISKSIZE="$2"
  VM_BRIDGE="$3"
  VM_DIR="$BASEPATH/vm/$VMNAME"
  CONF="$VM_DIR/vm.conf"

  mkdir -p "$VM_DIR"
  LOG_FILE="$VM_DIR/vm.log" # Set LOG_FILE for create command

  log "Creating VM $VMNAME in $VM_DIR"

  # === Check and create bridge interface if it doesn't exist ===
  if ! ifconfig "$VM_BRIDGE" > /dev/null 2>&1; then
    log "Bridge interface '$VM_BRIDGE' does not exist. Creating..."
    ifconfig bridge create name "$VM_BRIDGE"
    log "Bridge interface '$VM_BRIDGE' successfully created."
  else
    log "Bridge interface '$VM_BRIDGE' already exists."
  fi

  # === Create disk image ===
  truncate -s "${DISKSIZE}G" "$VM_DIR/disk.img"
  log "Disk ${DISKSIZE} GB created: $VM_DIR/disk.img"

  # === Generate unique UUID ===
  UUID=$(uuidgen)

  # === Generate unique MAC address (static prefix, random suffix) ===
  MAC_0="58:9c:fc$(jot -r -w ":%02x" -s "" 3 0 255)"

  # === Safely detect next available TAP & create TAP ===
  NEXT_TAP_NUM=0
  while ifconfig | grep -q "^tap${NEXT_TAP_NUM}:"; do
    NEXT_TAP_NUM=$((NEXT_TAP_NUM + 1))
  done
  TAP_0="tap${NEXT_TAP_NUM}"

  # === Create TAP interface
  ifconfig "$TAP_0" create
  log "TAP interface '$TAP_0' successfully created"

  # === Add TAP description according to VM name
  ifconfig "$TAP_0" description "vmnet/${VMNAME}/0/${VM_BRIDGE}"
  log "TAP description '$TAP_0' set: VM: vmnet/${VMNAME}/0/${VM_BRIDGE}"

  # === Activate TAP
  ifconfig "$TAP_0" up
  log "TAP '$TAP_0' activated"

  # === Add TAP to bridge
  ifconfig "$VM_BRIDGE" addm "$TAP_0"
  log "TAP '$TAP_0' added to bridge '$VM_BRIDGE'"

  # === Generate unique console name ===
  CONSOLE="nmdm-${VMNAME}.1"
  log "Console device: $CONSOLE"

  # === Create configuration file ===
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
EOF

  log "Configuration file created: $CONF"
  log "VM '$VMNAME' successfully created"
  echo_message "Please continue by running: $0 install $VMNAME"
}

# === Subcommand: delete ===
cmd_delete() {
  if [ -z "$1" ]; then
    cmd_delete_usage
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  log "Deleting VM '$VMNAME'..."

  # === Stop bhyve if still running ===
  if pgrep -f "bhyve.*$VMNAME" > /dev/null; then
    log "VM is still running. Stopping bhyve process..."
    pkill -f "bhyve.*$VMNAME"
    sleep 1
  fi

  # === Destroy from kernel memory ===
  if bhyvectl --vm="$VMNAME" --destroy > /dev/null 2>&1; then
    log "VM destroyed from kernel memory."
  fi

  # === Remove all TAPs from bridge and destroy TAP interfaces ===
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
    fi

    if ifconfig "$CURRENT_TAP" > /dev/null 2>&1; then
      log "Destroying TAP interface '$CURRENT_TAP'..."
      ifconfig "$CURRENT_TAP" destroy
    fi
    NIC_IDX=$((NIC_IDX + 1))
  done

  # === Delete VM directory ===
  log "Deleting VM directory: $VM_DIR"
  rm -rf "$VM_DIR"

  echo_message "VM '$VMNAME' successfully deleted."
}

# === Subcommand: install ===
cmd_install() {
  if [ -z "$1" ]; then
    cmd_install_usage
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  log "Starting VM '$VMNAME' installation..."

  # === Stop bhyve if still active ===
  if pgrep -f "bhyve.*$VMNAME" > /dev/null; then
    log "VM '$VMNAME' is still running. Stopped..."
    pkill -f "bhyve.*$VMNAME"
    sleep 1
  fi

  # === Destroy if still remaining in kernel ===
  if bhyvectl --vm="$VMNAME" --destroy > /dev/null 2>&1; then
    log "VM '$VMNAME' was still in memory. Destroyed."
  fi

  # === Select ISO source ===
  echo_message ""
  echo_message "Select ISO source:"
  echo_message "1. Choose existing ISO"
  echo_message "2. Download ISO from URL"
  read -rp "Choice [1/2]: " CHOICE

  case "$CHOICE" in
    1)
      log "Searching for ISO files in $ISO_DIR..."
      ISO_LIST=($(find "$ISO_DIR" -type f -name "*.iso" 2>/dev/null))
      if [ ${#ISO_LIST[@]} -eq 0 ]; then
        echo_message "[WARNING] No ISO files found in $ISO_DIR!"
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
        echo_message "[ERROR] Failed to download ISO"
        exit 1
      }
      ;;
    *)
      echo_message "[ERROR] Invalid choice"
      exit 1
      ;;
  esac

  # === Select UEFI firmware ===
  if [ -f /usr/local/share/uefi-firmware/BHYVE_UEFI.fd ]; then
    LOADER="-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd"
    log "Using UEFI firmware: BHYVE_UEFI.fd"
  else
    LOADER=""
    log "UEFI firmware not found, running without bootrom"
  fi

  # === Run bhyve in background ===
  log "Running bhyve installer in background..."
  bhyve \
    -c "$CPUS" \
    -m "$MEMORY" \
    -AHP \
    -s 0,hostbridge \
    -s 3:0,virtio-blk,"$VM_DIR/$DISK" \
    -s 4:0,ahci-cd,"$ISO_PATH" \
    -s 5:0,virtio-net,"$TAP" \
    -l com1,/dev/"${CONSOLE}A" \
    -s 31,lpc \
    $LOADER \
    "$VMNAME" >> "$LOG_FILE" 2>&1 &

  VM_PID=$!
  log "Bhyve VM started in background with PID $VM_PID"

  # === Waiting for nmdmB device to appear ===
  for i in $(seq 1 10); do
    if [ -e "/dev/${CONSOLE}B" ]; then
      break
    fi
    sleep 0.5
  done

  # === CTRL+C Handler ===
  cleanup() {
    echo_message ""
    echo_message "[INFO] SIGINT received, Force stopping vm-bhyve (PID $VM_PID)..."
    kill "$VM_PID"

    sleep 1
    if ps -p "$VM_PID" > /dev/null 2>&1; then
     log "PID $VM_PID still running, Forcing KILL..."
     kill -9 "$VM_PID"
     sleep 1
    fi

    wait "$VM_PID"
    log "Installer for $VMNAME forced stop by user."
    exit 0
  }
  trap cleanup INT

  # === Automatic console ===
  echo_message ""
  echo_message ">>> Entering VM '$VMNAME' console (exit with ~.)"
  cu -l /dev/"${CONSOLE}B"

  # === Wait for bhyve to finish ===
  wait "$VM_PID" # Changed from BHYVE_PID to VM_PID
  log "Installer for $VMNAME has stopped (exit)"

  echo_message ""
  echo_message "Installer finished. If OS installation was successful, start the VM with:"
  echo_message "  $0 start $VMNAME"
}

# === Subcommand: start ===
cmd_start() {
  if [ -z "$1" ]; then
    cmd_start_usage
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  log "Preparing Config for $VMNAME"

  # ==== Check if bhyve is still running
  if pgrep -f "bhyve.*$VMNAME" > /dev/null; then
    log "VM '$VMNAME' is still running. Stopping..."
    pkill -f "bhyve.*$VMNAME"
    sleep 1
  fi

  # === Destroy VM if still remaining in kernel
  if bhyvectl --vm="$VMNAME" --destroy > /dev/null 2>&1; then
    log "VM '$VMNAME' was still in memory. Stopped."
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

    # === Create TAP interface if it doesn't exist
    if ! ifconfig "$CURRENT_TAP" > /dev/null 2>&1; then
      log "TAP '$CURRENT_TAP' does not exist. Creating..."
      ifconfig "$CURRENT_TAP" create description "vm-$VMNAME-nic${NIC_IDX}"
      ifconfig "$CURRENT_TAP" up
      log "TAP '$CURRENT_TAP' created and activated."
    else
      ifconfig "$CURRENT_TAP" up
      log "TAP '$CURRENT_TAP' already exists and activated."
    fi

    # === Add to bridge if not already a member
    if ! ifconfig "$CURRENT_BRIDGE" > /dev/null 2>&1; then
      log "Bridge interface '$CURRENT_BRIDGE' does not exist. Creating..."
      ifconfig bridge create name "$CURRENT_BRIDGE"
      log "Bridge interface '$CURRENT_BRIDGE' successfully created."
    else
      log "Bridge interface '$CURRENT_BRIDGE' already exists."
    fi

    if ! ifconfig "$CURRENT_BRIDGE" | grep -qw "$CURRENT_TAP"; then
      ifconfig "$CURRENT_BRIDGE" addm "$CURRENT_TAP"
      log "TAP '$CURRENT_TAP' added to bridge '$CURRENT_BRIDGE'"
    else
      log "TAP '$CURRENT_TAP' already connected to bridge '$CURRENT_BRIDGE'"
    fi

    NETWORK_ARGS+=" -s ${DEV_NUM}:0,virtio-net,\"$CURRENT_TAP\""
    DEV_NUM=$((DEV_NUM + 1))
    NIC_IDX=$((NIC_IDX + 1))
  done

  # === Ensure nmdm device is available
  if ! [ -e "/dev/${CONSOLE}A" ] && ! [ -e "/dev/${CONSOLE}B" ]; then
    log "Creating device /dev/${CONSOLE}A and /dev/${CONSOLE}B"
    mdm_number="${CONSOLE##*.}"
    mdm_base="${CONSOLE%%.*}"
    mdm_device="/dev/${mdm_base}.${mdm_number}"
    true > "${mdm_device}A"
    true > "${mdm_device}B"
  fi

  # === Select UEFI firmware ===
  if [ -f /usr/local/share/uefi-firmware/BHYVE_UEFI.fd ]; then
    LOADER="-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd"
    log "Using UEFI firmware: BHYVE_UEFI.fd"
  else
    LOADER=""
    log "UEFI firmware not found, running without bootrom"
  fi

  # Run bhyve
  log "Starting VM '$VMNAME'..."

  bhyve \
    -c "$CPUS" \
    -m "$MEMORY" \
    -AHP \
    -s 0,hostbridge \
    -s 3:0,virtio-blk,"$VM_DIR/$DISK" \
    $NETWORK_ARGS \
    -l com1,/dev/"${CONSOLE}A" \
    -s 31,lpc \
     $LOADER \
    "$VMNAME" >> "$LOG_FILE" 2>&1 &

  BHYVE_PID=$!

  # Wait a moment
  sleep 1

  if ps -p "$BHYVE_PID" > /dev/null 2>&1; then
    log "VM '$VMNAME' is running with PID $BHYVE_PID"
  else
    log "Failed to start VM '$VMNAME' (PID not found)"
  fi
}

# === Subcommand: stop ===
cmd_stop() {
  if [ -z "$1" ]; then
    cmd_stop_usage
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  log "Stopping VM '$VMNAME'..."

  # === Check PID of active process
  VM_PID=$(pgrep -f "bhyve.*$VMNAME")

  if [ -z "$VM_PID" ]; then
    log "VM '$VMNAME' is not running."
    exit 0
  fi

  # === Send TERM signal to bhyve
  log "Sending TERM signal to PID $VM_PID"
  kill "$VM_PID"

  # === Wait for bhyve process to stop
  sleep 1
  if ps -p "$VM_PID" > /dev/null 2>&1; then
    log "PID $VM_PID is still running, Forcing KILL..."
    kill -9 "$VM_PID"
    sleep 1
  fi

  log "VM '$VMNAME' successfully stopped."
}







# === Usage function for info ===
cmd_info_usage() {
  echo_message "Usage: $0 info <vmname>"
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
    echo_message "[ERROR] Console device '$DEVICE_B' not found."
    echo_message "Ensure the VM has been run at least once, or the device has been created."
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
    echo_message "[ERROR] Log file for VM '$VMNAME' not found: $LOG_FILE"
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
  
  # Generate dynamic separator line
  header_line=$(printf "$header_format" \
    "--------------------" \
    "----------" \
    "------------" \
    "------------" \
    "------------" \
    "------------" \
    "----------")
  echo_message "${header_line// /}" # Remove spaces to make it a continuous line

  for VMCONF in "$BASEPATH"/vm/*/vm.conf; do
    [ -f "$VMCONF" ] || continue
    . "$VMCONF"

    local VMNAME="${VMNAME:-N/A}"
    local CPUS="${CPUS:-N/A}"
    local MEMORY="${MEMORY:-N/A}"

    local ALL_TAPS=""
    local ALL_MACS=""
    local ALL_BRIDGES=""
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

      if [ -n "$ALL_TAPS" ]; then
        ALL_TAPS+=","
        ALL_MACS+=","
        ALL_BRIDGES+=","
      fi
      ALL_TAPS+="$CURRENT_TAP"
      ALL_MACS+="$CURRENT_MAC"
      ALL_BRIDGES+="$CURRENT_BRIDGE"
      NIC_IDX=$((NIC_IDX + 1))
    done

    local PID=$(pgrep -f "bhyve.*$VMNAME")
    local CPU_USAGE="N/A"
    local RAM_USAGE="N/A"

    if [ -n "$PID" ]; then
      local STATUS="RUNNING"
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
    else
      local STATUS="STOPPED"
      local PID="-"
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
    log "Autostart enabled for VM '$VMNAME'."
  elif [ "$ACTION" = "disable" ]; then
    log "Disabling autostart for VM '$VMNAME'..."
    sed -i '' 's/^AUTOSTART=.*/AUTOSTART=no/' "$CONF_FILE"
    log "Autostart disabled for VM '$VMNAME'."
  fi
}





# === Usage function for info ===
cmd_info_usage() {
  echo_message "Usage: $0 info <vmname>"
}

# === Subcommand: modify ===
cmd_modify() {
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

  # Check if VM is running
  if pgrep -f "bhyve.*$VMNAME" > /dev/null; then
    echo_message "[ERROR] VM '$VMNAME' is currently running. Please stop the VM before modifying its configuration."
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
          echo_message "[ERROR] Invalid NIC index: $NIC_TO_MODIFY. Must be a number."
          exit 1
        fi
        ;;
      --tap)
        shift
        TAP_NEW="$1"
        log "Setting TAP for NIC ${NIC_TO_MODIFY} to $TAP_NEW for VM '$VMNAME'."
        sed -i '' "s/^TAP_${NIC_TO_MODIFY}=.*/TAP_${NIC_TO_MODIFY}=$TAP_NEW/" "$CONF_FILE"
        ;;
      --mac)
        shift
        MAC_NEW="$1"
        log "Setting MAC for NIC ${NIC_TO_MODIFY} to $MAC_NEW for VM '$VMNAME'."
        sed -i '' "s/^MAC_${NIC_TO_MODIFY}=.*/MAC_${NIC_TO_MODIFY}=$MAC_NEW/" "$CONF_FILE"
        ;;
      --bridge)
        shift
        BRIDGE_NEW="$1"
        log "Setting BRIDGE for NIC ${NIC_TO_MODIFY} to $BRIDGE_NEW for VM '$VMNAME'."
        sed -i '' "s/^BRIDGE_${NIC_TO_MODIFY}=.*/BRIDGE_${NIC_TO_MODIFY}=$BRIDGE_NEW/" "$CONF_FILE"
        ;;
      *)
        echo_message "[ERROR] Invalid option: $1"
        echo_message "Usage: $0 modify <vmname> [--cpu <num>] [--ram <size>] [--nic <index> --tap <tap_name> --mac <mac_address> --bridge <bridge_name>]"
        exit 1
        ;;
    esac
    shift
  done

  log "VM '$VMNAME' configuration updated."
}

# === Subcommand: clone ===
cmd_clone() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    cmd_clone_usage
    exit 1
  fi

  SOURCE_VMNAME="$1"
  NEW_VMNAME="$2"

  SOURCE_VM_DIR="$BASEPATH/vm/$SOURCE_VMNAME"
  NEW_VM_DIR="$BASEPATH/vm/$NEW_VMNAME"

  # Check if source VM exists
  if [ ! -d "$SOURCE_VM_DIR" ]; then
    echo_message "[ERROR] Source VM '$SOURCE_VMNAME' not found: $SOURCE_VM_DIR"
    exit 1
  fi

  # Check if new VM already exists
  if [ -d "$NEW_VM_DIR" ]; then
    echo_message "[ERROR] Destination VM '$NEW_VM_NAME' already exists: $NEW_VM_DIR"
    exit 1
  fi

  # Load source VM config to get its status
  load_vm_config "$SOURCE_VMNAME"

  # Check if source VM is running
  if pgrep -f "bhyve.*$SOURCE_VMNAME" > /dev/null; then
    echo_message "[ERROR] Source VM '$SOURCE_VMNAME' is currently running. Please stop the VM before cloning."
    exit 1
  fi

  log "Cloning VM '$SOURCE_VMNAME' to '$NEW_VMNAME'..."

  # Create new VM directory
  mkdir -p "$NEW_VM_DIR"
  log "Created new VM directory: $NEW_VM_DIR"

  # Copy disk image
  log "Copying disk image from $SOURCE_VM_DIR/disk.img to $NEW_VM_DIR/disk.img..."
  cp "$SOURCE_VM_DIR/disk.img" "$NEW_VM_DIR/disk.img"
  if [ $? -ne 0 ]; then
    echo_message "[ERROR] Failed to copy disk image."
    rm -rf "$NEW_VM_DIR"
    exit 1
  fi
  log "Disk image copied."

  # Generate new UUID, MAC, TAP, CONSOLE
  NEW_UUID=$(uuidgen)
  NEW_MAC="58:9c:fc$(jot -r -w ":%02x" -s "" 3 0 255)"
  
  NEXT_TAP_NUM=0
  while ifconfig | grep -q "^tap${NEXT_TAP_NUM}:"; do
    NEXT_TAP_NUM=$((NEXT_TAP_NUM + 1))
  done
  NEW_TAP="tap${NEXT_TAP_NUM}"

  NEW_CONSOLE="nmdm-${NEW_VMNAME}.1"

  # Create new vm.conf
  NEW_CONF_FILE="$NEW_VM_DIR/vm.conf"
  cat > "$NEW_CONF_FILE" <<EOF
VMNAME=$NEW_VMNAME
UUID=$NEW_UUID
CPUS=$CPUS
MEMORY=$MEMORY
DISK=disk.img
DISKSIZE=$DISKSIZE
CONSOLE=$NEW_CONSOLE
LOG=$NEW_VM_DIR/vm.log
AUTOSTART=no
EOF

  # Copy and modify network interfaces
  local NIC_IDX=0
  while true; do
    local SOURCE_TAP_VAR="TAP_${NIC_IDX}"
    local SOURCE_MAC_VAR="MAC_${NIC_IDX}"
    local SOURCE_BRIDGE_VAR="BRIDGE_${NIC_IDX}"

    local SOURCE_TAP="${!SOURCE_TAP_VAR}"
    local SOURCE_MAC="${!SOURCE_MAC_VAR}"
    local SOURCE_BRIDGE="${!SOURCE_BRIDGE_VAR}"

    if [ -z "$SOURCE_TAP" ]; then
      break # No more network interfaces configured
    fi

    local NEW_TAP_CLONE
    NEXT_TAP_NUM=0
    while ifconfig | grep -q "^tap${NEXT_TAP_NUM}:"; do
      NEXT_TAP_NUM=$((NEXT_TAP_NUM + 1))
    done
    NEW_TAP_CLONE="tap${NEXT_TAP_NUM}"

    local NEW_MAC_CLONE="58:9c:fc$(jot -r -w ":%02x" -s "" 3 0 255)"

    echo "TAP_${NIC_IDX}=$NEW_TAP_CLONE" >> "$NEW_CONF_FILE"
    echo "MAC_${NIC_IDX}=$NEW_MAC_CLONE" >> "$NEW_CONF_FILE"
    echo "BRIDGE_${NIC_IDX}=$SOURCE_BRIDGE" >> "$NEW_CONF_FILE"

    NIC_IDX=$((NIC_IDX + 1))
  done

  log "New configuration file created: $NEW_CONF_FILE"
  log "VM '$NEW_VMNAME' cloned successfully."
  echo_message "VM '$NEW_VMNAME' has been cloned from '$SOURCE_VMNAME'."
  echo_message "You can now start it with: $0 start $NEW_VMNAME"
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
  printf "$info_format" "Name" "$VMNAME"
  printf "$info_format" "UUID" "$UUID"
  printf "$info_format" "CPUs" "$CPUS"
  printf "$info_format" "Memory" "$MEMORY"
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
  printf "$info_format" "TAP" "$TAP"
  printf "$info_format" "MAC" "$MAC"
  printf "$info_format" "Bridge" "$BRIDGE"
  printf "$info_format" "Console" "$CONSOLE"
  printf "$info_format" "Log File" "$LOG_FILE"
  printf "$info_format" "Autostart" "$AUTOSTART"

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

  # Check runtime status
  local PID=$(pgrep -f "bhyve.*$VMNAME")
  if [ -n "$PID" ]; then
    printf "$info_format" "Status" "RUNNING (PID: $PID)"
    local PS_INFO=$(ps -p "$PID" -o %cpu,rss= | tail -n 1)
    if [ -n "$PS_INFO" ]; then
      local CPU_USAGE=$(echo "$PS_INFO" | awk '{print $1 "%"}')
      local RAM_RSS_KB=$(echo "$PS_INFO" | awk '{print $2}')
      local RAM_USAGE
      if command -v bc >/dev/null 2>&1; then
        RAM_USAGE=$(echo "scale=0; $RAM_RSS_KB / 1024" | bc) # Convert KB to MB
        RAM_USAGE="${RAM_USAGE}MB"
      else
        RAM_USAGE="${RAM_RSS_KB}KB (bc not found)"
      fi
      printf "$info_format" "CPU Usage" "$CPU_USAGE"
      printf "$info_format" "RAM Usage" "$RAM_USAGE"
    fi
  else
    printf "$info_format" "Status" "STOPPED"
  fi
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

  # Check if VM is running
  if pgrep -f "bhyve.*$VMNAME" > /dev/null; then
    echo_message "[ERROR] VM '$VMNAME' is currently running. Please stop the VM before resizing its disk."
    exit 1
  fi

  if [ ! -f "$DISK_PATH" ]; then
    echo_message "[ERROR] Disk image for VM '$VMNAME' not found: $DISK_PATH"
    exit 1
  fi

  # Get current disk size in GB
  CURRENT_SIZE_BYTES=$(stat -f %z "$DISK_PATH")
  CURRENT_SIZE_GB=$((CURRENT_SIZE_BYTES / 1024 / 1024 / 1024))

  if (( NEW_SIZE_GB <= CURRENT_SIZE_GB )); then
    echo_message "[ERROR] New size ($NEW_SIZE_GB GB) must be greater than current size ($CURRENT_SIZE_GB GB)."
    exit 1
  fi

  log "Resizing disk for VM '$VMNAME' from ${CURRENT_SIZE_GB}GB to ${NEW_SIZE_GB}GB..."
  truncate -s "${NEW_SIZE_GB}G" "$DISK_PATH"
  if [ $? -ne 0 ]; then
    echo_message "[ERROR] Failed to resize disk image."
    exit 1
  fi
  # Update DISKSIZE in vm.conf
  sed -i '' "s/^DISKSIZE=.*/DISKSIZE=${NEW_SIZE_GB}/" "$CONF_FILE"
  log "Disk resized successfully and vm.conf updated."
  echo_message "Disk for VM '$VMNAME' has been resized to ${NEW_SIZE_GB}GB."
  echo_message "Note: You may need to extend the partition inside the VM operating system."
}

# === Subcommand: export ===
cmd_export() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    cmd_export_usage
    exit 1
  fi

  VMNAME="$1"
  DEST_PATH="$2"
  VM_DIR="$BASEPATH/vm/$VMNAME"

  if [ ! -d "$VM_DIR" ]; then
    echo_message "[ERROR] VM '$VMNAME' not found: $VM_DIR"
    exit 1
  fi

  # Check if VM is running
  if pgrep -f "bhyve.*$VMNAME" > /dev/null; then
    echo_message "[ERROR] VM '$VMNAME' is currently running. Please stop the VM before exporting."
    exit 1
  fi

  log "Exporting VM '$VMNAME' to '$DEST_PATH'..."
  tar -czf "$DEST_PATH" -C "$BASEPATH/vm" "$VMNAME"
  if [ $? -ne 0 ]; then
    echo_message "[ERROR] Failed to export VM '$VMNAME'."
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

  ARCHIVE_PATH="$1"

  if [ ! -f "$ARCHIVE_PATH" ]; then
    echo_message "[ERROR] VM archive not found: $ARCHIVE_PATH"
    exit 1
  fi

  log "Importing VM from '$ARCHIVE_PATH'..."

  # Extract archive to a temporary directory first to get VMNAME
  local TEMP_DIR=$(mktemp -d)
  tar -xzf "$ARCHIVE_PATH" -C "$TEMP_DIR"
  if [ $? -ne 0 ]; then
    echo_message "[ERROR] Failed to extract VM archive."
    rm -rf "$TEMP_DIR"
    exit 1
  fi

  # Find the VM directory inside the extracted archive
  local EXTRACTED_VM_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d -name "vm-*" -print -quit)
  if [ -z "$EXTRACTED_VM_DIR" ]; then
    EXTRACTED_VM_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d -name "*" -print -quit)
  fi

  local IMPORTED_VMNAME=$(basename "$EXTRACTED_VM_DIR")
  local NEW_VM_DIR="$BASEPATH/vm/$IMPORTED_VMNAME"

  if [ -d "$NEW_VM_DIR" ]; then
    echo_message "[ERROR] VM '$IMPORTED_VMNAME' already exists. Please delete the existing VM or choose a different name."
    rm -rf "$TEMP_DIR"
    exit 1
  fi

  # Move extracted VM to BASEPATH/vm
  mv "$EXTRACTED_VM_DIR" "$BASEPATH/vm/"
  if [ $? -ne 0 ]; then
    echo_message "[ERROR] Failed to move extracted VM to destination."
    rm -rf "$TEMP_DIR"
    exit 1
  fi
  rm -rf "$TEMP_DIR"

  # Load the imported VM's config
  load_vm_config "$IMPORTED_VMNAME"

  # Generate new UUID, MAC, TAP, CONSOLE for the imported VM to avoid conflicts
  local NEW_UUID=$(uuidgen)
  local NEW_MAC="58:9c:fc$(jot -r -w ":%02x" -s "" 3 0 255)"
  
  NEXT_TAP_NUM=0
  while ifconfig | grep -q "^tap${NEXT_TAP_NUM}:"; do
    NEXT_TAP_NUM=$((NEXT_TAP_NUM + 1))
  done
  local NEW_TAP="tap${NEXT_TAP_NUM}"

  local NEW_CONSOLE="nmdm-${IMPORTED_VMNAME}.1"

  local CONF_FILE="$VM_DIR/vm.conf"
  sed -i '' "s/^UUID=.*/UUID=$NEW_UUID/" "$CONF_FILE"
  sed -i '' "s/^MAC=.*/MAC=$NEW_MAC/" "$CONF_FILE"
  sed -i '' "s/^TAP=.*/TAP=$NEW_TAP/" "$CONF_FILE"
  sed -i '' "s/^CONSOLE=.*/CONSOLE=$NEW_CONSOLE/" "$CONF_FILE"
  sed -i '' "s/^LOG=.*/LOG=$VM_DIR/vm.log/" "$CONF_FILE"
  sed -i '' "s/^VMNAME=.*/VMNAME=$IMPORTED_VMNAME/" "$CONF_FILE"

  log "VM '$IMPORTED_VMNAME' imported successfully."
  echo_message "VM '$IMPORTED_VMNAME' has been imported."
  echo_message "You can now start it with: $0 start $IMPORTED_VMNAME"
}





# === Subcommand: network add ===
cmd_network_add() {
  local VMNAME=""
  local BRIDGE_NAME=""
  local MAC_ADDRESS=""

  # Parse named arguments
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
        echo_message "[ERROR] Invalid option: $1"
        cmd_network_add_usage
        exit 1
        ;;
    esac
    shift
  done

  # Validate required arguments
  if [ -z "$VMNAME" ] || [ -z "$BRIDGE_NAME" ]; then
    cmd_network_add_usage
    exit 1
  fi

  load_vm_config "$VMNAME"

  # Check if VM is running
  if pgrep -f "bhyve.*$VMNAME" > /dev/null; then
    echo_message "[ERROR] VM '$VMNAME' is currently running. Please stop the VM before adding a network interface."
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

  # Create and configure the TAP interface immediately
  log "Creating TAP interface '$NEW_TAP'..."
  ifconfig "$NEW_TAP" create
  if [ $? -ne 0 ]; then
    echo_message "[ERROR] Failed to create TAP interface '$NEW_TAP'."
    exit 1
  fi
  ifconfig "$NEW_TAP" description "vm-$VMNAME-nic${NIC_IDX}"
  ifconfig "$NEW_TAP" up
  log "TAP interface '$NEW_TAP' created and activated."

  # Add TAP to bridge
  if ! ifconfig "$BRIDGE_NAME" > /dev/null 2>&1; then
    log "Bridge interface '$BRIDGE_NAME' does not exist. Creating..."
    ifconfig bridge create name "$BRIDGE_NAME"
    log "Bridge interface '$BRIDGE_NAME' successfully created."
  else
    log "Bridge interface '$BRIDGE_NAME' already exists."
  fi

  ifconfig "$BRIDGE_NAME" addm "$NEW_TAP"
  if [ $? -ne 0 ]; then
    echo_message "[ERROR] Failed to add TAP '$NEW_TAP' to bridge '$BRIDGE_NAME'."
    exit 1
  fi
  log "TAP '$NEW_TAP' added to bridge '$BRIDGE_NAME'."

  log "Added network interface TAP '$NEW_TAP' (MAC: $NEW_MAC) on bridge '$BRIDGE_NAME' to VM '$VMNAME'."
  echo_message "Network interface added to VM '$VMNAME'. Please restart the VM for changes to take effect."
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

  # Check if VM is running
  if pgrep -f "bhyve.*$VMNAME" > /dev/null; then
    echo_message "[ERROR] VM '$VMNAME' is currently running. Please stop the VM before removing a network interface."
    exit 1
  fi

  local CONF_FILE="$VM_DIR/vm.conf"
  local FOUND_NIC_IDX=-1
  local NIC_COUNT=0
  local CURRENT_BRIDGE_OF_TAP_TO_REMOVE=""

  # Find the index and bridge of the NIC to remove
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
    echo_message "[ERROR] Network interface '$TAP_TO_REMOVE' not found for VM '$VMNAME'."
    exit 1
  fi

  # Remove the lines from vm.conf
  sed -i '' "/^TAP_${FOUND_NIC_IDX}=/d" "$CONF_FILE"
  sed -i '' "/^MAC_${FOUND_NIC_IDX}=/d" "$CONF_FILE"
  sed -i '' "/^BRIDGE_${FOUND_NIC_IDX}=/d" "$CONF_FILE"

  # Remove TAP from bridge and destroy TAP interface immediately
  if [ -n "$CURRENT_BRIDGE_OF_TAP_TO_REMOVE" ] && ifconfig "$CURRENT_BRIDGE_OF_TAP_TO_REMOVE" | grep -qw "$TAP_TO_REMOVE"; then
    log "Removing TAP '$TAP_TO_REMOVE' from bridge '$CURRENT_BRIDGE_OF_TAP_TO_REMOVE'..."
    ifconfig "$CURRENT_BRIDGE_OF_TAP_TO_REMOVE" deletem "$TAP_TO_REMOVE"
  fi

  if ifconfig "$TAP_TO_REMOVE" > /dev/null 2>&1; then
    log "Destroying TAP interface '$TAP_TO_REMOVE'..."
    ifconfig "$TAP_TO_REMOVE" destroy
  fi

  # Re-index remaining NICs if necessary
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
  echo_message "Network interface removed from VM '$VMNAME'. Please restart the VM for changes to take effect."
}

# === Main logic ===
case "$1" in
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
            echo_message "[ERROR] Invalid subcommand for 'network': $1"
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
      remove)
        shift
        cmd_switch_remove "$@"
        ;;
      --help)
        cmd_switch_usage
        exit 0
        ;;
      *)
        if [ -n "$1" ]; then
            echo_message "[ERROR] Invalid subcommand for 'switch': $1"
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
