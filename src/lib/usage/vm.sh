#!/usr/local/bin/bash

# === Main usage function for vm ===
cmd_vm_usage() {
  echo_message "Usage: $(basename "$(basename "$0")") vm <subcommand> [options]"
  echo_message "\nDescription:"
  echo_message "  Main command for managing virtual machines."
  echo_message "\nAvailable Subcommands:"
  echo_message "  create, delete, install, start, stop, restart, console, autostart, modify, clone, info, resize-disk, export, import, suspend, resume, vnc, list, stopall, startall, verify"
  echo_message "\nFor detailed usage of each subcommand, use: $(basename "$0") vm <subcommand> --help"
}

# === Usage function for create ===
cmd_create_usage() {
  echo_message "Usage: $(basename "$0") create --name <vmname> --switch <bridge_name> [--disk-size <disksize in GB>] [--from-template <template_name>] [--bootloader <type>] [--vnc-port <port>] [--vnc-wait] [--nic-type <type>]"
  echo_message "\nOptions:"
  echo_message "  --name <vmname>              - Name of the virtual machine."
  echo_message "  --switch <bridge_name>       - Name of the network bridge to connect the VM to."
  echo_message "  --disk-size <size in GB>     - Optional. Size of the virtual disk in GB. Required if --from-template is not used."
  echo_message "  --from-template <template_name> - Optional. Create VM from an existing template. If used, --disk-size is optional."
  echo_message "  --bootloader <type>          - Optional. Type of bootloader (bhyveload, uefi). Default: bhyveload."
  echo_message "  --vnc-port <port>            - Optional. Enable VNC console on specified port (e.g., 5900)."
  echo_message "  --vnc-wait                   - Optional. Wait for VNC client connection before booting VM."
  echo_message "  --nic-type <type>            - Optional. Type of virtual NIC (virtio-net, e1000, re0). Default: virtio-net."
  echo_message "\nExample:"
  echo_message "  $(basename "$0") create --name vm-bsd --disk-size 40 --switch bridge100"
  echo_message "  $(basename "$0") create --name vm-uefi --disk-size 60 --switch bridge101 --bootloader uefi --vnc-port 5900 --vnc-wait --nic-type e1000"
  echo_message "  $(basename "$0") create --name myvm-from-template --from-template mytemplate --switch bridge0"
}

# === Usage function for delete ===
cmd_delete_usage() {
  echo_message "Usage: $(basename "$0") delete <vmname>"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine to permanently delete."
}

# === Usage function for install ===
cmd_install_usage() {
  echo_message "Usage: $(basename "$0") install <vmname> [--bootloader <type>] [--bootmenu]"
  echo_message "\nOptions:"
  echo_message "  --bootloader <type>          - Optional. Override the bootloader type for this installation (bhyveload, uefi)."
  echo_message "  --bootmenu                   - Optional. For UEFI bootloader, attempts to send ESC key to trigger boot menu."
}

# === Usage function for start ===
cmd_start_usage() {
  echo_message "Usage: $(basename "$0") start <vmname> [--console]"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine to start."
  echo_message "\nOptions:"
  echo_message "  --console   - Automatically connect to the VM's console after starting. Bootloader output will be shown."
}

# === Usage function for stop ===
cmd_stop_usage() {
  echo_message "Usage: $(basename "$0") stop <vmname> [--force]"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine to stop."
  echo_message "\nOptions:"
  echo_message "  --force     - Forcefully stop the VM without attempting a graceful shutdown."
}

# === Usage function for console ===
cmd_console_usage() {
  echo_message "Usage: $(basename "$0") console <vmname>"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine to connect to."
}



# === Usage function for autostart ===
cmd_autostart_usage() {
  echo_message "Usage: $(basename "$0") autostart <vmname> <enable|disable>"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine."
  echo_message "  <action>    - 'enable' to set the VM to autostart on boot, or 'disable' to prevent it."
}

# === Usage function for list ===
cmd_list_usage() {
  echo_message "Usage: $(basename "$0") vm list"
  echo_message "\nDescription:"
  echo_message "  Lists all configured virtual machines, their static configuration, and live status."
}

# === Usage function for info ===
cmd_info_usage() {
  echo_message "Usage: $(basename "$0") info <vmname>"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine to display information about."
}

# === Usage function for modify ===
cmd_modify_usage() {
  echo_message "Usage: $(basename "$0") modify <vmname> [options]"
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
  echo_message "  --add-disk-path <path>       - Add an existing disk image file to the VM."
  echo_message "  --add-disk-type <type>       - Specify disk type for --add-disk or --add-disk-path (virtio-blk, ahci-hd). Default: virtio-blk."
  echo_message "  --remove-disk <index>        - Remove a virtual disk by its index (e.g., 0 for the primary disk, 1 for DISK_1).\n  --nic-type <type>            - Specify NIC type for --add-nic (virtio-net, e1000, re0). Default: virtio-net.\n\nExamples:"
  echo_message "\nExamples:"
  echo_message "  $(basename "$0") modify myvm --cpu 4 --ram 4096M"
  echo_message "  $(basename "$0") modify myvm --nic 0 --tap tap1 --bridge bridge1 # Modify existing NIC 0"
  echo_message "  $(basename "$0") modify myvm --add-nic bridge2                 # Add a new NIC connected to bridge2"
  echo_message "  $(basename "$0") modify myvm --add-disk 20"
  echo_message "  $(basename "$0") modify myvm --add-disk-path /path/to/my/data.img --add-disk-type ahci-hd"
  echo_message "  $(basename "$0") modify myvm --remove-disk 1"
}

# === Usage function for clone ===
cmd_clone_usage() {
  echo_message "Usage: $(basename "$0") clone <source_vmname> <new_vmname>"
  echo_message "\nArguments:"
  echo_message "  <source_vmname>    - The name of the existing virtual machine to clone."
  echo_message "  <new_vmname>       - The name for the new cloned virtual machine."
  echo_message "\nExample:"
  echo_message "  $(basename "$0") clone myvm newvm"
}

# === Usage function for resize-disk ===
cmd_resize_disk_usage() {
  echo_message "Usage: $(basename "$0") resize-disk <vmname> <new_size_in_GB>"
  echo_message "\nArguments:"
  echo_message "  <vmname>         - The name of the virtual machine whose disk you want to resize."
  echo_message "  <new_size_in_GB> - The new size of the virtual disk in GB. Must be larger than the current size."
  echo_message "\nExample:"
  echo_message "  $(basename "$0") resize-disk myvm 60"
}

# === Usage function for export ===
cmd_export_usage() {
  echo_message "Usage: $(basename "$0") export <vmname> <destination_directory> [--compression <format>] [--force-export | --suspend-export | --stop-export]\nArguments:"
  echo_message "  <vmname>              - The name of the virtual machine to export."
  echo_message "  <destination_directory> - The full path to the directory where the VM will be exported. The VM will be exported in a new compression format."
  echo_message "\nOptions:"
  echo_message "  --compression <format> - Optional. Specify the compression format (gz, bz2, xz, lz4, zst). Default: gz."
  echo_message "  --force-export         - Optional. Force export a running VM without stopping/suspending (not recommended)."
  echo_message "  --suspend-export       - Optional. Suspend a running VM before export, and resume after."
  echo_message "  --stop-export          - Optional. Stop a running VM before export, and restart after."
  echo_message "\nExample:"
  echo_message "  $(basename "$0") export myvm /tmp/myvm_exports"
  echo_message "  $(basename "$0") export myvm /tmp/myvm_exports --compression bz2"
  echo_message "  $(basename "$0") export myvm /tmp/myvm_exports --stop-export"
}

# === Usage function for import ===
cmd_import_usage() {
  echo_message "Usage: $(basename "$0") import <path_to_vm_archive>"
  echo_message "\nArguments:"
  echo_message "  <path_to_vm_archive> - The full path to the VM archive file to import (e.g., /tmp/myvm_backup.tar.gz)."
  echo_message "\nExample:"
  echo_message "  $(basename "$0") import /tmp/myvm_backup.tar.gz"
}

# === Usage function for restart ===
cmd_restart_usage() {
  echo_message "Usage: $(basename "$0") restart <vmname> [--force]\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine to restart.\nOptions:"
  echo_message "  --force     - Perform a fast but unsafe restart (hard reset). Skips graceful shutdown."
}

# === Usage function for stopall ===
cmd_stopall_usage() {
  echo_message "Usage: $(basename "$0") vm stopall [--force]"
  echo_message "\nOptions:"
  echo_message "  --force     - Forcefully stop all VMs without attempting graceful shutdown."
}

# === Usage function for startall ===
cmd_startall_usage() {
  echo_message "Usage: $(basename "$0") vm startall"
  echo_message "\nDescription:"
  echo_message "  Start all configured virtual machines."
}

# === Usage function for suspend ===
cmd_suspend_usage() {
  echo_message "Usage: $(basename "$0") suspend <vmname>"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine to suspend."
  echo_message "\nDescription:"
  echo_message "  Suspends a running virtual machine, saving its state to disk."
}

# === Usage function for resume ===
cmd_resume_usage() {
  echo_message "Usage: $(basename "$0") resume <vmname>"
  echo_message "\nArguments:"
  echo_message "  <vmname>    - The name of the virtual machine to resume."
  echo_message "\nDescription:"
  echo_message "  Resumes a previously suspended virtual machine from its saved state."
}

# === Usage function for verify ===
cmd_verify_usage() {
  echo_message "Usage: $(basename "$0") vm verify"
  echo_message "\nDescription:"
  echo_message "  Verify the consistency and integrity of VM configurations."
}
