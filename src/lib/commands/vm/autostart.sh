#!/usr/local/bin/bash

# === Subcommand: autostart ===
cmd_autostart() {
  if [ -z "$2" ]; then
    cmd_autostart_usage
    exit 1
  fi

  VMNAME="$1"
  ACTION="$2"

  # Find VM across all datastores
  local found_vm_info
  found_vm_info=$(find_any_vm "$VMNAME")

  if [ -z "$found_vm_info" ]; then
    display_and_log "ERROR" "VM '$VMNAME' not found in any bhyve-cli or vm-bhyve datastores."
    exit 1
  fi

  local vm_source
  local datastore_name
  local datastore_path
  vm_source=$(echo "$found_vm_info" | cut -d':' -f1)
  datastore_name=$(echo "$found_vm_info" | cut -d':' -f2)
  datastore_path=$(echo "$found_vm_info" | cut -d':' -f3)
  local vm_dir="$datastore_path/$VMNAME" # Define vm_dir here

  # If it's a vm-bhyve VM, we don't modify its config directly
  if [ "$vm_source" == "vm-bhyve" ]; then
    display_and_log "ERROR" "VM '$VMNAME' is a vm-bhyve VM. Autostart cannot be managed by bhyve-cli for vm-bhyve VMs."
    exit 1
  fi

  # Load VM config using the found datastore_path. This sets the global VMNAME, VM_DIR, CONF_FILE etc.
  # We need to load the config to ensure CONF_FILE is set for sed operations.
  load_vm_config "$VMNAME" "$vm_dir"

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
