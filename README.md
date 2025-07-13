# bhyve-cli.sh - A Command-Line Interface for bhyve VM Management

`bhyve-cli.sh` is a comprehensive Bash script designed to simplify the management of bhyve virtual machines on FreeBSD. It provides a command-line interface for common VM operations, network configuration, and system initialization, aiming to streamline the bhyve workflow.

## Table of Contents

- [bhyve-cli.sh - A Command-Line Interface for bhyve VM Management](#bhyve-clish---a-command-line-interface-for-bhyve-vm-management)
  - [Table of Contents](#table-of-contents)
  - [Features](#features)
  - [Prerequisites](#prerequisites)
  - [Installation and Setup](#installation-and-setup)
  - [Configuration](#configuration)
  - [Usage](#usage)
    - [General Usage](#general-usage)
    - [Commands](#commands)
      - [`init`](#init)
      - [`create`](#create)
      - [`delete`](#delete)
      - [`install`](#install)
      - [`start`](#start)
      - [`stop`](#stop)
      - [`restart`](#restart)
      - [`console`](#console)
      - [`logs`](#logs)
      - [`autostart`](#autostart)
      - [`modify`](#modify)
      - [`clone`](#clone)
      - [`info`](#info)
      - [`resize-disk`](#resize-disk)
      - [`export`](#export)
      - [`import`](#import)
      - [`iso`](#iso)
      - [`status`](#status)
      - [`switch`](#switch)
        - [`switch init`](#switch-init)
        - [`switch add`](#switch-add)
        - [`switch list`](#switch-list)
        - [`switch destroy`](#switch-destroy)
        - [`switch delete`](#switch-delete)
      - [`network`](#network)
        - [`network add`](#network-add)
        - [`network remove`](#network-remove)
  - [Logging](#logging)
  - [Troubleshooting](#troubleshooting)

## Features

- **VM Lifecycle Management:** Create, delete, install, start, stop, and restart virtual machines.
- **Configuration:** Modify VM settings like CPU, RAM, and network interfaces.
- **Networking:** Manage bhyve network bridges, add/remove physical interfaces, and configure VLANs.
- **Disk Management:** Resize virtual disk images.
- **Import/Export:** Archive and restore VMs.
- **ISO Management:** List and download ISO images for installations.
- **Console Access:** Connect to VM consoles.
- **Logging:** Centralized and VM-specific logging for easy debugging.
- **Autostart:** Configure VMs to start automatically on host boot.

## Prerequisites

Before using `bhyve-cli.sh`, ensure your FreeBSD system meets the following requirements:

- **Bash:** The script requires Bash to run.
- **bhyve:** The bhyve hypervisor and its utilities (`bhyvectl`, `bhyveload`) must be installed and available in your system's PATH.
- **Kernel Modules:** The `vmm` and `nmdm` kernel modules must be loaded. You can load them manually using `kldload vmm` and `kldload nmdm`, or configure them to load at boot via `/etc/rc.conf`.
- **`uuidgen`:** For generating unique identifiers (usually part of `util-linux` or base system).
- **`fetch`:** For downloading ISOs (part of base system).
- **`cu`:** For console access (part of base system).
- **`bc`:** For disk size calculations (optional, but recommended for accurate status reporting).

## Installation and Setup

1.  **Download the script:**
    ```bash
    git clone <repository_url>
    cd bhyve-cli.sh_directory
    chmod +x bhyve-cli.sh
    ```
    (Replace `<repository_url>` with the actual URL if applicable, otherwise assume the script is already in the current directory.)

2.  **Initialize the script:**
    The first time you run `bhyve-cli.sh`, you need to initialize its configuration. This will create necessary directories and a main configuration file.

    ```bash
    ./bhyve-cli.sh init
    ```
    During initialization, you will be prompted to specify a directory for storing ISO images. The default is `/var/bhyve/iso`.

## Configuration

`bhyve-cli.sh` stores its main configuration in `/usr/local/etc/bhyve-cli/bhyve-cli.conf`. Each VM also has its own configuration file located in `/usr/local/etc/bhyve-cli/vm.d/<vmname>/vm.conf`.

Key configuration variables:

-   `CONFIG_DIR`: Base directory for bhyve-cli configurations (`/usr/local/etc/bhyve-cli`).
-   `MAIN_CONFIG_FILE`: Main configuration file (`$CONFIG_DIR/bhyve-cli.conf`).
-   `VM_CONFIG_BASE_DIR`: Directory for VM-specific configurations (`$CONFIG_DIR/vm.d`).
-   `SWITCH_CONFIG_FILE`: File for storing network switch configurations (`$CONFIG_DIR/switch.conf`).
-   `ISO_DIR`: Directory where ISO images are stored (configured during `init`).
-   `UEFI_FIRMWARE_PATH`: Path to UEFI firmware for UEFI-booted VMs (configured during `init`).
-   `GLOBAL_LOG_FILE`: Path to the global log file (`/var/log/bhyve-cli.log`).

## Usage

### General Usage

```bash
./bhyve-cli.sh <command> [options/arguments]
```

For detailed usage of any specific command, use:

```bash
./bhyve-cli.sh <command> --help
```

### Commands

#### `init`

Initializes the `bhyve-cli` configuration directory and files.

```bash
Usage: ./bhyve-cli.sh init
```

#### `create`

Creates a new virtual machine.

```bash
Usage: ./bhyve-cli.sh create --name <vmname> --disk-size <disksize in GB> --switch <bridge_name> [--bootloader <type>]

Options:
  --name <vmname>              - Name of the virtual machine.
  --disk-size <size in GB>     - Size of the virtual disk in GB.
  --switch <bridge_name>       - Name of the network bridge to connect the VM to.
  --bootloader <type>          - Optional. Type of bootloader (bhyveload, uefi). Default: bhyveload.

Example:
./bhyve-cli.sh create --name vm-bsd --disk-size 40 --switch bridge100
./bhyve-cli.sh create --name vm-uefi --disk-size 60 --switch bridge101 --bootloader uefi
```

#### `delete`

Deletes an existing virtual machine permanently.

```bash
Usage: ./bhyve-cli.sh delete <vmname>

Arguments:
  <vmname>    - The name of the virtual machine to permanently delete.
```

#### `install`

Installs an operating system on a VM. This command will guide you through selecting an ISO and connecting to the VM's console for installation.

```bash
Usage: ./bhyve-cli.sh install <vmname> [--bootloader <type>]

Options:
  --bootloader <type>          - Optional. Override the bootloader type for this installation (bhyveload, uefi).
```

#### `start`

Starts a virtual machine.

```bash
Usage: ./bhyve-cli.sh start <vmname>

Arguments:
  <vmname>    - The name of the virtual machine to start.
```

#### `stop`

Stops a running virtual machine.

```bash
Usage: ./bhyve-cli.sh stop <vmname>

Arguments:
  <vmname>    - The name of the virtual machine to stop.
```

#### `restart`

Restarts a virtual machine.

```bash
Usage: ./bhyve-cli.sh restart <vmname>

Arguments:
  <vmname>    - The name of the virtual machine to restart.
```

#### `console`

Accesses the console of a VM.

```bash
Usage: ./bhyve-cli.sh console <vmname>

Arguments:
  <vmname>    - The name of the virtual machine to connect to.
```

#### `logs`

Displays real-time logs for a VM.

```bash
Usage: ./bhyve-cli.sh logs <vmname>

Arguments:
  <vmname>    - The name of the virtual machine whose logs you want to view.
```

#### `autostart`

Enables or disables VM autostart on boot.

```bash
Usage: ./bhyve-cli.sh autostart <vmname> <enable|disable>

Arguments:
  <vmname>    - The name of the virtual machine.
  <action>    - 'enable' to set the VM to autostart on boot, or 'disable' to prevent it.
```

#### `modify`

Modifies VM configuration (CPU, RAM, network, etc.). The VM must be stopped before modification.

```bash
Usage: ./bhyve-cli.sh modify <vmname> [--cpu <num>] [--ram <size>] [--nic <index> --tap <tap_name> --mac <mac_address> --bridge <bridge_name>]

Arguments:
  <vmname>    - The name of the virtual machine to modify.

Options:
  --cpu <num>                  - Set the number of virtual CPUs for the VM.
  --ram <size>                 - Set the amount of RAM for the VM (e.g., 2G, 4096M).
  --nic <index>                - Specify the index of the network interface to modify (e.g., 0 for TAP_0). Required when using --tap, --mac, or --bridge.
  --tap <tap_name>             - Assign a new TAP device name to the specified NIC.
  --mac <mac_address>          - Assign a new MAC address to the specified NIC.
  --bridge <bridge_name>       - Connect the specified NIC to a different bridge.

Example:
 ./bhyve-cli.sh modify myvm --cpu 4 --ram 4096M
 ./bhyve-cli.sh modify myvm --nic 0 --tap tap1 --bridge bridge1
```

#### `clone`

Creates a clone of an existing VM. The source VM must be stopped.

```bash
Usage: ./bhyve-cli.sh clone <source_vmname> <new_vmname>

Arguments:
  <source_vmname>    - The name of the existing virtual machine to clone.
  <new_vmname>       - The name for the new cloned virtual machine.

Example:
 ./bhyve-cli.sh clone myvm newvm
```

#### `info`

Displays detailed information about a VM.

```bash
Usage: ./bhyve-cli.sh info <vmname>

Arguments:
  <vmname>    - The name of the virtual machine to display information about.
```

#### `resize-disk`

Resizes a VM's disk image. The VM must be stopped.

```bash
Usage: ./bhyve-cli.sh resize-disk <vmname> <new_size_in_GB>

Arguments:
  <vmname>         - The name of the virtual machine whose disk you want to resize.
  <new_size_in_GB> - The new size of the virtual disk in GB. Must be larger than the current size.

Example:
 ./bhyve-cli.sh resize-disk myvm 60
```

#### `export`

Exports a VM to an archive file. The VM must be stopped.

```bash
Usage: ./bhyve-cli.sh export <vmname> <destination_path>

Arguments:
  <vmname>           - The name of the virtual machine to export.
  <destination_path> - The full path including the filename for the exported archive (e.g., /tmp/myvm_backup.tar.gz).

Example:
 ./bhyve-cli.sh export myvm /tmp/myvm_backup.tar.gz
```

#### `import`

Imports a VM from an archive file.

```bash
Usage: ./bhyve-cli.sh import <path_to_vm_archive>

Arguments:
  <path_to_vm_archive> - The full path to the VM archive file to import (e.g., /tmp/myvm_backup.tar.gz).

Example:
 ./bhyve-cli.sh import /tmp/myvm_backup.tar.gz
```

#### `iso`

Manages ISO images (list and download).

```bash
Usage: ./bhyve-cli.sh iso [list | <URL>]

Subcommands:
  list         - List all ISO images in $ISO_DIR.
  <URL>        - Download an ISO image from the specified URL to $ISO_DIR.

Example:
 ./bhyve-cli.sh iso list
 ./bhyve-cli.sh iso https://example.com/freebsd.iso
```

#### `status`

Shows the status of all virtual machines.

```bash
Usage: ./bhyve-cli.sh status
```

#### `switch`

Manages network bridges and physical interfaces.

```bash
Usage: ./bhyve-cli.sh switch [subcommand] [Option] [Arguments]

Subcommands:
  init        - Re-initialize all saved switch configurations.
  add         - Create a bridge and add a physical interface
  list        - List all bridge interfaces and their members
  destroy     - Destroy a bridge and all its members
  delete      - Remove a specific member from a bridge
```

##### `switch init`

Re-initializes all saved switch configurations from the switch config file. This is useful for restoring network configuration after a host reboot.

```bash
Usage: ./bhyve-cli.sh switch init
```

##### `switch add`

Creates a bridge and adds a physical interface to it.

```bash
Usage: ./bhyve-cli.sh switch add --name <bridge_name> --interface <physical_interface> [--vlan <vlan_tag>]

Options:
  --name <bridge_name>         - Name of the bridge or vSwitch.
  --interface <physical_interface> - Parent physical network interface (e.g., em0, igb1).
  --vlan <vlan_tag>            - Optional. VLAN ID if the parent interface is in trunk mode. A VLAN interface (e.g., vlan100) will be created on top of the physical interface and tagged to the bridge.
```

##### `switch list`

Lists all bridge interfaces and their members.

```bash
Usage: ./bhyve-cli.sh switch list
```

##### `switch destroy`

Destroys a bridge and all its members.

```bash
Usage: ./bhyve-cli.sh switch destroy <bridge_name>

Arguments:
  <bridge_name> - The name of the bridge to destroy.
```

##### `switch delete`

Removes a specific member from a bridge.

```bash
Usage: ./bhyve-cli.sh switch delete --member <interface> --from <bridge_name>

Options:
  --member <interface>         - The specific member interface to remove (e.g., tap0, vlan100).
  --from <bridge_name>         - The bridge from which to remove the member.
```

#### `network`

Manages network interfaces for individual VMs.

```bash
Usage: ./bhyve-cli.sh network [subcommand] [arguments]

Subcommands:
  add    - Add a network interface to a VM.
  remove - Remove a network interface from a VM.

For detailed usage of each subcommand, use: ./bhyve-cli.sh network <subcommand> --help
```

##### `network add`

Adds a network interface to a VM.

```bash
Usage: ./bhyve-cli.sh network add --vm <vmname> --switch <bridge_name> [--mac <mac_address>]

Options:
  --vm <vmname>                - Name of the virtual machine to add the network interface to.
  --switch <bridge_name>       - Name of the network bridge to connect the new interface to.
  --mac <mac_address>          - Optional. Specific MAC address for the new interface. If omitted, a random one is generated.

Example:
 ./bhyve-cli.sh network add --vm myvm --switch bridge1
 ./bhyve-cli.sh network add --vm myvm --switch bridge2 --mac 58:9c:fc:00:00:01
```

##### `network remove`

Removes a network interface from a VM.

```bash
Usage: ./bhyve-cli.sh network remove <vmname> <tap_name>

Arguments:
  <vmname>    - The name of the virtual machine to remove the network interface from.
  <tap_name>  - The name of the TAP interface to remove (e.g., tap0, tap1).

Example:
 ./bhyve-cli.sh network remove myvm tap0
```

## Logging

The script uses a structured logging approach:

-   **Console Output (`echo_message`):** Used for interactive prompts and general messages displayed directly to the user without timestamps.
-   **Console & Log File (`display_and_log`):** Used for event-based messages (ERROR, WARNING, INFO) that are displayed to the console (without timestamp/level prefix) and also written to both the VM-specific log file (with timestamp and level) and the global log file.
-   **Global Log File Only (`log_to_global_file`):** Used for messages that should only be recorded in the global log file, typically for background operations or detailed debugging.

VM-specific logs are located in `VM_CONFIG_BASE_DIR/<vmname>/vm.log`.
The global log file is located at `/var/log/bhyve-cli.log`.

## Troubleshooting

-   **"This script must be run with superuser (root) privileges.
-   **"Kernel module 'vmm.ko' is not loaded." or "'nmdm.ko' is not loaded."**: Load the required kernel modules using `kldload vmm` and `kldload nmdm`. For persistence across reboots, add `vmm_load="YES"` and `nmdm_load="YES"` to `/etc/rc.conf`.
-   **"bhyve-cli has not been initialized."**: Run `./bhyve-cli.sh init` to set up the necessary configuration files.
-   **VM not stopping/starting correctly**: Check the VM's specific log file (`VM_CONFIG_BASE_DIR/<vmname>/vm.log`) and the global log file (`/var/log/bhyve-cli.log`) for error messages.
-   **Network issues**: Use `./bhyve-cli.sh switch list` to inspect bridge and TAP interface configurations. Ensure physical interfaces are correctly added to bridges.
-   **"UEFI firmware not found."**: Install `edk2-bhyve` using `pkg install edk2-bhyve` or manually place a compatible UEFI firmware file in the configured `UEFI_FIRMWARE_PATH
