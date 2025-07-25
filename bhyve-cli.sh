#!/usr/local/bin/bash

# === Ensure Script is Run with Bash ===
if [ -z "$BASH_VERSION" ]; then
  echo "[ERROR] This script requires Bash to run. Please execute with 'bash <script_name>' or ensure your shell is Bash." >&2
  exit 1
fi

# === Global Variables & Paths ===
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
CONFIG_DIR="/usr/local/etc/bhyve-cli"
MAIN_CONFIG_FILE="$CONFIG_DIR/bhyve-cli.conf"
VM_CONFIG_BASE_DIR="$CONFIG_DIR/vm.d"
SWITCH_CONFIG_FILE="$CONFIG_DIR/switch.conf"
VERSION="1.3.0-super-modular"

# === Bhyve Binaries Paths ===
BHYVE="/usr/sbin/bhyve"
BHYVECTL="/usr/sbin/bhyvectl"
BHYVELOAD="/usr/sbin/bhyveload"

# Load core functions and variables
source "$SCRIPT_DIR/lib/core.sh"

# === Source All Library Files ===

# Load Helper Functions
for func_file in "$SCRIPT_DIR"/lib/functions/*.sh; do
    source "$func_file"
done

# Load Usage Messages
for usage_file in "$SCRIPT_DIR"/lib/usage/*.sh; do
    source "$usage_file"
done

# Load Command Implementations
for cmd_file in "$SCRIPT_DIR"/lib/commands/**/*.sh; do
    source "$cmd_file"
done

# Load the main dispatcher
source "$SCRIPT_DIR/lib/main_dispatcher.sh"

# === Main Execution Logic ===
main() {
  # Load main config to get global settings like log file path
  load_config

  # Check initialization status (unless the command is 'init')
  check_initialization "$1"

  # Most commands require root privileges
  case "$1" in
    list|info|status|--version|-v|--help|-h)
      # These commands are safe to run as a non-root user
      ;;
    *)
      check_root
      ;;
  esac

  # Pass all arguments to the dispatcher
  main_dispatcher "$@"
}

# === Execute Main Function ===
main "$@"
