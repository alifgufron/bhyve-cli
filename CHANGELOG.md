# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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