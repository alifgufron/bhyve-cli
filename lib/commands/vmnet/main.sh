#!/usr/local/bin/bash

# === Subcommand: vmnet ===
cmd_vmnet() {
  if [ -z "$1" ]; then
    cmd_vmnet_usage
    exit 1
  fi

  local SUBCOMMAND="$1"
  shift

  case "$SUBCOMMAND" in
    create)
      cmd_vmnet_create "$@"
      ;;
    list)
      cmd_vmnet_list "$@"
      ;;
    destroy)
      cmd_vmnet_destroy "$@"
      ;;
    init)
      cmd_vmnet_init "$@"
      ;;
    --help|help)
      cmd_vmnet_usage
      ;;
    *)
      display_and_log "ERROR" "Invalid subcommand for 'vmnet': $SUBCOMMAND"
      cmd_vmnet_usage
      exit 1
      ;;
  esac
}
