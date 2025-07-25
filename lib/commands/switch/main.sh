#!/usr/local/bin/bash

cmd_switch() {
  if [ -z "$1" ]; then
    cmd_switch_usage
    exit 1
  fi

  local SUBCOMMAND="$1"
  shift

  case "$SUBCOMMAND" in
    init)
      cmd_switch_init
      ;;
    add)
      cmd_switch_add "$@"
      ;;
    list)
      cmd_switch_list
      ;;
    destroy)
      cmd_switch_destroy "$@"
      ;;
    delete)
      cmd_switch_delete "$@"
      ;;
    --help|help)
      cmd_switch_usage
      ;;
    *)
      display_and_log "ERROR" "Invalid subcommand for 'switch': $SUBCOMMAND"
      cmd_switch_usage
      exit 1
      ;;
  esac
}
