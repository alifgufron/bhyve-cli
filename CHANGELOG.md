# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v1.1.3] - 2025-10-20

### Fixed

- **`vm export` - Staging Directory Location:**
    - Modified the `vm export` command to create its temporary staging directory within the user-specified destination directory (`$DEST_DIR`) instead of the system's default temporary directory (`/tmp`).
    - This prevents export failures due to insufficient space in `/tmp` when exporting large VMs.
- **Script Compatibility and Logic in `extra/` Scripts:**
    - Changed the shebang from `#!/bin/sh` to `#!/usr/bin/env bash` for `backup_and_report.sh` and `backup-vm-test.sh` to ensure consistent execution with bash.
    - This change resolves compatibility errors with `((...))` arithmetic and `<<<` here-strings that occurred under `sh`.
    - Reverted complex workarounds (like using `mktemp`) back to cleaner, bash-native logic.
- **Interactive vs. Cron Logging:**
    - Modified the `log()` function in both scripts to write to the console *and* the log file when run from an interactive terminal, but only to the log file when run from a non-interactive session (like cron).
    - Removed the redundant `console_output()` function and replaced its calls with `log()`.
- **Email Formatting:**
    - Fixed an issue where newline characters (`\n`) were not being interpreted in the email body, causing improper formatting.
### Added

- **Unified Backup Script (`vmdump.sh`):**
    - Consolidated `backup-vm.sh` and the remote `vmdump` orchestrator into a single, powerful script: `extra/vmdump.sh`.
    - Centralized all configuration into a new `extra/backup.conf` file.
- **Flexible Email Reporting (`REPORTING_MODE`):**
    - Implemented a `REPORTING_MODE` setting in `backup.conf` to control email notifications.
    - **`summary` mode:** Sends a single email per node with a summary of all VM backup results (e.g., "2 SUCCESS, 1 FAILURE").
    - **`individual` mode:** Sends a separate email for each VM backup, maintaining the original behavior.
    - The script's logic was refactored to support both modes for local and remote execution.

### Changed

- **Backup Script Execution Model:**
    - Simplified the execution model for `extra/vmdump.sh`. The script is now exclusively run using `vmdump.sh --config <path_to_config>`.
    - Removed argument-based mode selection; the operational mode (`local` or `remote`) is now determined by the `BACKUP_MODE` variable within the specified `backup.conf` file.
    - Introduced `LOCAL_VMS` variable in `backup.conf` for defining VMs to be backed up in local mode.
    - Updated `usage` message in `vmdump.sh` to reflect the new execution model.

### Removed

## [v1.1.2] - 2025-09-16

### Changed

- **Major Refactoring of VM Discovery:**
    - Replaced multiple, inconsistent VM discovery implementations across various commands with a single, robust, centralized function: `find_any_vm`.
    - This resolves numerous bugs where commands (`stop`, `start`, `info`, `suspend`, `resume`, `export`, `import`, `snapshot`) would fail if the target VM was not in a default datastore.
    - All major commands now reliably work with both `bhyve-cli` and `vm-bhyve` VMs across all configured datastores.
- **Snapshot Command Logic:**
    - Reworked all `snapshot` subcommands (`list`, `create`, `delete`, `revert`) to correctly delegate to the native `vm-bhyve` utility for `vm-bhyve` VMs, enabling proper ZFS snapshot support.
    - Corrected file paths for `bhyve-cli` file-based snapshots.
- **PID and Helper Function Reliability:**
    - Corrected logic in all commands to pass the full VM directory path to helper functions (`is_vm_running`, `get_vm_pid`, etc.), improving reliability and fixing latent bugs.
    - Fixed argument parsing in the `wait_for_vm_status` helper function.
- **`clone` Command Argument Parsing & Datastore Support:**
    - Modified `clone` command to use named arguments (`--source`, `--new-name`) and added optional `--datastore` argument for specifying the destination datastore.
    - Implemented in `src/lib/commands/vm/clone.sh` and `src/lib/usage/vm.sh`.
- **`Makefile` Uninstall Target:**
    - Modified the `uninstall` target to execute `network_cleanup_all.sh`, ensuring a cleaner removal of network configurations.
- **`bhyve-cli init` Interactive Configuration:**
    - The `init` command now interactively prompts the user for the desired ISO storage directory and the default VM datastore path.
    - Updates the main configuration file (`bhyve-cli.conf`) and `/etc/rc.conf` with the user-defined paths.

### Fixed

- **`autostart` VM Discovery Across Datastores:**
    - Fixed an issue where `bhyve-cli autostart` could not find VMs located in non-default `bhyve-cli` datastores.
    - The command now correctly searches for VMs across all configured `bhyve-cli` datastores.
    - Added a check to prevent managing autostart for `vm-bhyve` VMs, as they are managed by `vm-bhyve` itself.
    - Implemented in `src/lib/commands/vm/autostart.sh`.
- **`vm info` VM Discovery Across Datastores:**
    - Fixed an issue where `bhyve-cli vm info` could not find VMs located in non-default `bhyve-cli` datastores due to a duplicated directory in the VM path.
    - The command now correctly resolves the VM directory.
    - Implemented in `src/lib/commands/vm/info.sh` and `src/lib/functions/config.sh`.
- **`datastore delete` VM Check and Confirmation:**
    - Enhanced `datastore delete` to check for existing VMs within the datastore before deletion.
    - Prompts for interactive confirmation if VMs are found, preventing accidental data loss.
    - Implemented in `src/lib/commands/datastore/delete.sh`.
- **`vm list` vm-bhyve Primary Datastore Name:**
    - Corrected the display name for the primary `vm-bhyve` datastore in `vm list` output from its basename (e.g., "bhvye") to "default".
    - Implemented in `src/lib/functions/config.sh`.
- **`vm list` Duplicate VM Names & Formatting:**
    - Modified `vm list` to display `VMNAME` only for `bhyve-cli` VMs (removed `(DATASTORE)` suffix), relying on the dedicated `DATASTORE` column for clarity.
    - Adjusted column widths in `vm list` output for both data and header rows to `%-40s` for "VM NAME" and `%-20s` for "DATASTORE" to ensure proper alignment and visual neatness, accommodating longer names.
    - Implemented in `src/lib/commands/vm/list.sh`.
- **Unintentional Network Cleanup Execution:**
    - Fixed an issue where `network_cleanup_all.sh` was unintentionally executed during normal `bhyve-cli` operations.
    - Resolved by excluding `network_cleanup_all.sh` from the sourced helper functions in `src/bhyve-cli`.

### Added

- **Network Cleanup Script for Uninstallation:**
    - Created `src/lib/functions/network_cleanup_all.sh` to comprehensively remove all `bhyve-cli` created network interfaces (bridges and TAP devices) during uninstallation.

## [v1.1.1] - 2025-09-13

### Fixed

- **`make install` Directory Creation:**
    - Fixed `make install` failure due to `No such file or directory` error for `vm.d`.
    - Ensured explicit creation of parent configuration directory (`/usr/local/etc/bhyve-cli`) before `vm.d`.
- **`bhyve-cli init` Redundant Copies:**
    - Removed incorrect and redundant `rc.d` script copying from `bhyve-cli init`.
    - Removed incorrect and redundant firmware files copying from `bhyve-cli init`.
    - These tasks are correctly handled by `make install`.

## [v1.1.0] - 2025-09-13

### Added

- **`vm list` - VNC Port Column & Formatting:**
    - Added a "VNC PORT" column to the `vm list` output.
    - Adjusted column widths for better alignment and readability, especially after adding the new column.
    - Displays the `VNC_PORT` from `vm.conf` or '-' if not configured.

### Changed

- **`vm start` Console Message:**
    - Modified the console connection message displayed after `vm start`.
    - Changed from `./src/bhyve-cli console <VM_NAME>` to `bhyve-cli vm console <VM_NAME>` for better consistency and user experience.

### Fixed

- **`vm import` - Unique TAP Interfaces:**
    - Fixed "Device busy" error when starting imported VMs.
    - The `vm import` command now iterates through network interfaces (`TAP_X`) in the imported VM's `vm.conf`.
    - It assigns new, unique TAP numbers using `get_next_available_tap_num` and updates `vm.conf` accordingly.
    - This ensures that imported VMs do not conflict with existing running VMs over TAP devices.
- **`vm import` Extraction:**
    - Fixed a "Broken pipe" error (`zstd: error 70`) occurring during the import of compressed archives (`.zst`, `.gz`, etc.).
    - The previous method relied on `tar`'s `--use-compress-program` flag, which proved unreliable on the target system.
    - Replaced the logic in `src/lib/commands/vm/import.sh` with a robust `case` statement that uses explicit pipes (e.g., `zstd -dc | tar -xf -`).
    - This ensures reliable and portable extraction for all supported archive formats.

### Features (from vm-bhyve integration)

- **`vm-bhyve` Integration - Core Commands:**
    - Implemented `get_vm_bhyve_dir()` to detect `vm-bhyve` installation path from `/etc/rc.conf`.
    - **`vm list`**: Adapted to display VMs from both `bhyve-cli` and `vm-bhyve` sources, including dynamic bootloader detection and output formatting.
    - **`vm info`**: Adapted to display detailed information for VMs from both `bhyve-cli` and `vm-bhyve` sources, including correct variable mapping for CPU, Memory, Disk, and Network.
    - **`vm start`**: Implemented delegation to `vm-bhyve`'s `vm start` command for `vm-bhyve` VMs.
    - **`vm stop`**: Implemented delegation to `vm-bhyve`'s `vm stop` command for `vm-bhyve` VMs.
    - **`vm suspend`/`vm resume`**: Adapted to work with `bhyve` processes launched by `vm-bhyve` (using `SIGSTOP`/`SIGCONT`).
    - **`snapshot create`**: Implemented integration for `vm-bhyve` VMs, including source detection, centralized snapshot storage, and `cp`-based disk copying. Fixed previous syntax errors and path issues. Works for UFS-based disk images; ZFS zvols are not yet supported.
    - **`snapshot list`**: Adapted to correctly list snapshots for both `bhyve-cli` native and `vm-bhyve` VMs.
    - **`vm export`**: Implemented integration for `vm-bhyve` VMs, allowing export of UFS-based disk images.
    - **`vm export` - Enhanced Compression & Usage**: Added `--compression` flag to support `gz`, `bz2`, `xz`, `lz4`, `zst` formats. Implemented automatic file extension handling based on compression type.
    - **`vm export` - Suspend/Stop Robustness:**
        * Removed placeholder `set_vm_status` call from `src/lib/commands/vm/suspend.sh`.
        * Implemented `wait_for_vm_status` helper function to robustly wait for a VM to reach a specific status (suspended or stopped).
        * Modified `vm export` to use `wait_for_vm_status` after calling `cmd_suspend` and `cmd_stop`.
        * Refined `is_vm_running` to accurately reflect the "running" status by checking the actual process state.
    * **`vm list` - Correct CPU/RAM Display for `vm-bhyve` and `bhyve-cli` VMs:**
        * Modified `vm list` to correctly parse and display CPU and RAM information for `vm-bhyve` VMs.
        * Adjusted the logic to conditionally assign CPU/RAM values based on VM type.
    * **`vm export` - Add Date to Filename:**
        * Modified `vm export` to include the current date (`YYYY_MM_DD`) in the exported archive filename.

### Other Enhancements

- **Add Data Deletion Notice to Uninstall:**
    - Modified the `uninstall` target in the `Makefile` to display a clear message informing users that their data is not automatically deleted.

### Bug Fixes (Older)

- **TAP Interface Cleanup on VM Start:**
    - Added a call to `cleanup_vm_network_interfaces` at the beginning of `cmd_start`.
    - This resolves the "ifconfig: BRDGADD tapX: Device busy" error when starting VMs.
- **`switch` Commands Implicit `vmnet_init` Call:**
    - Removed `switch` from the list of commands that trigger `cmd_vmnet_init` unconditionally.
    - This resolves the "Bridge already exists" error when running `switch` commands.
- **`vmnet list` and `vmnet init` Implicit Calls:**
    - Corrected a design flaw where `cmd_vmnet_init` was being called unconditionally for `vmnet` commands.
    - This resolves the "Bridge already exists" error when running `vmnet list` or `vmnet init`.
- **`vm import` Overwrite on Running VM:**
    - Fixed a critical bug where importing a VM over an existing, running VM would not stop the running process.
    - The `import` command now checks if the target VM is running before an overwrite, stops it gracefully, and then proceeds.
- **VM Status Consistency:**
    - Identified and fixed a major bug causing inconsistent status reporting between `list` and `info` commands.
    - Consolidated all VM status logic into `lib/functions/pid.sh`.
- **Command Dispatcher & Usage:**
    - Fixed a major design flaw in the main command dispatcher that prevented subcommand help from being displayed.
    - Implemented a two-level dispatcher system.
- **VM Start "Device Busy" Error:**
    - Added `bhyvectl --vm="$VMNAME" --destroy` call before starting the VM in `src/lib/commands/vm/start.sh`.
- **Clone Command Robustness & Start Reliability:**
    - Fixed `clone` command resume logic.
    - Fixed cloned VM PID issue.
    - Fixed `start` command `pgrep` regex.
    - Fixed `clone` command not copying `vm.log`.
