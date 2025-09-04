#!/usr/local/bin/bash

# === Subcommand: vm ===
cmd_vm() {
  if [ -z "$1" ]; then
    cmd_vm_usage
    exit 1
  fi

  local SUBCOMMAND="$1"
  shift

  case "$SUBCOMMAND" in
    create)
      cmd_create "$@"
      ;;
    delete)
      cmd_delete "$@"
      ;;
    install)
      cmd_install "$@"
      ;;
    start)
      cmd_start "$@"
      ;;
    stop)
      cmd_stop "$@"
      ;;
    restart)
      cmd_restart "$@"
      ;;
    console)
      cmd_console "$@"
      ;;
    autostart)
      cmd_autostart "$@"
      ;;
    modify)
      cmd_modify "$@"
      ;;
    clone)
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
      cmd_import "$@"
      ;;
    suspend)
      cmd_suspend "$@"
      ;;
    resume)
      cmd_resume "$@"
      ;;
    vnc)
      cmd_vnc "$@"
      ;;
    list)
      cmd_list "$@"
      ;;
    stopall)
      cmd_stopall "$@"
      ;;
    startall)
      cmd_startall "$@"
      ;;
    verify)
      cmd_verify "$@"
      ;;
    --help|-h)
      cmd_vm_usage
      ;;
    *)
      display_and_log "ERROR" "Invalid subcommand for 'vm': $SUBCOMMAND"
      cmd_vm_usage
      exit 1
      ;;
  esac
}
