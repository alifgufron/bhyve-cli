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
VERSION="1.2.0-modular"

# === Bhyve Binaries Paths ===
BHYVE="/usr/sbin/bhyve"
BHYVECTL="/usr/sbin/bhyvectl"
BHYVELOAD="/usr/sbin/bhyveload"

# === Source Library Files ===
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/usage.sh"
source "$SCRIPT_DIR/lib/commands/vm.sh"
source "$SCRIPT_DIR/lib/commands/switch.sh"
source "$SCRIPT_DIR/lib/commands/iso.sh"
source "$SCRIPT_DIR/lib/commands/utils.sh"
source "$SCRIPT_DIR/lib/commands/vmnet.sh"

# === Main Command Dispatcher ===
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

  local command="$1"
  shift

  case "$command" in
    init)
      cmd_init "$@"
      ;;
    create)
      cmd_vmnet_init
      cmd_create "$@"
      ;;
    delete)
      cmd_delete "$@"
      ;;
    install)
      cmd_vmnet_init
      cmd_install "$@"
      ;;
    start)
      cmd_vmnet_init
      cmd_start "$@"
      ;;
    stop)
      cmd_stop "$@"
      ;;
    restart)
      cmd_vmnet_init
      cmd_restart "$@"
      ;;
    console)
      cmd_console "$@"
      ;;
    logs)
      cmd_logs "$@"
      ;;
    list)
      cmd_list "$@"
      ;;
    status)
      cmd_status "$@"
      ;;
    autostart)
      cmd_autostart "$@"
      ;;
    modify)
      cmd_vmnet_init
      cmd_modify "$@"
      ;;
    clone)
      cmd_vmnet_init
      cmd_clone "$@"
      ;;
    info)
      cmd_info "$@"
      ;;
    resize-disk)
      cmd_resize_disk "$@"
      ;;
    export)
      cmd_export "$@"
      ;;
    import)
      cmd_vmnet_init
      cmd_import "$@"
      ;;
    template)
      cmd_template "$@"
      ;;
    verify)
      cmd_verify "$@"
      ;;
    snapshot)
      cmd_snapshot "$@"
      ;;
    suspend)
      cmd_vmnet_init
      cmd_suspend "$@"
      ;;
    resume)
      cmd_vmnet_init
      cmd_resume "$@"
      ;;
    iso)
      cmd_iso "$@"
      ;;
    vnc)
      cmd_vmnet_init
      cmd_vnc "$@"
      ;;
    switch)
      cmd_vmnet_init
      cmd_switch "$@"
      ;;
    vmnet)
      cmd_vmnet_init
      cmd_vmnet "$@"
      ;;
    stopall)
      cmd_vmnet_init
      cmd_stopall "$@"
      ;;
    startall)
      cmd_vmnet_init
      cmd_startall "$@"
      ;;
    --version|-v)
      echo_message "bhyve-cli version $VERSION"
      ;;
    --help|-h)
      main_usage
      ;;
    *)
      main_usage
      exit 1
      ;;
  esac
}

# === Execute Main Function ===
main "$@"