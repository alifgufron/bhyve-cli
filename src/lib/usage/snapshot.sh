#!/usr/local/bin/bash

# === Usage function for snapshot ===
cmd_snapshot_usage() {
  echo_message "Usage: $(basename "$0") snapshot <subcommand> [options/arguments]"
  echo_message "\nSubcommands:"
  echo_message "  create <vmname> [snapshot_name] - Creates a new snapshot of the VM. If snapshot_name is omitted, a timestamped name is generated."
  echo_message "  list <vmname>                   - Lists all snapshots for the specified VM."
  echo_message "  revert <vmname> <snapshot_name> - Reverts the VM to a specified snapshot. VM must be stopped."
  echo_message "  delete <vmname> <snapshot_name> - Deletes a specified snapshot."
  echo_message "\nExamples:"
  echo_message "  $(basename "$0") snapshot create myvm initial_state"
  echo_message "  $(basename "$0") snapshot list myvm"
  echo_message "  $(basename "$0") snapshot revert myvm initial_state"
  echo_message "  $(basename "$0") snapshot delete myvm initial_state"
}
