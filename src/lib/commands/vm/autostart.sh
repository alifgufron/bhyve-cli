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
  local found_bhyve_cli_vm
  found_bhyve_cli_vm=$(find_vm_in_datastores "$VMNAME")

  if [ -n "$found_bhyve_cli_vm" ]; then
    local datastore_name=$(echo "$found_bhyve_cli_vm" | head -n 1 | cut -d':' -f1)
    local vm_dir=$(echo "$found_bhyve_cli_vm" | head -n 1 | cut -d':' -f2)/"$VMNAME"
    CONF_FILE="$vm_dir/vm.conf"
  else
    # If not found in bhyve-cli datastores, check vm-bhyve directories
    local vm_bhyve_dirs
    vm_bhyve_dirs=$(get_vm_bhyve_dir) # Returns "name:path" pairs

    local vm_found_in_vm_bhyve=false
    if [ -n "$vm_bhyve_dirs" ]; then
      for datastore_pair in $vm_bhyve_dirs; do
        local current_ds_name=$(echo "$datastore_pair" | cut -d':' -f1)
        local current_ds_path=$(echo "$datastore_pair" | cut -d':' -f2)
        
        if [ -d "$current_ds_path/$VMNAME" ]; then
          # For vm-bhyve VMs, we don't modify their config directly,
          # but we need to acknowledge their existence.
          display_and_log "ERROR" "VM '$VMNAME' is a vm-bhyve VM. Autostart cannot be managed by bhyve-cli for vm-bhyve VMs."
          exit 1
        fi
      done
    fi

    display_and_log "ERROR" "VM '$VMNAME' not found in any bhyve-cli datastores."
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
