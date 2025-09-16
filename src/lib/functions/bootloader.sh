#!/usr/local/bin/bash

# === Helper function to get bootloader-specific bhyve arguments ===
get_bootloader_arg() {
  local BOOTLOADER_TYPE="$1"
  local VM_DIR="$2"
  local BHYVE_LOADER_CLI_ARG=""

  case "$BOOTLOADER_TYPE" in
    uefi|bootrom)
      local UEFI_PATH=""
      # Check standard paths for UEFI firmware
      if [ -f "/usr/local/share/uefi-firmware/BHYVE_UEFI.fd" ]; then
        UEFI_PATH="/usr/local/share/uefi-firmware/BHYVE_UEFI.fd"
      elif [ -f "$FIRMWARE_DIR/BHYVE_UEFI.fd" ]; then # Check our own firmware dir
        UEFI_PATH="$FIRMWARE_DIR/BHYVE_UEFI.fd"
      fi

      if [ -n "$UEFI_PATH" ]; then
        BHYVE_LOADER_CLI_ARG="-l bootrom,$UEFI_PATH"
        log "Using UEFI firmware from: $UEFI_PATH"
      else
        display_and_log "ERROR" "UEFI firmware not found. Please install 'edk2-bhyve' or place firmware in '$FIRMWARE_DIR'."
        return 1 # Failure
      fi
      ;;
    grub2-bhyve)
      if [ -f "$VM_DIR/grub.conf" ]; then
        BHYVE_LOADER_CLI_ARG="-l grub,${VM_DIR}/grub.conf"
        log "Using grub2-bhyve with config: ${VM_DIR}/grub.conf"
      else
        display_and_log "ERROR" "grub.conf not found in $VM_DIR for grub2-bhyve boot."
        return 1 # Failure
      fi
      ;;
    bhyveload)
      # bhyveload is handled separately before bhyve is called, so no extra arg needed here.
      BHYVE_LOADER_CLI_ARG=""
      ;;
    *)
      display_and_log "ERROR" "Unsupported bootloader type: $BOOTLOADER_TYPE"
      return 1 # Failure
      ;;
  esac

  echo "$BHYVE_LOADER_CLI_ARG"
  return 0
}
