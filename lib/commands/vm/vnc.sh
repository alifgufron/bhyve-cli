#!/usr/local/bin/bash

# === Subcommand: vnc ===
cmd_vnc() {
  
  if [ -z "$1" ]; then
    cmd_vnc_usage
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  if [ -z "$VNC_PORT" ]; then
    display_and_log "ERROR" "VNC is not configured for VM '$VMNAME'. Please use 'create --vnc-port <port>' or 'modify --vnc-port <port>'."
    exit 1
  fi

  if ! is_vm_running "$VMNAME"; then
    display_and_log "ERROR" "VM '$VMNAME' is not running. Please start the VM first."
    exit 1
  fi

  echo_message "Connecting to VNC console for VM '$VMNAME'."
  echo_message "Please ensure you have a VNC client installed (e.g., \`vncviewer\`)."
  echo_message "You can connect to: localhost:$VNC_PORT"

  # Attempt to launch vncviewer if available
  if command -v vncviewer >/dev/null 2>&1; then
    display_and_log "INFO" "Launching vncviewer..."
    vncviewer "localhost::$VNC_PORT" &
  else
    display_and_log "WARNING" "vncviewer not found. Please connect manually to localhost:$VNC_PORT with your VNC client."
  fi
  
}

