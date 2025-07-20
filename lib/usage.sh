#!/usr/local/bin/bash

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
  echo_message "  restart       - Restart a virtual machine."
  echo_message "  console       - Access the console of a VM."
  echo_message "  logs          - Display real-time logs for a VM."
  echo_message "  list          - List all configured virtual machines and their static configuration."
  echo_message "  status        - Show the live status and resource usage of all virtual machines."
  echo_message "  autostart     - Enable or disable VM autostart on boot."
  echo_message "  modify        - Modify VM configuration (CPU, RAM, network, etc.)."
  echo_message "  clone         - Create a clone of an existing VM."
  echo_message "  info          - Display detailed information about a VM."
  echo_message "  resize-disk   - Resize a VM's disk image."
  echo_message "  export        - Export a VM to an archive file."
  echo_message "  import        - Import a VM from an archive file."
  echo_message "  iso           - Manage ISO images (list and download)."
  echo_message "  switch        - Manage network bridges and physical interfaces."
  echo_message "  stopall       - Stop all running virtual machines."
  echo_message "  startall      - Start all configured virtual machines."
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
  echo_message "Usage: $0 start <vmname> [--console]"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine to start."
  echo_message "\nOptions:"
  echo_message "  --console   - Automatically connect to the VM's console after starting. Bootloader output will be shown."
}

# === Usage function for stop ===
cmd_stop_usage() {
  echo_message "Usage: $0 stop <vmname> [--force]"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine to stop."
  echo_message "\nOptions:"
  echo_message "  --force     - Forcefully stop the VM without attempting a graceful shutdown."
}

# === Usage function for console ===
cmd_console_usage() {
  echo_message "Usage: $0 console <vmname>"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine to connect to."
}

# === Usage function for logs ===
cmd_logs_usage() {
  echo_message "Usage: $0 logs <vmname>\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine whose logs you want to view."
}

# === Usage function for autostart ===
cmd_autostart_usage() {
  echo_message "Usage: $0 autostart <vmname> <enable|disable>"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine."
  echo_message "  <action>    - 'enable' to set the VM to autostart on boot, or 'disable' to prevent it."
}

# === Usage function for status ===
cmd_status_usage() {
  echo_message "Usage: $0 status"
  echo_message "\nDescription:"
  echo_message "  Displays the live resource usage (CPU, RAM) and status for all virtual machines."
}

# === Usage function for list ===
cmd_list_usage() {
  echo_message "Usage: $0 list"
  echo_message "\nDescription:"
  echo_message "  Lists all configured virtual machines and their static configuration details (UUID, CPU, RAM, etc.)."
}

# === Usage function for info ===
cmd_info_usage() {
  echo_message "Usage: $0 info <vmname>"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine to display information about."
}

# === Usage function for modify ===
cmd_modify_usage() {
  echo_message "Usage: $0 modify <vmname> [options]"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine to modify."
  echo_message "\nOptions:"
  echo_message "  --cpu <num>                  - Set the number of virtual CPUs for the VM."
  echo_message "  --ram <size>                 - Set the amount of RAM for the VM (e.g., 2G, 4096M)."
  echo_message "  --nic <index>                - Specify the index of an existing network interface to modify (e.g., 0 for TAP_0, 1 for TAP_1). This option MUST be used with --tap, --mac, or --bridge."
  echo_message "  --tap <tap_name>             - Assign a new TAP device name to the specified NIC (requires --nic).\n                                   Example: --nic 0 --tap newtap0"
  echo_message "  --mac <mac_address>          - Assign a new MAC address to the specified NIC (requires --nic).\n                                   Example: --nic 0 --mac 58:9c:fc:00:00:01"
  echo_message "  --bridge <bridge_name>       - Connect the specified NIC to a different bridge (requires --nic).\n                                   Example: --nic 0 --bridge newbridge"
  echo_message "  --add-nic <bridge_name>      - Automatically add a NEW network interface to the VM, connected to the specified bridge."
  echo_message "  --remove-nic <index>         - Remove a network interface by its index (e.g., 0 for TAP_0)."
  echo_message "  --add-disk <size_in_GB>      - Add a new virtual disk to the VM with the specified size in GB."
  echo_message "  --remove-disk <index>        - Remove a virtual disk by its index (e.g., 0 for the primary disk, 1 for DISK_1)."
  echo_message "\nExamples:"
  echo_message "  $0 modify myvm --cpu 4 --ram 4096M"
  echo_message "  $0 modify myvm --nic 0 --tap tap1 --bridge bridge1 # Modify existing NIC 0"
  echo_message "  $0 modify myvm --add-nic bridge2                 # Add a new NIC connected to bridge2"
  echo_message "  $0 modify myvm --add-disk 20"
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
  echo_message "Usage: $0 export <vmname> <destination_path>\nArguments:"
  echo_message "  <vmname>           - The name of the virtual machine to export."
  echo_message "  <destination_path> - The full path including the filename for the exported archive (e.g., /tmp/myvm_backup.tar.gz).\nExample:"
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
  echo_message "Usage: $0 restart <vmname> [--force]\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine to restart.\nOptions:"
  echo_message "  --force     - Perform a fast but unsafe restart (hard reset). Skips graceful shutdown."
}

# === Usage function for stopall ===
cmd_stopall_usage() {
  echo_message "Usage: $0 stopall [--force]\nOptions:"
  echo_message "  --force     - Forcefully stop all VMs without attempting graceful shutdown."
}

# === Usage function for startall ===
cmd_startall_usage() {
  echo_message "Usage: $0 startall"
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
