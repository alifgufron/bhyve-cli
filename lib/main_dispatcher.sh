#!/usr/local/bin/bash

# === Main Command Dispatcher ===
main_dispatcher() {
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
