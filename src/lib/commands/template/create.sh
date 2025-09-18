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

  # Check for zstd availability
  if ! command -v zstd >/dev/null 2>&1; then
    display_and_log "ERROR" "zstd command not found. Please install zstd to enable template compression."
    exit 1
  fi

  display_and_log "INFO" "Creating template '$TEMPLATE_NAME' from VM '$SOURCE_VMNAME'..."
  start_spinner "Copying VM files to template..."

  # Copy vm.conf and all disk images
  cp "$SOURCE_VM_DIR/vm.conf" "$NEW_TEMPLATE_DIR/vm.conf" || {
    stop_spinner
    display_and_log "ERROR" "Failed to copy vm.conf to template."
    rm -rf "$NEW_TEMPLATE_DIR"
    exit 1
  }

  # Find and copy all disk images (disk.img, disk1.img, etc.)
  for disk_file in "$SOURCE_VM_DIR"/disk*.img; do
    if [ -f "$disk_file" ]; then
      cp "$disk_file" "$NEW_TEMPLATE_DIR/" || {
        stop_spinner
        display_and_log "ERROR" "Failed to copy disk image '$disk_file' to template."
        rm -rf "$NEW_TEMPLATE_DIR"
        exit 1
      }
      log "Copied disk image: $(basename "$disk_file") to $NEW_TEMPLATE_DIR/"

      # Compress the copied disk image
      local TEMPLATE_DISK_PATH="$NEW_TEMPLATE_DIR/$(basename "$disk_file")"
      log "Compressing '$TEMPLATE_DISK_PATH' with zstd..."
      if ! zstd -q "$TEMPLATE_DISK_PATH" -o "${TEMPLATE_DISK_PATH}.zst"; then
        stop_spinner
        display_and_log "ERROR" "Failed to compress disk image '$(basename "$disk_file")' with zstd. Aborting."
        rm -rf "$NEW_TEMPLATE_DIR"
        exit 1
      fi
      rm "$TEMPLATE_DISK_PATH" # Remove uncompressed copy
      log "Compressed '${TEMPLATE_DISK_PATH}.zst'. Original removed."

      # Update vm.conf in template to point to the .zst file
      sed -i '' "s|$(basename "$disk_file")|$(basename "$disk_file").zst|" "$NEW_TEMPLATE_DIR/vm.conf"
      log "Updated vm.conf in template to reference .zst file."
    fi # <-- ADDED THIS
  done # <-- ADDED THIS
  stop_spinner # <-- MOVED THIS HERE

  # Clean up VM-specific settings in the template's vm.conf
  sed -i '' "/^VMNAME=/d" "$NEW_TEMPLATE_DIR/vm.conf"
  sed -i '' "/^UUID=/d" "$NEW_TEMPLATE_DIR/vm.conf"
  sed -i '' "/^CONSOLE=/d" "$NEW_TEMPLATE_DIR/vm.conf"
  sed -i '' "/^LOG=/d" "$NEW_TEMPLATE_DIR/vm.conf"
  sed -i '' "/^VNC_PORT=/d" "$NEW_TEMPLATE_DIR/vm.conf"
  sed -i '' "/^VNC_WAIT=/d" "$NEW_TEMPLATE_DIR/vm.conf"
  sed -i '' "/^BOOTLOADER_TYPE=/d" "$NEW_TEMPLATE_DIR/vm.conf" # New: remove bootloader type
  sed -i '' "/^AUTOSTART=/d" "$NEW_TEMPLATE_DIR/vm.conf" # New: remove autostart

  display_and_log "INFO" "Template '$TEMPLATE_NAME' created successfully."
  display_and_log "INFO" "You can now create new VMs from this template using: bhyve-cli vm create --name <new_vm> --from-template $TEMPLATE_NAME --switch <bridge>"
}
