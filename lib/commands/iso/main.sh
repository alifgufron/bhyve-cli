#!/usr/local/bin/bash

# === Subcommand: iso ===
cmd_iso() {
  if [ -z "$1" ]; then
    cmd_iso_usage
    exit 1
  fi

  local SUBCOMMAND="$1"
  shift

  case "$SUBCOMMAND" in
    list)
      cmd_iso_list
      ;;
    http://*|https://*)
      cmd_iso_download "$SUBCOMMAND"
      ;;
    delete)
      cmd_iso_delete "$@"
      ;;
    *)
      display_and_log "ERROR" "Invalid subcommand or URL for 'iso': $SUBCOMMAND"
      cmd_iso_usage
      exit 1
      ;;
  esac
}
