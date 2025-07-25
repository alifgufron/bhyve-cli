#!/usr/local/bin/bash

# === Subcommand: verify ===
cmd_verify() {
  
  display_and_log "INFO" "Starting VM configuration verification..."

  local VERIFY_STATUS="SUCCESS"
  local VM_COUNT=0
  local ERROR_COUNT=0

  if [ ! -d "$VM_CONFIG_BASE_DIR" ] || [ -z "$(ls -A "$VM_CONFIG_BASE_DIR")" ]; then
    display_and_log "INFO" "No virtual machines configured to verify."
    exit 0
  fi

  for VM_DIR_PATH in "$VM_CONFIG_BASE_DIR"/*/; do
    if [ -d "$VM_DIR_PATH" ]; then
      VM_COUNT=$((VM_COUNT + 1))
      local VMNAME=$(basename "$VM_DIR_PATH")
      local CONF_FILE="$VM_DIR_PATH/vm.conf"
      
      echo_message "\nVerifying VM: $VMNAME"
      echo_message "---------------------------------"

      if [ ! -f "$CONF_FILE" ]; then
        display_and_log "ERROR" "  Configuration file '$CONF_FILE' not found."
        VERIFY_STATUS="FAILED"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        continue
      fi

      # Check for syntax errors by sourcing in a subshell
      if ! (source "$CONF_FILE") > /dev/null 2>&1; then
        display_and_log "ERROR" "  Syntax error in '$CONF_FILE'."
        VERIFY_STATUS="FAILED"
        ERROR_COUNT=$((ERROR_COUNT + 1))
      else
        display_and_log "INFO" "  Configuration file syntax: OK"
      fi

      # Load VM config to check disk paths
      # Temporarily set VM_DIR for this check
      local ORIGINAL_VM_DIR="$VM_DIR"
      VM_DIR="$VM_DIR_PATH"
      
      # Source again to get variables for disk checks
      source "$CONF_FILE"

      local DISK_IDX=0
      while true; do
        local CURRENT_DISK_VAR="DISK"
        if [ "$DISK_IDX" -gt 0 ]; then
          CURRENT_DISK_VAR="DISK_${DISK_IDX}"
        fi
        local CURRENT_DISK_FILENAME="${!CURRENT_DISK_VAR}"

        if [ -z "$CURRENT_DISK_FILENAME" ]; then
          break # No more disks configured
        fi

        local CURRENT_DISK_PATH="$VM_DIR/$CURRENT_DISK_FILENAME"
        if [ ! -f "$CURRENT_DISK_PATH" ]; then
          display_and_log "ERROR" "  Disk image '$CURRENT_DISK_PATH' not found."
          VERIFY_STATUS="FAILED"
          ERROR_COUNT=$((ERROR_COUNT + 1))
        else
          display_and_log "INFO" "  Disk image '$CURRENT_DISK_FILENAME': OK"
        fi
        DISK_IDX=$((DISK_IDX + 1))
      done
      
      # Restore original VM_DIR
      VM_DIR="$ORIGINAL_VM_DIR"
      echo_message "---------------------------------"
    fi
  done

  echo_message "\nVerification Summary:"
  echo_message "---------------------------------"
  echo_message "Total VMs checked: $VM_COUNT"
  echo_message "Errors found: $ERROR_COUNT"
  if [ "$ERROR_COUNT" -eq 0 ]; then
    display_and_log "INFO" "All VM configurations verified successfully."
  else
    display_and_log "ERROR" "Verification completed with errors. Please review the logs above."
  fi
  echo_message "---------------------------------"
  
}