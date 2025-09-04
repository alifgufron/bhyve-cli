#!/usr/local/bin/bash

# === Subcommand: template ===
cmd_template() {
  if [ -z "$1" ]; then
    cmd_template_usage
    exit 1
  fi

  local SUBCOMMAND="$1"
  shift

  case "$SUBCOMMAND" in
    create)
      cmd_template_create "$@"
      ;;
    list)
      cmd_template_list "$@"
      ;;
    delete)
      cmd_template_delete "$@"
      ;;
    --help|help)
      cmd_template_usage
      ;;
    *)
      display_and_log "ERROR" "Invalid subcommand for 'template': $SUBCOMMAND"
      cmd_template_usage
      exit 1
      ;;
  esac
}
