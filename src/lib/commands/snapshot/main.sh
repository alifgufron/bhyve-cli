#!/usr/local/bin/bash

# === Subcommand: snapshot ===
cmd_snapshot() {
  if [ -z "$1" ]; then
    cmd_snapshot_usage
    exit 1
  fi

  local SUBCOMMAND="$1"
  shift

  case "$SUBCOMMAND" in
    create)
      cmd_snapshot_create "$@"
      ;;
    list)
      cmd_snapshot_list "$@"
      ;;
    revert)
      cmd_snapshot_revert "$@"
      ;;
    delete)
      cmd_snapshot_delete "$@"
      ;;
    --help|help)
      cmd_snapshot_usage
      ;;
    *)
      display_and_log "ERROR" "Invalid subcommand for 'snapshot': $SUBCOMMAND"
      cmd_snapshot_usage
      exit 1
      ;;
  esac
}
