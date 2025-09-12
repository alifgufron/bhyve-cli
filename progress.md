# Progress Log for bhyve-cli

This file tracks completed tasks and major changes.

---

* **2025-09-12** - **Enhancement: `vm start` Console Message**
    * Modified the console connection message displayed after `vm start`.
    * Changed from `./src/bhyve-cli console <VM_NAME>` to `bhyve-cli vm console <VM_NAME>` for better consistency and user experience.

* **2025-09-12** - **Bug Fix: `vm import` - Unique TAP Interfaces**
    * Fixed "Device busy" error when starting imported VMs.
    * The `vm import` command now iterates through network interfaces (`TAP_X`) in the imported VM's `vm.conf`.
    * It assigns new, unique TAP numbers using `get_next_available_tap_num` and updates `vm.conf` accordingly.
    * This ensures that imported VMs do not conflict with existing running VMs over TAP devices.

* **2025-09-12** - **Bug Fix: `vm import` Extraction**
    * Fixed a "Broken pipe" error (`zstd: error 70`) occurring during the import of compressed archives (`.zst`, `.gz`, etc.).
    * The previous method relied on `tar`'s `--use-compress-program` flag, which proved unreliable on the target system.
    * Replaced the logic in `src/lib/commands/vm/import.sh` with a robust `case` statement that uses explicit pipes (e.g., `zstd -dc | tar -xf -`).
    * This ensures reliable and portable extraction for all supported archive formats.

* **2025-09-11** - **Feature: `vm-bhyve` Integration - Core Commands**
    * Implemented `get_vm_bhyve_dir()` to detect `vm-bhyve` installation path from `/etc/rc.conf`.
    * **`vm list`**: Adapted to display VMs from both `bhyve-cli` and `vm-bhyve` sources, including dynamic bootloader detection and output formatting.
    * **`vm info`**: Adapted to display detailed information for VMs from both `bhyve-cli` and `vm-bhyve` sources, including correct variable mapping for CPU, Memory, Disk, and Network.
    * **`vm start`**: Implemented delegation to `vm-bhyve`'s `vm start` command for `vm-bhyve` VMs.
    * **`vm stop`**: Implemented delegation to `vm-bhyve`'s `vm stop` command for `vm-bhyve` VMs.
    * **`vm suspend`/`vm resume`**: Adapted to work with `bhyve` processes launched by `vm-bhyve` (using `SIGSTOP`/`SIGCONT`).
    * **`snapshot create`**: Implemented integration for `vm-bhyve` VMs, including source detection, centralized snapshot storage, and `cp`-based disk copying. Fixed previous syntax errors and path issues. Works for UFS-based disk images; ZFS zvols are not yet supported.
    * **`snapshot list`**: Adapted to correctly list snapshots for both `bhyve-cli` native and `vm-bhyve` VMs.
    * **`vm export`**: Implemented integration for `vm-bhyve` VMs, allowing export of UFS-based disk images.
    * **`vm export` - Enhanced Compression & Usage**: Added `--compression` flag to support `gz`, `bz2`, `xz`, `lz4`, `zst` formats. Implemented automatic file extension handling based on compression type. **Note: Encountered persistent corruption issues with `src/lib/usage/vm.sh` during usage update, requiring file overwrite.**
    * **`vm export` - Suspend/Stop Robustness:**
        * Removed placeholder `set_vm_status` call from `src/lib/commands/vm/suspend.sh`.
        * Implemented `wait_for_vm_status` helper function in `src/lib/functions/vm_actions.sh` to robustly wait for a VM to reach a specific status (suspended or stopped).
        * Modified `src/lib/commands/vm/export.sh` to use `wait_for_vm_status` after calling `cmd_suspend` and `cmd_stop` (for both flag-based and interactive choices), ensuring the export process waits for the VM to be truly suspended or stopped.
        * Refined `is_vm_running` in `src/lib/functions/pid.sh` to accurately reflect the "running" status by checking the actual process state using `get_vm_status`, resolving the false positive for suspended VMs.
    * **`vm list` - Correct CPU/RAM Display for `vm-bhyve` and `bhyve-cli` VMs:**
        * Modified `src/lib/commands/vm/list.sh` to correctly parse and display CPU and RAM information for `vm-bhyve` VMs by mapping their `cpu` and `memory` variables.
        * Adjusted the logic in `src/lib/commands/vm/list.sh` to conditionally assign CPU/RAM values based on whether the VM is a `bhyve-cli` VM or a `vm-bhyve` VM, ensuring correct display for both.
    * **`vm export` - Add Date to Filename:**
        * Modified `src/lib/commands/vm/export.sh` to include the current date (`YYYY_MM_DD`) in the exported archive filename (e.g., `vm-name_2025_09_11.tar.gz`).


* **2025-09-10 00:00:00** - **Enhancement: Add Data Deletion Notice to Uninstall**
  - Modified the `uninstall` target in the `Makefile` to display a clear message informing users that their data (VMs, ISOs, etc.) is not automatically deleted.
  - The message provides the default paths for manual removal, improving user clarity during uninstallation.

* **2025-09-09 18:00:00** - **Documentation Update: `README.md` and `rc.d` Script**
  - Updated `README.md` to reflect the refactored structure, new features (live snapshots, vmnet), and updated installation instructions.
  - Modified `rc.d/bhyve-cli` to include `vmnet init` in `start_cmd` for comprehensive network initialization on boot.

* **2025-09-09 17:00:00** - **Bug Fix: TAP Interface Cleanup on VM Start**
  - Added a call to `cleanup_vm_network_interfaces` at the beginning of `cmd_start` in `src/lib/commands/vm/start.sh`.
  - This resolves the "ifconfig: BRDGADD tapX: Device busy" error when starting VMs, ensuring proper cleanup of network interfaces.

* **2025-09-09 16:00:00** - **Bug Fix: `switch` Commands Implicit `vmnet_init` Call**
  - Removed `switch` from the list of commands that trigger `cmd_vmnet_init` unconditionally in `src/lib/main_dispatcher.sh`.
  - This resolves the "Bridge already exists" error when running `switch` commands.

* **2025-09-09 15:00:00** - **Feature: Live Snapshot for Running VMs**
  - Modified `src/lib/commands/snapshot/create.sh` to use `SIGSTOP`/`SIGCONT` for suspending/resuming VMs during snapshot creation.
  - This enables "live" snapshots for running VMs, ensuring data consistency.

* **2025-09-09 15:00:00** - **Bug Fix: `vmnet list` and `vmnet init` Implicit Calls**
  - Corrected a design flaw in `src/lib/main_dispatcher.sh` where `cmd_vmnet_init` was being called unconditionally for `vmnet` commands.
  - This resolves the "Bridge already exists" error when running `vmnet list` or `vmnet init` on an already configured bridge.

* **2025-09-08 10:10:08** - **Feature: Robust Network Interface Cleanup & Enhanced VM Modify**
  - Implemented a robust cleanup mechanism for VM network interfaces (TAP devices) during VM stop/restart, ensuring no orphaned interfaces are left on the host.
  - Tested and verified various `vm modify` options: CPU, RAM, adding/removing disks, and adding/removing network interfaces.
  - Fixed `vm modify --remove-nic` to correctly destroy associated TAP interfaces.
  - Fixed `vm vm <subcommand> --help` functionality.

* **2025-09-08 08:19:50** - **Bug Fix: `vm import` Overwrite on Running VM**
  - Fixed a critical bug where importing a VM over an existing, running VM would not stop the running running process, leading to an inconsistent state.
  - The `import` command now checks if the target VM is running before an overwrite, stops it gracefully, and then proceeds with the import.

* **2025-03-09 22:35:13** - **Project Refactoring & Dev Environment Fix**
  - Completed a major structural refactoring, modularizing the entire codebase into `lib/commands`, `lib/functions`, and `lib/usage`.
  - The main script `src/bhyve-cli` now acts as a loader/dispatcher.
  - Fixed the script's library path to allow execution in a local development environment (not requiring `make install`).

* **2025-03-09 22:36:03** - **Code Cleanup**
  - Removed obsolete backup files (`install.sh-ori*`) from the `src/lib/commands/vm/` directory.

* **2025-03-09 22:39:14** - **Bug Fix: VM Status Consistency**
  - Identified and fixed a major bug causing inconsistent status reporting between `list` and `info` commands.
  - Consolidated all VM status logic into `lib/functions/pid.sh`, making process state (`ps`) the single source of truth.
  - Removed duplicated and unreliable status-file-based functions from `lib/functions/vm_actions.sh`.
  - Refactored `lib/commands/utils/list.sh` to use the new consolidated status functions.

* **2025-03-09 22:39:45** - **Refactoring Cleanup**
  - Renamed `src/lib/usage/vmnet_usage.sh` to `vmnet.sh` to improve naming consistency across the project.

* **2025-03-09 22:44:55** - **Bug Fix: Command Dispatcher & Usage**
  - Fixed a major design flaw in the main command dispatcher that prevented subcommand help (e.g., `vm --help`) from being displayed.
  - Implemented a two-level dispatcher system: `main_dispatcher.sh` now calls subcommand dispatchers (e.g., `vm/main.sh`).
  - Created `vm/main.sh` to handle all `vm` subcommands.
  - Added `cmd_vm_usage` to `usage/vm.sh` to provide a help summary for the `vm` module.
  - Corrected root privilege checks to allow displaying help messages without requiring `sudo`.

* **2025-03-09 10:00:00** - **Bug Fix: VM Status Reporting & Missing Function**
  - Implemented a placeholder `set_vm_status` function in `src/lib/functions/pid.sh` to resolve "command not found" error during VM startup.
  - Modified `get_vm_status` in `src/lib/functions/pid.sh` to correctly identify suspended VMs by recognizing the `TC` process state.

* **2025-03-09 10:00:00** - **Configuration: Git Ignore Update**
  - Added `bhyve_cli_checklist.md` to `.gitignore` as requested.

* **2025-03-09 10:00:00** - **Bug Fix: Info Command Status Display**
  - Modified `src/lib/commands/vm/info.sh` to use `get_vm_status` for accurate display of VM status, including 'suspended' state.

* **2025-03-09 10:00:00** - **Bug Fix: Resume Command Functionality**
  - Modified `src/lib/commands/vm/resume.sh` to correctly use `get_vm_status` with the VM's PID, resolving the issue where suspended VMs could not be resumed.

* **2025-03-09 10:00:00** - **Refactored Command Structure**
  - Moved `list`, `stopall`, `startall`, `verify` commands under the `vm` module.
  - Updated `src/lib/main_dispatcher.sh` to redirect these commands to `vm <command>`.
  - Updated `src/lib/usage/main.sh` to remove these commands from the top-level help.
  - Updated `src/lib/usage/vm.sh` to include these commands in the `vm` module's help.
  - Updated `bhyve_cli_checklist.md` to reflect the new command structure.
  - Fixed `vm verify` error for `templates` directory: Modified `verify.sh` to skip the `templates` directory during verification, as it's not a regular VM.

* **2025-03-09 10:00:00** - **Bug Fix: VM Start "Device Busy" Error**
  - Added `bhyvectl --vm="$VMNAME" --destroy` call before starting the VM in `src/lib/commands/vm/start.sh` to ensure a clean state and resolve "vm_reinit: device busy" errors.

* **2025-03-09 10:00:00** - **Bug Fix: Clone Command Robustness & Start Reliability**
  - Fixed `clone` command resume logic: Ensured source VM resumes after cloning if suspended.
  - Fixed cloned VM PID issue: Ensured `vm.pid` is not copied during cloning, leading to independent PIDs for cloned VMs.
  - Fixed `start` command `pgrep` regex: Updated regex in `pid.sh` and `start.sh` to correctly identify bhyve processes, resolving "Could not find bhyve process PID" errors (including the `pgrep` regex for `[[:<:]]` and `[[:>:]]` word boundaries).
  - Fixed `clone` command not copying `vm.log`: Ensured `vm.log` is not copied from source VM to cloned VM.

---

## Future TODO (Post-Checklist)

*   **Integrate with existing `vm-bhyve` installations.**
    *   **Goal:** Allow `bhyve-cli` to manage VMs created by the standard `vm-bhyve` tool.
    *   **Step 1: Detect `vm-bhyve` Directory.** Add logic to auto-detect the `vm_dir` path from `/etc/rc.conf`.
    *   **Step 2: Unify VM Listing.** Modify `vm list` to display VMs from both `bhyve-cli`'s own directory and the detected `vm-bhyve` directory.
    *   **Step 3: Adapt `vm info`.** Update the `info` command to parse `vm-bhyve`'s configuration file format.
    *   **Step 4: Adapt Other Commands.** Incrementally update other commands (`start`, `stop`, `snapshot`, `export`, etc.) to work with `vm-bhyve`'s structure and conventions.
*   **Rename VM on Import.**
    *   **Goal:** Allow specifying a new name for a VM during the import process.
    *   **Implementation:** Modify the `vm import` command to accept an optional second argument: `vm import <archive_path> [new_vm_name]`.
    *   **Logic:** If `new_vm_name` is provided, the script will extract the VM, modify the `VMNAME` in its `vm.conf`, and save the VM directory under the new name.
*   **Display VNC Info in `vm list`.**
    *   **Goal:** Add a 'VNC Port' column to the `vm list` output for quick overview.
    *   **Implementation:** Modify `vm list` to read `VNC_PORT` from `vm.conf` and display it in a new column. Show '-' if not configured.