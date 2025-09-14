#!/usr/local/bin/bash

# Main dispatcher for the 'datastore' command
cmd_datastore() {
  # Source required libraries
  . "$LIB_DIR/functions/config.sh"
  . "$LIB_DIR/functions/ui.sh"

  # Load main configuration
  load_config

  local subcommand="$1"
  shift # Remove subcommand from argument list

  # === DATSTORE SUBCOMMAND DISPATCHER ===
  case "$subcommand" in
    list)
      cmd_datastore_list "$@"
      ;;
    add)
      cmd_datastore_add "$@"
      ;;
    delete)
      cmd_datastore_delete "$@"
      ;;
    *)
      datastore_usage
      exit 1
      ;;
  esac
}