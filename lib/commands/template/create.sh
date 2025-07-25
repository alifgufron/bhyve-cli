#!/usr/local/bin/bash

# === Subcommand: template create ===
cmd_template_create() {
  if [ -z "$2" ]; then
    cmd_template_usage
    exit 1
  fi

  local SOURCE_VMNAME="$1"
  local TEMPLATE_NAME="$2"

  local SOURCE_VM_DIR="$VM_CONFIG_BASE_DIR/$SOURCE_VMNAME"
  local TEMPLATE_BASE_DIR="$VM_CONFIG_BASE_DIR/templates"
  local NEW_TEMPLATE_DIR="$TEMPLATE_BASE_DIR/$TEMPLATE_NAME"

  if [ ! -d "$SOURCE_VM_DIR" ]; then
    display_and_log "ERROR" "Source VM '$SOURCE_VMNAME' not found."
    exit 1
  fi

  if [ -d "$NEW_TEMPLATE_DIR" ]; then
    display_and_log "ERROR" "Template '$TEMPLATE_NAME' already exists."
    exit 1
  fi

  mkdir -p "$NEW_TEMPLATE_DIR" || { display_and_log "ERROR" "Failed to create template directory '$NEW_TEMPLATE_DIR'."; exit 1; }

  display_and_log "INFO" "Creating template '$TEMPLATE_NAME' from VM '$SOURCE_VMNAME'..."
  start_spinner "Copying VM files to template..."

  # Copy vm.conf and disk image
  cp "$SOURCE_VM_DIR/vm.conf" "$NEW_TEMPLATE_DIR/vm.conf" || {
    stop_spinner
    display_and_log "ERROR" "Failed to copy vm.conf to template."
    rm -rf "$NEW_TEMPLATE_DIR"
    exit 1
  }
  cp "$SOURCE_VM_DIR/disk.img" "$NEW_TEMPLATE_DIR/disk.img" || {
    stop_spinner
    display_and_log "ERROR" "Failed to copy disk image to template."
    rm -rf "$NEW_TEMPLATE_DIR"
    exit 1
  }
  stop_spinner

  # Clean up VM-specific settings in the template's vm.conf
  sed -i '' "/^VMNAME=/d" "$NEW_TEMPLATE_DIR/vm.conf"
  sed -i '' "/^UUID=/d" "$NEW_TEMPLATE_DIR/vm.conf"
  sed -i '' "/^TAP_[0-9]=/d" "$NEW_TEMPLATE_DIR/vm.conf"
  sed -i '' "/^MAC_[0-9]=/d" "$NEW_TEMPLATE_DIR/vm.conf"
  sed -i '' "/^BRIDGE_[0-9]=/d" "$NEW_TEMPLATE_DIR/vm.conf"
  sed -i '' "/^CONSOLE=/d" "$NEW_TEMPLATE_DIR/vm.conf"
  sed -i '' "/^LOG=/d" "$NEW_TEMPLATE_DIR/vm.conf"
  sed -i '' "/^VNC_PORT=/d" "$NEW_TEMPLATE_DIR/vm.conf"
  sed -i '' "/^VNC_WAIT=/d" "$NEW_TEMPLATE_DIR/vm.conf"

  display_and_log "INFO" "Template '$TEMPLATE_NAME' created successfully."
  display_and_log "INFO" "You can now create new VMs from this template using: $0 create --name <new_vm> --from-template $TEMPLATE_NAME --switch <bridge>"
}
