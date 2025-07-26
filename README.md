# bhyve-cli - Advanced Bhyve VM Management

`bhyve-cli` is a powerful, modular shell script for managing bhyve virtual machines on FreeBSD. It provides a structured command-line interface for the entire VM lifecycle, from creation and network setup to daily operations and system integration.

## Features

-   **Full VM Lifecycle:** Create, delete, start, stop, restart, install, clone, export, import, and resize VM disks.
-   **Modular Codebase:** A clean, maintainable structure with commands, functions, and usage messages separated into individual files.
-   **Network Management:** Easily manage virtual switches (bridges), add physical interfaces, and handle VLANs.
-   **Autostart Service (rc.d):** Includes a system `rc.d` script to initialize the network and autostart designated VMs on boot.
-   **Console & Logs:** Instantly access VM consoles and view real-time logs.
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

2.  **Install the scripts:**
    Copy the main script and the rc.d service script to their standard locations.
    ```bash
    sudo cp bhyve-cli.sh /usr/local/sbin/
    sudo cp bhyve-cli /usr/local/etc/rc.d/
    sudo chmod +x /usr/local/etc/rc.d/bhyve-cli
    ```

3.  **Initialize `bhyve-cli`:**
    Run the `init` command to create the necessary configuration files and directories.
    ```bash
    sudo bhyve-cli.sh init
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
`sudo bhyve-cli.sh <command> [sub-command] [options]`

**Examples:**

```bash
# Create a new VM
$ sudo bhyve-cli.sh vm create --name my-bsd --disk-size 20 --switch bridge0

# Start the VM
$ sudo bhyve-cli.sh vm start my-bsd

# List all VMs and their status
$ sudo bhyve-cli.sh list

# Access the VM's console
$ sudo bhyve-cli.sh vm console my-bsd

# List all network switches
$ sudo bhyve-cli.sh switch list
```

## Main Commands

-   `init`: Initializes the configuration for `bhyve-cli`.
-   `list`: Lists all created VMs and their current status (running, stopped).
-   `vm`: The primary command for all VM-specific actions.
    -   `vm create`, `vm delete`, `vm install`, `vm start`, `vm stop`, `vm restart`, `vm console`, `vm info`
-   `switch`: Manages virtual network switches (bridges).
    -   `switch add`, `switch list`, `switch destroy`
-   `iso`: Manages installation ISO images.
    -   `iso list`, `iso download`, `iso delete`
-   `startall`: Starts all VMs that have `AUTOSTART=yes` in their config.
-   `stopall`: Stops all currently running VMs.

For detailed usage of any command, use the `--help` flag:
`sudo bhyve-cli.sh <command> --help`