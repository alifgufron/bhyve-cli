#!/usr/local/bin/bash

# === Subcommand: autostart ===
cmd_autostart() {
  if [ -z "$2" ]; then
    cmd_autostart_usage
    exit 1
  fi

  VMNAME="$1"
  ACTION="$2"
  CONF_FILE="$VM_CONFIG_BASE_DIR/$VMNAME/vm.conf"

  if [ ! -f "$CONF_FILE" ]; then
    display_and_log "ERROR" "VM configuration '$VMNAME' not found."
    exit 1
  fi

  case "$ACTION" in
    enable)
      sed -i '' 's/^AUTOSTART=.*/AUTOSTART=yes/' "$CONF_FILE"
      display_and_log "INFO" "Autostart enabled for VM '$VMNAME'."
      ;;
    disable)
      sed -i '' 's/^AUTOSTART=.*/AUTOSTART=no/' "$CONF_FILE"
      display_and_log "INFO" "Autostart disabled for VM '$VMNAME'."
      ;;
    *)
      cmd_autostart_usage
      exit 1
      ;;
  esac
}
