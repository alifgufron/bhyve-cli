#!/usr/local/bin/bash

# === Main Usage Function ===
main_usage() {
  echo_message "Usage: $0 <command> [options/arguments]"
  echo_message " "
  echo_message "Available Commands:"
  echo_message "  init          - Initialize bhyve-cli configuration."
  echo_message "  vm            - Main command for managing virtual machines."
  echo_message "  logs          - Display real-time logs for a VM."
  echo_message "  template      - Manage VM templates (create, list, delete)."
  echo_message "  snapshot      - Manage VM snapshots (create, list, revert, delete)."
  echo_message "  iso           - Manage ISO images (list and download)."
  echo_message "  switch        - Manage network bridges and physical interfaces."
  echo_message "  vmnet         - Manage isolated virtual networks for VMs."
  echo_message " "
  echo_message "For detailed usage of each command, use: $0 <command> --help"
}
