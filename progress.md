**2025-09-16 19:50**
- **feat(vm):** Implement static MAC address generation during VM creation.
- **refactor(vm):** Centralize MAC generation into a `generate_mac_address` function in `network.sh`.
- **fix(info):** Correctly display disk information after creation format change (DISK -> DISK_0).
- **style(info):** Remove debug messages and relabel 'Live TAP' to 'TAP' for cleaner output.

**2025-09-16 21:47**
- **fix(core):** End-to-end stabilization of VM lifecycle (create, install, start, info, console).
- **fix(net):** Reworked network argument generation to use dynamic TAP interfaces, fixing VMs starting without networking.
- **fix(start):** Re-implemented uninstalled VM check to prevent errors on empty disks.
- **fix(start)::** Resolved multiple shell syntax errors (`nameref`, stray numbers, missing quotes) causing start failures.
- **fix(info)::** Corrected logic to reliably find and display active TAP interfaces for running VMs.
- **fix(install):** Ensured TAP interfaces are properly cleaned up after installation.
- **refactor(core):** Modularized bootloader and VNC argument generation into helper functions.

**2025-09-17 10:45**
- **fix(core):** Refactored `load_vm_config` in `src/lib/functions/config.sh` to correctly accept the full VM directory path, resolving path duplication issues.
- **fix(vm):** Corrected `load_vm_config` calls in `vm clone`, `vm info`, `vm console`, `vm install`, `vm restart`, `vm start`, `vm stop` to pass the full VM directory path, ensuring proper VM configuration loading across all datastores.
- **fix(snapshot):** Corrected `load_vm_config` calls in `snapshot create` and `snapshot revert` for accurate snapshot operations.
- **feat(vm):** Verified `vm clone` functionality, including cloning to different datastores and successful startup of cloned VMs.

**2025-09-17 12:00**
- **feat:** Enhance VM management and fix datastore compatibility
  - Refactored `load_vm_config` to correctly handle full VM directory paths, resolving path duplication issues.
  - Updated numerous commands (`vm clone`, `vm modify`, `vm restart`, `vm suspend`, `vm resume`, `vm autostart`, `vm export`, `vm import`, `vm resize-disk`, `vm stop`, `vm stopall`, `vm verify`, `vm console`, `snapshot create`, `snapshot revert`, `vm install`, `vm list`) to correctly utilize the updated `load_vm_config` and `find_any_vm` functions, ensuring proper VM configuration loading and operation across all datastores.
  - Fixed `vm list` to prevent variable pollution between VM entries, ensuring accurate display of VNC ports and other VM properties.
  - Implemented robust `vm resize-disk` functionality, including correct disk path resolution and `vm.conf` updates for `DISK_0_SIZE`.
  - Verified functionality of `vm clone`, `vm modify`, `vm restart`, `vm suspend`, `vm resume`, `vm autostart`, `vm export`, `vm import`, `vm resize-disk`, `vm stop`, `vm stopall`, and `vm verify` commands.