#!/usr/local/bin/bash

# === Main Command Dispatcher ===
main_dispatcher() {
  local command="$1"
  shift

  # Initialize network environment for commands that need it
  case "$command" in
    create|delete|install|start|restart|modify|clone|import|suspend|resume|vnc|stopall|startall)
      cmd_vmnet_init
      ;;
  esac

  case "$command" in
    init)
      cmd_init "$@"
      ;;
    vm)
      cmd_vm "$@"
      ;;
    template)
      cmd_template "$@"
      ;;
    snapshot)
      cmd_snapshot "$@"
      ;;
    iso)
      cmd_iso "$@"
      ;;
    switch)
      cmd_switch "$@"
      ;;
    vmnet)
      cmd_vmnet "$@"
      ;;
    datastore)
      cmd_datastore "$@"
      ;;
    # Direct commands from old structure
    logs)
      cmd_logs "$@"
      ;;
    --version|-v)
      echo_message "bhyve-cli version $VERSION"
      ;;
    --help|-h)
      main_usage
      ;;
    # Deprecated direct commands: inform user and show main usage
    create|delete|install|start|stop|restart|console|autostart|modify|clone|info|resize-disk|export|import|suspend|resume|vnc|list|verify|stopall|startall)
      main_usage
      exit 1
      ;;
    *)
      main_usage
      exit 1
      ;;
  esac
}