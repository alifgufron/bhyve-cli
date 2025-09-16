# Progress Log for bhyve-cli

This file tracks completed tasks and major changes.

---

* **2025-09-16** - **Refactor: Centralized Datastore Integration**
    *   **Fix:** Created a centralized `find_any_vm` function in `lib/functions/config.sh` to reliably locate VMs from any datastore (`bhyve-cli` or `vm-bhyve`), replacing multiple broken implementations.
    *   **Fix:** Refactored `vm stop`, `vm start`, `vm info`, `vm suspend`, and `vm resume` to use the new `find_any_vm` function. This fixed major bugs preventing these commands from working on VMs outside of the default datastores.
    *   **Fix:** Corrected latent PID management bugs in the refactored commands by ensuring the full, correct VM directory path is used for PID file operations.
    *   **Fix:** Refactored `vm export` to use `find_any_vm` and corrected a hardcoded `tar` path bug that prevented exporting from non-default datastores.
    *   **Fix:** Corrected argument parsing and a latent bug in the `wait_for_vm_status` helper function in `lib/functions/vm_actions.sh`.
    *   **Status:** The core VM discovery logic is now robust. `stop`, `start`, `info`, `suspend`, `resume` are verified. `export` is refactored but pending final verification.

* **TODO (In Progress):**
    *   **Verify `vm export`:** Run the final verification test for `vm export` that was previously cancelled.
    *   **Fix `vm import`:** Refactor to support a `--datastore` argument.
    *   **Fix `snapshot` commands:** Refactor `snapshot create`, `list`, `revert`, and `delete` to use `find_any_vm` and work across all datastores.

## Branch: v1.1.2

* **2025-09-15** - **Enhancement: Comprehensive Network Cleanup on Uninstall**
    *   **Added:** Created `src/lib/functions/network_cleanup_all.sh` to remove all `bhyve-cli` created network interfaces (bridges and TAP devices) during uninstallation.
    *   **Changed:** Modified the `Makefile`'s `uninstall` target to execute `network_cleanup_all.sh`, ensuring a cleaner removal of network configurations.

* **2025-09-15** - **Bug Fix: `bhyve-cli init` Command Path in Error Message**
    *   **Fix:** Corrected the error message for uninitialized `bhyve-cli` to display `bhyve-cli init` instead of the absolute path (`/usr/local/sbin/bhyve-cli init`).
    *   **Logic:** Implemented by using `$(basename "$0")` in `src/lib/core.sh` and `src/lib/functions/config.sh`.

* **2025-09-15** - **Bug Fix: `vm list` Formatting & `vm-bhyve` Datastore Name**
    *   **Fix:** Corrected the display name for the primary `vm-bhyve` datastore in `vm list` output from its basename (e.g., "bhvye") to "default".
    *   **Fix:** Modified `vm list` to display `VMNAME` only for `bhyve-cli` VMs (removed `(DATASTORE)` suffix), relying on the dedicated `DATASTORE` column for clarity.
    *   **Enhancement:** Adjusted column widths in `vm list` output for both data and header rows to `%-40s` for "VM NAME" and `%-20s` for "DATASTORE" to ensure proper alignment and visual neatness, accommodating longer names.

* **2025-09-15** - **Bug Fix: Unintentional Network Cleanup Execution**
    *   **Fix:** Resolved an issue where `network_cleanup_all.sh` was unintentionally executed during normal `bhyve-cli` operations.
    *   **Logic:** Implemented by excluding `network_cleanup_all.sh` from the sourced helper functions in `src/bhyve-cli`.

* **2025-09-15** - **Bug Fix: `vm list` Formatting & `vm-bhyve` Datastore Name**
    *   **Fix:** Corrected the display name for the primary `vm-bhyve` datastore in `vm list` output from its basename (e.g., "bhvye") to "default".
    *   **Fix:** Modified `vm list` to display `VMNAME (DATASTORE)` for `bhyve-cli` VMs, resolving confusion with duplicate VM names across datastores and improving output clarity.
    *   **Enhancement:** Increased the width of the "VM NAME" column to `%-40s` and the "DATASTORE" column to `%-25s` in `vm list` output to accommodate longer names and ensure proper alignment.

* **2025-09-15** - **Enhancement: `Makefile` Root Privilege Check & `bhyve-cli init` Interactive Configuration**
    *   **Enhancement:** Added a root privilege check to `install` and `uninstall` targets in `Makefile`, providing clear error messages if not run as root.
    *   **Enhancement:** Modified `bhyve-cli init` to interactively prompt the user for the desired ISO storage directory and the default VM datastore path.
    *   **Logic:** The `init` command now updates the main configuration file (`bhyve-cli.conf`) and `/etc/rc.conf` with the user-defined paths.

* **2025-09-15** - **Bug Fix: `vm delete` Syntax Error & Datastore/vm-bhyve Integration Updates**
    *   **Fix:** Resolved `syntax error: unexpected end of file` in `src/lib/commands/vm/delete.sh` by completing truncated `case` and function blocks.
    *   **Enhancement:** Implemented and integrated datastore management features, including `datastore add`, `datastore list`, `datastore delete` commands.
    *   **Enhancement:** Updated `vm create` to support `--datastore` option.
    *   **Enhancement:** Enhanced `vm list` to display VMs from multiple `bhyve-cli` and `vm-bhyve` datastores, including correct datastore naming.
    *   **Refinement:** Improved `src/lib/functions/config.sh` with `get_datastore_path`, `get_all_bhyve_cli_datastores`, and `find_vm_in_datastores` for robust datastore handling.
    *   **Refinement:** Integrated `datastore` command into `main_dispatcher.sh` and `src/lib/usage/main.sh`.

* **2025-09-14** - **Enhancement: Advanced `vm-bhyve` Datastore Detection**
    *   **Enhancement:** Re-engineered `vm-bhyve` integration to correctly detect and name all datastores.
    *   **Logic:** The script now reads the primary datastore from `/etc/rc.conf`, then parses `<primary>/.config/system.conf` to find and identify any additional datastores.
    *   **Fix:** As part of this, a bug was fixed where `vm list` failed in a `sudo` context because `ls` was not in the minimal `PATH`. This was resolved by using `/bin/ls`.
    *   **Result:** The `vm list` command now accurately displays all VMs from all `vm-bhyve` datastores with their correct datastore names.

---

* **2025-09-13** - **Bug Fix: `make install` Directory Creation**
    * Fixed `make install` failure due to `No such file or directory` error for `vm.d`.
    * Ensured explicit creation of parent configuration directory (`/usr/local/etc/bhyve-cli`) before `vm.d`.

* **2025-09-13** - **Bug Fix: `bhyve-cli init` Redundant Copies**
    * Removed incorrect and redundant `rc.d` script copying from `bhyve-cli init`.
    * Removed incorrect and redundant firmware files copying from `bhyve-cli init`.
    * These tasks are correctly handled by `make install`.

* **2025-09-13** - **Enhancement: `vm list` - VNC Port Column & Formatting**
    * Added a "VNC PORT" column to the `vm list` output.
    * Adjusted column widths for better alignment and readability, especially after adding the new column.
    * Displays the `VNC_PORT` from `vm.conf` or '-' if not configured.

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
    * **`vm export` - Enhanced Compression & Usage**: Added `--compression` flag to support `gz`, `bz2`, `xz`, `lz4`, `zst` formats. Implemented automatic file extension handling based on compression type.
    * **`vm export` - Suspend/Stop Robustness:**
        * Removed placeholder `set_vm_status` call from `src/lib/commands/vm/suspend.sh`.
        * Implemented `wait_for_vm_status` helper function to robustly wait for a VM to reach a specific status (suspended or stopped).
        * Modified `vm export` to use `wait_for_vm_status` after calling `cmd_suspend` and `cmd_stop`.
        * Refined `is_vm_running` to accurately reflect the "running" status by checking the actual process state.
    * **`vm list` - Correct CPU/RAM Display for `vm-bhyve` and `bhyve-cli` VMs:**
        * Modified `vm list` to correctly parse and display CPU and RAM information for `vm-bhyve` VMs.
        * Adjusted the logic to conditionally assign CPU/RAM values based on VM type.
    * **`vm export` - Add Date to Filename:**
        * Modified `vm export` to include the current date (`YYYY_MM_DD`) in the exported archive filename.


* **2025-09-10 00:00:00** - **Enhancement: Add Data Deletion Notice to Uninstall**
  - Modified the `uninstall` target in the `Makefile` to display a clear message informing users that their data (VMs, ISOs, etc.) is not automatically deleted.
  - The message provides the default paths for manual removal, improving user clarity during uninstallation.

* **2025-09-09 18:00:00** - **Documentation Update: `README.md` and `rc.d` Script**
  - Updated `README.md` to reflect the refactored structure, new features (live snapshots, vmnet), and updated installation instructions.
  - Modified `rc.d/bhyve-cli` to include `vmnet init` in `start_cmd` for comprehensive network initialization on boot.

* **2025-09-09 17:00:00** - **Bug Fix: TAP Interface Cleanup on VM Start**
  - Added a call to `cleanup_vm_network_interfaces` at the beginning of `cmd_start`.
  - This resolves the "ifconfig: BRDGADD tapX: Device busy" error when starting VMs.

* **2025-09-09 16:00:00** - **Bug Fix: `switch` Commands Implicit `vmnet_init` Call**
  - Removed `switch` from the list of commands that trigger `cmd_vmnet_init` unconditionally.
  - This resolves the "Bridge already exists" error when running `switch` commands.

* **2025-09-09 15:00:00** - **Feature: Live Snapshot for Running VMs**
  - Modified `src/lib/commands/snapshot/create.sh` to use `SIGSTOP`/`SIGCONT` for suspending/resuming VMs during snapshot creation.
  - This enables "live" snapshots for running VMs, ensuring data consistency.

* **2025-09-09 15:00:00** - **Bug Fix: `vmnet list` and `vmnet init` Implicit Calls**
  - Corrected a design flaw where `cmd_vmnet_init` was being called unconditionally for `vmnet` commands.
  - This resolves the "Bridge already exists" error when running `vmnet list` or `vmnet init`.

* **2025-09-08 10:10:08** - **Feature: Robust Network Interface Cleanup & Enhanced VM Modify**
  - Implemented a robust cleanup mechanism for VM network interfaces (TAP devices) during VM stop/restart.
  - Tested and verified various `vm modify` options: CPU, RAM, adding/removing disks, and adding/removing network interfaces.
  - Fixed `vm modify --remove-nic` to correctly destroy associated TAP interfaces.
  - Fixed `vm vm <subcommand> --help` functionality.

* **2025-09-08 08:19:50** - **Bug Fix: `vm import` Overwrite on Running VM**
  - Fixed a critical bug where importing a VM over an existing, running VM would not stop the running process.
  - The `import` command now checks if the target VM is running before an overwrite, stops it gracefully, and then proceeds.

* **2025-03-09 22:35:13** - **Project Refactoring & Dev Environment Fix**
  - Completed a major structural refactoring, modularizing the entire codebase into `lib/commands`, `lib/functions`, and `lib/usage`.
  - The main script `src/bhyve-cli` now acts as a loader/dispatcher.
  - Fixed the script's library path to allow execution in a local development environment (not requiring `make install`).

* **2025-03-09 22:36:03** - **Code Cleanup**
  - Removed obsolete backup files (`install.sh-ori*`) from the `src/lib/commands/vm/` directory.

* **2025-03-09 22:39:14** - **Bug Fix: VM Status Consistency**
  - Identified and fixed a major bug causing inconsistent status reporting between `list` and `info` commands.
  - Consolidated all VM status logic into `lib/functions/pid.sh`.

* **2025-03-09 22:39:45** - **Refactoring Cleanup**
  - Renamed `src/lib/usage/vmnet_usage.sh` to `vmnet.sh` to improve naming consistency across the project.

* **2025-03-09 22:44:55** - **Bug Fix: Command Dispatcher & Usage**
  - Fixed a major design flaw in the main command dispatcher that prevented subcommand help from being displayed.
  - Implemented a two-level dispatcher system.

* **2025-03-09 10:00:00** - **Bug Fix: VM Status Reporting & Missing Function**
  - Implemented a placeholder `set_vm_status` function in `src/lib/functions/pid.sh`.

* **2025-03-09 10:00:00** - **Configuration: Git Ignore Update**
  - Added `bhyve_cli_checklist.md` to `.gitignore`.

* **2025-03-09 10:00:00** - **Bug Fix: Info Command Status Display**
  - Modified `src/lib/commands/vm/info.sh` to use `get_vm_status` for accurate display of VM status.

* **2025-03-09 10:00:00** - **Bug Fix: Resume Command Functionality**
  - Modified `src/lib/commands/vm/resume.sh` to correctly use `get_vm_status` with the VM's PID.

* **2025-03-09 10:00:00** - **Refactored Command Structure**
  - Moved `list`, `stopall`, `startall`, `verify` commands under the `vm` module.

* **2025-03-09 10:00:00** - **Bug Fix: VM Start "Device Busy" Error**
  - Added `bhyvectl --vm="$VMNAME" --destroy` call before starting the VM in `src/lib/commands/vm/start.sh`.

* **2025-03-09 10:00:00** - **Bug Fix: Clone Command Robustness & Start Reliability**
  - Fixed `clone` command resume logic.
  - Fixed cloned VM PID issue.
  - Fixed `start` command `pgrep` regex.
  - Fixed `clone` command not copying `vm.log`.

---

## Future TODO (Post-Checklist)

*   **Integrate with existing `vm-bhyve` installations.**
    *   **Goal:** Allow `bhyve-cli` to manage VMs created by the standard `vm-bhyve` tool.
    *   **Step 1: Detect `vm-bhyve` Directory.** Add logic to auto-detect the `vm_dir` path from `/etc/rc.conf`.
    *   **Step 2: Unify VM Listing.** Modify `vm list` to display VMs from both `bhyve-cli`'s own directory and the detected `vm-bhyve` directory.
    *   **Step 3: Adapt `vm info`.** Update the `info` command to parse `vm-bhyve`'s configuration file format.
    *   **Step 4: Adapt Other Commands.** Incrementally update other commands (`start`, `stop`, `snapshot`, `export`, etc.) to work with `vm-bhyve`'s structure and conventions.
*   **Datastore Management for bhyve-cli.**
    *   **Goal:** Allow managing `bhyve-cli` datastores directly from the command line.
    *   **Implementation:**
        *   `datastore list`: List all configured `bhyve-cli` datastores.
        *   `datastore add <name> <path>`: Add a new datastore.
        *   `datastore delete <name>`: Remove a datastore.
        *   `vm create --datastore <name>`: Allow specifying a datastore during VM creation.
*   **Rename VM on Import.**
    *   **Goal:** Allow specifying a new name for a VM during the import process.
    *   **Implementation:** Modify the `vm import` command to accept an optional second argument: `vm import <archive_path> [new_vm_name]`.
    *   **Logic:** If `new_vm_name` is provided, the script will extract the VM, modify the `VMNAME` in its `vm.conf`, and save the VM directory under the new name.
*   **Display VNC Info in `vm list`.**
    *   **Goal:** Add a 'VNC Port' column to the `vm list` output for quick overview.
    *   **Implementation:** Modify `vm list` to read `VNC_PORT` from `vm.conf` and display it in a new column. Show '-' if not configured.