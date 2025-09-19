#!/usr/local/bin/bash

# === Subcommand: vm ===
cmd_vm() {
  if [ -z "$1" ]; then
    cmd_vm_usage
    exit 1
  fi

  local SUBCOMMAND="$1"
  shift

  # Check for --help flag on subcommands
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    case "$SUBCOMMAND" in
      create)       cmd_create_usage; exit 0 ;;
      delete)       cmd_delete_usage; exit 0 ;;
      install)      cmd_install_usage; exit 0 ;;
      start)        cmd_start_usage; exit 0 ;;
      stop)         cmd_stop_usage; exit 0 ;;
      restart)      cmd_restart_usage; exit 0 ;;
      console)      cmd_console_usage; exit 0 ;;
      autostart)    cmd_autostart_usage; exit 0 ;;
      modify)       cmd_modify_usage; exit 0 ;;
      clone)        cmd_clone_usage; exit 0 ;;
      info)         cmd_info_usage; exit 0 ;;
      resize-disk)  cmd_resize_disk_usage; exit 0 ;;
      export)       cmd_export_usage; exit 0 ;;
      import)       cmd_import_usage; exit 0 ;;
      suspend)      cmd_suspend_usage; exit 0 ;;
      resume)       cmd_resume_usage; exit 0 ;;

      list)         cmd_list_usage; exit 0 ;;
      stopall)      cmd_stopall_usage; exit 0 ;;
      startall)     cmd_startall_usage; exit 0 ;;
      verify)       cmd_verify_usage; exit 0 ;;
      *)            cmd_vm_usage; exit 0 ;;
    esac
  fi

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
