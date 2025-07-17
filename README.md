# bhyve-cli.sh - Simple bhyve VM Management

`bhyve-cli.sh` is a straightforward Bash script for managing bhyve virtual machines on FreeBSD. It provides a command-line interface for common VM operations, network setup, and system initialization.

## Features

-   **VM Management:** Create, delete, start, stop, restart, install, clone, export, import, and resize VM disks.
-   **Network Configuration:** Manage bhyve network bridges, add/remove interfaces, and configure VLANs.
-   **Console & Logs:** Access VM consoles and view logs.
-   **Autostart:** Configure VMs to start automatically on boot.
-   **ISO Management:** List and download ISO images.

## Prerequisites

-   **FreeBSD:** Operating system.
-   **Bash:** Script execution.
-   **bhyve:** Hypervisor and utilities (`bhyvectl`, `bhyveload`).
-   **Kernel Modules:** `vmm` and `nmdm` loaded.
-   **Utilities:** `uuidgen`, `fetch`, `cu`, `bc`.

## Installation and Setup

1.  **Download the script:**
    ```bash
    git clone https://github.com/alifgufron/bhyve-cli.git
    cd bhyve-cli.sh_directory
    chmod +x bhyve-cli.sh
    ```
2.  **Initialize:**
    ```bash
    ./bhyve-cli.sh init
    ```
    Follow the prompts to set up configuration directories.

## Usage

```bash
./bhyve-cli.sh <command> [options/arguments]
```

For detailed usage of any command:

```bash
./bhyve-cli.sh <command> --help
```

## Commands

-   `init`: Initialize bhyve-cli configuration.
-   `create`: Create a new virtual machine.
-   `delete`: Delete an existing virtual machine.
-   `install`: Install an operating system on a VM.
-   `start`: Start a virtual machine.
-   `stop`: Stop a running virtual machine.
-   `restart`: Restart a virtual machine.
-   `console`: Access the console of a VM.
-   `logs`: Display real-time logs for a VM.
-   `status`: Show the status of all virtual machines.
-   `autostart`: Enable or disable VM autostart on boot.
-   `modify`: Modify VM configuration (CPU, RAM, network, etc.).
-   `clone`: Create a clone of an existing VM.
-   `info`: Display detailed information about a VM.
-   `resize-disk`: Resize a VM's disk image.
-   `export`: Export a VM to an archive file.
-   `import`: Import a VM from an archive file.
-   `iso`: Manage ISO images (list and download).
-   `switch`: Manage network bridges and physical interfaces.
-   `stopall`: Stop all running virtual machines.
-   `startall`: Start all configured virtual machines.

## Logging

Logs are stored in VM-specific files (`VM_CONFIG_BASE_DIR/<vmname>/vm.log`) and a global log file (`/var/log/bhyve-cli.log`).

## Troubleshooting

Refer to the script's output for error messages and check the log files for detailed information. Common issues include missing kernel modules, uninitialized configuration, or VMs already running/stopped.
