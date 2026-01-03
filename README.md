# bhyve-cli - lightweight Bhyve VM Management

`bhyve-cli` is a powerful, modular shell script for managing bhyve virtual machines on FreeBSD. It provides a structured command-line interface for the entire VM lifecycle, from creation and network setup to daily operations and system integration.

## Features

-   **Full VM Lifecycle:** Comprehensive management including create, delete, start, stop, restart, install, clone, export, import, modify, verify, and disk resizing.
-   **Live Snapshots:** Create consistent snapshots of running VMs using a non-disruptive suspend/resume mechanism (create, list, revert, delete).
-   **Modular & Maintainable:** Clean codebase with commands, functions, and usage messages separated into single-responsibility files.
-   **Flexible Network Management:**
    -   Manage virtual switches (bridges) with physical interfaces and VLANs.
    -   Create and manage isolated virtual networks (vmnet) for inter-VM communication.
-   **Autostart Service (rc.d):** System `rc.d` script to initialize network configurations (switches and vmnets) and autostart designated VMs on boot.
-   **Console & Logs:** Direct access to VM consoles and enhanced real-time log viewing with `--tail` and `-f` options.
-   **ISO Management:** List, download, and manage ISO installation images.
-   **Enhanced Disk Management:** Flexible options to add, remove, and specify disk types (virtio-blk, ahci-hd) for VMs.
-   **VM Templating:** Create and manage VM templates for quick deployment of new VMs.
-   **Configuration Verification:** Ensure VM configurations are valid before starting.

## Extra: Automated Backup & Email Reporting

The `extra/` directory contains a powerful standalone script, `backup-vmbhyve.sh`, for automating VM backups and receiving status reports via email. This single script can manage backups for the local machine or act as a controller to orchestrate backups on multiple remote nodes.

### Script Features

-   **Unified Controller/Worker Model:** A single script handles both local backups and orchestrating remote backups via SSH.
-   **High Portability:** Automatically detects and uses either `base64` or `openssl` for data encoding, ensuring it runs on a wide range of systems, including older FreeBSD versions where `base64` might not be in the base system.
-   **Flexible Backup Modes:** Configure `BACKUP_MODE="local"` or `BACKUP_MODE="remote"` in the config file.
-   **Dual Email Reports:**
    -   Sends detailed **individual reports** for each VM backup, including status, manager, duration, and a list of retained backups.
    -   Sends a comprehensive **summary report** after all operations are complete, containing the full, synchronized log of the entire run.
-   **Robust & Dependency-Free:** Includes a self-contained mail function and has been hardened against common shell scripting pitfalls.

### Setup

Before first use, copy the sample configuration file and edit it to match your environment.

```bash
cd extra/
cp backup-vmbhyve.conf.sample backup-vmbhyve.conf
# Now edit backup-vmbhyve.conf with your settings (email, SSH user, nodes, etc.)
```

### Usage

The script is always run from the controller machine and requires the path to its configuration file.

```bash
# Run the backup process as defined in your config file
./extra/backup-vmbhyve.sh --config ./extra/backup-vmbhyve.conf
```

### Automation with Cron

This script is ideal for automation. To run your configured backup process daily at 2:30 AM, add the following to your crontab (e.g., `sudo crontab -e`):

```crontab
# Daily backup for all configured VMs
30 2 * * * /path/to/bhyve-cli/extra/backup-vmbhyve.sh --config /path/to/bhyve-cli/extra/backup-vmbhyve.conf > /dev/null 2>&1
```

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

## Interoperability with vm-bhyve

`bhyve-cli` offers some integration with VMs managed by the standard `vm-bhyve` tool, allowing `bhyve-cli` to list, start, stop, suspend, resume, and export `vm-bhyve` VMs. However, direct interoperability for exported/imported VM configurations requires manual intervention due to differences in their configuration formats.

### Exporting and Importing VMs between `bhyve-cli` and `vm-bhyve`

When you export a VM using `bhyve-cli`, the archive preserves the original VM's configuration format:
*   **`bhyve-cli` native VMs:** The archive contains `vm.conf` (bhyve-cli's format).
*   **`vm-bhyve` VMs:** The archive contains `<vmname>.conf` (vm-bhyve's format).

**Compatibility Notes:**

*   **Exported `vm-bhyve` VM imported into `bhyve-cli`:**
    *   The VM will be extracted into `bhyve-cli`'s VM directory.
    *   However, `bhyve-cli` expects a `vm.conf` file. Since the imported archive contains `<vmname>.conf`, `bhyve-cli`'s native commands will **not** automatically recognize or manage this VM.
    *   **Manual conversion is required:** To manage such a VM with `bhyve-cli`, you must manually rename `<vmname>.conf` to `vm.conf` and adjust its contents to match `bhyve-cli`'s configuration format.
*   **Exported `bhyve-cli` VM imported into `vm-bhyve`:**
    *   This is **not directly supported** by `bhyve-cli`'s `import` command. `vm-bhyve` has its own import mechanisms and expects its specific configuration format (`<vmname>.conf`).
    *   You would need to manually convert `bhyve-cli`'s `vm.conf` to `vm-bhyve`'s `<vmname>.conf` format and adjust the directory structure before attempting to import it into `vm-bhyve`.

In essence, while `bhyve-cli` can interact with `vm-bhyve` VMs, seamless configuration exchange via export/import requires manual adaptation due to differing internal formats.

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
-   `template`: Manage VM templates.
    -   `template create`, `template list`, `template delete`
-   `vmnet`: Manages isolated virtual networks for VMs.
    -   `vmnet create`, `vmnet list`, `vmnet destroy`, `vmnet init`
-   `logs`: Display real-time logs for a VM, with options like `--tail <num>` and `-f` for continuous monitoring.

For detailed usage of any command, use the `--help` flag:
`sudo bhyve-cli.sh <command> --help`
