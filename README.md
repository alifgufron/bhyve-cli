# bhyve-cli - lightweight Bhyve VM Management

`bhyve-cli` is a powerful, modular shell script for managing bhyve virtual machines on FreeBSD. It provides a structured command-line interface for the entire VM lifecycle, from creation and network setup to daily operations and system integration.

## Features

-   **Full VM Lifecycle:** Comprehensive management including create, delete, start, stop, restart, install, clone, export, import, and disk resizing.
-   **Live Snapshots:** Create consistent snapshots of running VMs using a non-disruptive suspend/resume mechanism.
-   **Modular & Maintainable:** Clean codebase with commands, functions, and usage messages separated into single-responsibility files.
-   **Flexible Network Management:**
    -   Manage virtual switches (bridges) with physical interfaces and VLANs.
    -   Create and manage isolated virtual networks (vmnet) for inter-VM communication.
-   **Autostart Service (rc.d):** System `rc.d` script to initialize network configurations (switches and vmnets) and autostart designated VMs on boot.
-   **Console & Logs:** Direct access to VM consoles and real-time log viewing.
-   **ISO Management:** List, download, and manage ISO installation images.

## Prerequisites

-   **OS:** FreeBSD 12.x, 13.x, 14.x
-   **Packages:** `bash`, `uuidgen`, `fetch`, `cu`, `bc`
-   **Kernel Modules:** `vmm` and `nmdm` must be loaded. Add to `/boot/loader.conf` to load on boot:
    ```
    vmm_load="YES"
    nmdm_load="YES"
    ```

## Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/alifgufron/bhyve-cli.git
    cd bhyve-cli
    ```

2.  **Install using Makefile:**
    The `Makefile` handles copying all necessary files (main script, libraries, firmware, rc.d script) to their standard locations.
    ```bash
    sudo make install
    ```

3.  **Initialize `bhyve-cli`:**
    Run the `init` command to create the necessary configuration files and directories.
    ```bash
    sudo bhyve-cli init
    ```

## Autostart on Boot

To have VMs start automatically when your system boots:

1.  **Enable the `bhyve-cli` service:**
    ```bash
    sudo sysrc bhyve_cli_enable="YES"
    ```

2.  **Configure a VM for autostart:**
    Edit the VM's configuration file (e.g., `/usr/local/etc/bhyve-cli/vm.d/my-vm/vm.conf`) and set `AUTOSTART=yes`.

On boot, the service will first initialize all network switches (`switch init`) and then start all VMs marked for autostart (`startall`).

## Usage

The general command structure is:
`sudo bhyve-cli <command> [subcommand] [options]`

**Examples:**

```bash
# Create a new VM
$ sudo bhyve-cli vm create --name my-bsd --disk-size 20 --switch bridge0

# Start the VM
$ sudo bhyve-cli vm start my-bsd

# List all VMs and their status
$ sudo bhyve-cli vm list

# Access the VM's console
$ sudo bhyve-cli vm console my-bsd

# List all network switches
$ sudo bhyve-cli switch list

# Create an isolated vmnet
$ sudo bhyve-cli vmnet create --name myisolatednet --ip 192.168.50.1/24
```

## Main Commands

-   `init`: Initializes the configuration for `bhyve-cli`.
-   `vm`: The primary command for all VM-specific actions.
    -   `vm create`, `vm delete`, `vm install`, `vm start`, `vm stop`, `vm restart`, `vm console`, `vm info`, `vm list`, `vm autostart`, `vm clone`, `vm export`, `vm import`, `vm modify`, `vm resize-disk`, `vm resume`, `vm suspend`, `vm verify`, `vm vnc`, `vm startall`, `vm stopall`
-   `snapshot`: Manage VM snapshots.
    -   `snapshot create`, `snapshot list`, `snapshot revert`, `snapshot delete`
-   `iso`: Manages installation ISO images.
    -   `iso list`, `iso download`, `iso delete`
-   `switch`: Manages virtual network switches (bridges).
    -   `switch add`, `switch list`, `switch destroy`, `switch init`
-   `vmnet`: Manages isolated virtual networks for VMs.
    -   `vmnet create`, `vmnet list`, `vmnet destroy`, `vmnet init`
-   `logs`: Display real-time logs for a VM.

For detailed usage of any command, use the `--help` flag:
`sudo bhyve-cli.sh <command> --help`