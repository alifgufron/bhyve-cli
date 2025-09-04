#!/usr/local/bin/bash

# === Subcommand: modify ===
cmd_modify() {
  if [ -z "$1" ]; then
    cmd_modify_usage
    exit 1
  fi

  VMNAME="$1"
  shift
  load_vm_config "$VMNAME"

  local VM_MODIFIED=false
  local PENDING_DISK_TYPE="" # To store type for --add-disk or --add-disk-path
  local PENDING_NIC_TYPE=""  # To store type for --add-nic

  while (( "$#" )); do
    case "$1" in
      --cpu)
        shift
        local NEW_CPUS="$1"
        log "Modifying CPU for VM '$VMNAME' to $NEW_CPUS..."
        sed -i '' "s/^CPUS=.*/CPUS=${NEW_CPUS}/" "$CONF_FILE"
        display_and_log "INFO" "CPUs set to $NEW_CPUS."
        VM_MODIFIED=true
        ;;
      --ram)
        shift
        local NEW_RAM="$1"
        log "Modifying RAM for VM '$VMNAME' to $NEW_RAM..."
        sed -i '' "s/^MEMORY=.*/MEMORY=${NEW_RAM}/" "$CONF_FILE"
        display_and_log "INFO" "RAM set to $NEW_RAM."
        VM_MODIFIED=true
        ;;
      --nic)
        shift
        local NIC_INDEX="$1"
        shift
        case "$1" in
          --tap)
            shift
            local NEW_TAP="$1"
            log "Modifying TAP for NIC $NIC_INDEX to $NEW_TAP..."
            sed -i '' "s/^TAP_${NIC_INDEX}=.*/TAP_${NIC_INDEX}=${NEW_TAP}/" "$CONF_FILE"
            display_and_log "INFO" "NIC $NIC_INDEX TAP set to $NEW_TAP."
            VM_MODIFIED=true
            ;;
          --mac)
            shift
            local NEW_MAC="$1"
            log "Modifying MAC for NIC $NIC_INDEX to $NEW_MAC..."
            sed -i '' "s/^MAC_${NIC_INDEX}=.*/MAC_${NIC_INDEX}=${NEW_MAC}/" "$CONF_FILE"
            display_and_log "INFO" "NIC $NIC_INDEX MAC set to $NEW_MAC."
            VM_MODIFIED=true
            ;;
          --bridge)
            shift
            local NEW_BRIDGE="$1"
            log "Modifying Bridge for NIC $NIC_INDEX to $NEW_BRIDGE..."
            sed -i '' "s/^BRIDGE_${NIC_INDEX}=.*/BRIDGE_${NIC_INDEX}=${NEW_BRIDGE}/" "$CONF_FILE"
            display_and_log "INFO" "NIC $NIC_INDEX Bridge set to $NEW_BRIDGE."
            VM_MODIFIED=true
            ;;
          *)
            display_and_log "ERROR" "Invalid option for --nic: $1"
            cmd_modify_usage
            exit 1
            ;;
        esac
        ;;
      --add-nic)
        shift
        local NEW_NIC_BRIDGE="$1"
        local NEXT_NIC_INDEX=0
        while grep -q "^TAP_${NEXT_NIC_INDEX}=" "$CONF_FILE"; do
          NEXT_NIC_INDEX=$((NEXT_NIC_INDEX + 1))
        done
        local NEW_TAP_NAME="tap$(get_next_available_tap_num)"
        local NEW_MAC_ADDRESS="58:9c:fc$(jot -r -w ":%02x" -s "" 3 0 255)"
        
        log "Adding new NIC (index $NEXT_NIC_INDEX) to VM '$VMNAME'..."
        echo "TAP_${NEXT_NIC_INDEX}=${NEW_TAP_NAME}" >> "$CONF_FILE"
        echo "MAC_${NEXT_NIC_INDEX}=${NEW_MAC_ADDRESS}" >> "$CONF_FILE"
        echo "BRIDGE_${NEXT_NIC_INDEX}=${NEW_NIC_BRIDGE}" >> "$CONF_FILE"
        if [ -n "$PENDING_NIC_TYPE" ]; then
          echo "NIC_${NEXT_NIC_INDEX}_TYPE=${PENDING_NIC_TYPE}" >> "$CONF_FILE"
          display_and_log "INFO" "New NIC added: TAP=${NEW_TAP_NAME}, MAC=${NEW_MAC_ADDRESS}, Bridge=${NEW_NIC_BRIDGE}, Type=${PENDING_NIC_TYPE}."
          PENDING_NIC_TYPE="" # Reset for next operation
        else
          display_and_log "INFO" "New NIC added: TAP=${NEW_TAP_NAME}, MAC=${NEW_MAC_ADDRESS}, Bridge=${NEW_NIC_BRIDGE}."
        fi
        VM_MODIFIED=true
        ;;
      --remove-nic)
        shift
        local REMOVE_NIC_INDEX="$1"
        log "Removing NIC (index $REMOVE_NIC_INDEX) from VM '$VMNAME'..."
        sed -i '' "/^TAP_${REMOVE_NIC_INDEX}=/d" "$CONF_FILE"
        sed -i '' "/^MAC_${REMOVE_NIC_INDEX}=/d" "$CONF_FILE"
        sed -i '' "/^BRIDGE_${REMOVE_NIC_INDEX}=/d" "$CONF_FILE"
        sed -i '' "/^NIC_${REMOVE_NIC_INDEX}_TYPE=/d" "$CONF_FILE" # Also remove type
        display_and_log "INFO" "NIC $REMOVE_NIC_INDEX removed."
        VM_MODIFIED=true
        ;;
      --add-disk)
        shift
        local NEW_DISK_SIZE_GB="$1"
        local NEXT_DISK_INDEX=1 # Start from DISK_1, DISK is 0
        while grep -q "^DISK_${NEXT_DISK_INDEX}=" "$CONF_FILE"; do
          NEXT_DISK_INDEX=$((NEXT_DISK_INDEX + 1))
        done
        local NEW_DISK_FILENAME="disk${NEXT_DISK_INDEX}.img"
        local NEW_DISK_PATH="$VM_DIR/$NEW_DISK_FILENAME"

        log "Adding new disk (index $NEXT_DISK_INDEX) to VM '$VMNAME'..."
        truncate -s "${NEW_DISK_SIZE_GB}G" "$NEW_DISK_PATH" || {
          display_and_log "ERROR" "Failed to create new disk image at '$NEW_DISK_PATH'."
          exit 1
        }
        echo "DISK_${NEXT_DISK_INDEX}=${NEW_DISK_FILENAME}" >> "$CONF_FILE"
        if [ -n "$PENDING_DISK_TYPE" ]; then
          echo "DISK_${NEXT_DISK_INDEX}_TYPE=${PENDING_DISK_TYPE}" >> "$CONF_FILE"
          display_and_log "INFO" "New disk added: ${NEW_DISK_FILENAME} (${NEW_DISK_SIZE_GB}GB) with type ${PENDING_DISK_TYPE}."
          PENDING_DISK_TYPE="" # Reset for next operation
        else
          display_and_log "INFO" "New disk added: ${NEW_DISK_FILENAME} (${NEW_DISK_SIZE_GB}GB)."
        fi
        VM_MODIFIED=true
        ;;
      --add-disk-path)
        shift
        local EXISTING_DISK_PATH="$1"
        # Resolve the absolute path of the existing disk file
        EXISTING_DISK_PATH=$(readlink -f "$EXISTING_DISK_PATH")
        if [ ! -f "$EXISTING_DISK_PATH" ]; then
          display_and_log "ERROR" "Existing disk path '$EXISTING_DISK_PATH' not found or is not a regular file."
          exit 1
        fi

        local NEXT_DISK_INDEX=1 # Start from DISK_1, DISK is 0
        while grep -q "^DISK_${NEXT_DISK_INDEX}=" "$CONF_FILE"; do
          NEXT_DISK_INDEX=$((NEXT_DISK_INDEX + 1))
        done
        
        log "Attaching existing disk (index $NEXT_DISK_INDEX) to VM '$VMNAME' from '$EXISTING_DISK_PATH'..."
        echo "DISK_${NEXT_DISK_INDEX}=${EXISTING_DISK_PATH}" >> "$CONF_FILE"
        if [ -n "$PENDING_DISK_TYPE" ]; then
          echo "DISK_${NEXT_DISK_INDEX}_TYPE=${PENDING_DISK_TYPE}" >> "$CONF_FILE"
          display_and_log "INFO" "Existing disk attached: ${EXISTING_DISK_PATH} with type ${PENDING_DISK_TYPE}."
          PENDING_DISK_TYPE="" # Reset for next operation
        else
          display_and_log "INFO" "Existing disk attached: ${EXISTING_DISK_PATH}."
        fi
        VM_MODIFIED=true
        ;;
      --add-disk-type)
        shift
        PENDING_DISK_TYPE="$1"
        log "Pending disk type set to: $PENDING_DISK_TYPE"
        ;;
      --remove-disk)
        shift
        local REMOVE_DISK_INDEX="$1"
        local DISK_VAR_TO_REMOVE="DISK"
        if [ "$REMOVE_DISK_INDEX" -gt 0 ]; then
          DISK_VAR_TO_REMOVE="DISK_${REMOVE_DISK_INDEX}"
        fi
        local DISK_FILENAME_FROM_CONF=$(grep "^${DISK_VAR_TO_REMOVE}=" "$CONF_FILE" | cut -d'=' -f2)
        
        local ACTUAL_DISK_PATH=""
        local IS_EXTERNAL_DISK=false

        # Determine if it's an internal or external disk
        if [[ "$DISK_FILENAME_FROM_CONF" =~ ^/ ]]; then
          # It's an absolute path, so it's an external disk
          ACTUAL_DISK_PATH="$DISK_FILENAME_FROM_CONF"
          IS_EXTERNAL_DISK=true
        else
          # It's a relative path, so it's an internal disk within VM_DIR
          ACTUAL_DISK_PATH="$VM_DIR/$DISK_FILENAME_FROM_CONF"
        fi

        log "Removing disk (index $REMOVE_DISK_INDEX) from VM '$VMNAME'..."
        
        # Always remove config entries first
        sed -i '' "/^${DISK_VAR_TO_REMOVE}=/d" "$CONF_FILE"
        sed -i '' "/^${DISK_VAR_TO_REMOVE}_TYPE=/d" "$CONF_FILE" # Also remove type

        if [ -f "$ACTUAL_DISK_PATH" ]; then
          if [ "$IS_EXTERNAL_DISK" = true ]; then
            read -rp "This is an external disk file: '$ACTUAL_DISK_PATH'. Do you want to delete the file as well? (y/N) " CONFIRM_DELETE_FILE
            if [[ "$CONFIRM_DELETE_FILE" =~ ^[Yy]$ ]]; then
              rm "$ACTUAL_DISK_PATH"
              display_and_log "INFO" "External disk file '$ACTUAL_DISK_PATH' removed."
            else
              display_and_log "INFO" "External disk file '$ACTUAL_DISK_PATH' kept."
            fi
          else
            # It's an internal disk created by bhyve-cli, delete automatically
            rm "$ACTUAL_DISK_PATH"
            display_and_log "INFO" "Internal disk file '$ACTUAL_DISK_PATH' removed."
          fi
        else
          display_and_log "INFO" "Disk file '$ACTUAL_DISK_PATH' not found on filesystem. Only configuration removed."
        fi
        display_and_log "INFO" "Disk $REMOVE_DISK_INDEX removed from configuration."
        VM_MODIFIED=true
        ;;
      --nic-type)
        shift
        PENDING_NIC_TYPE="$1"
        log "Pending NIC type set to: $PENDING_NIC_TYPE"
        ;;
      --vnc-port)
        shift
        local NEW_VNC_PORT="$1"
        log "Modifying VNC port for VM '$VMNAME' to $NEW_VNC_PORT..."
        sed -i '' "s/^VNC_PORT=.*/VNC_PORT=${NEW_VNC_PORT}/" "$CONF_FILE"
        display_and_log "INFO" "VNC port set to $NEW_VNC_PORT."
        VM_MODIFIED=true
        ;;
      --vnc-wait)
        log "Enabling VNC wait for VM '$VMNAME'..."
        sed -i '' "s/^VNC_WAIT=.*/VNC_WAIT=yes/" "$CONF_FILE"
        if ! grep -q "^VNC_WAIT=" "$CONF_FILE"; then
          echo "VNC_WAIT=yes" >> "$CONF_FILE"
        fi
        display_and_log "INFO" "VNC wait enabled."
        VM_MODIFIED=true
        ;;
      --no-vnc-wait)
        log "Disabling VNC wait for VM '$VMNAME'..."
        sed -i '' "/^VNC_WAIT=/d" "$CONF_FILE"
        display_and_log "INFO" "VNC wait disabled."
        VM_MODIFIED=true
        ;;
      *)
        display_and_log "ERROR" "Invalid option: $1"
        cmd_modify_usage
        exit 1
        ;;
    esac
    shift
  done

  if [ "$VM_MODIFIED" = true ]; then
    display_and_log "INFO" "VM '$VMNAME' modified successfully."
  else
    display_and_log "INFO" "No modifications specified for VM '$VMNAME'."
  fi
}
