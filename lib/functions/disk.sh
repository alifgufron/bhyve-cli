#!/usr/local/bin/bash

# === Helper function to build disk arguments ===
build_disk_args() {
  local VM_DIR="$1"
  local DISK_ARGS=""
  local DISK_DEV_NUM=3 # Starting device number for virtio-blk

  local CURRENT_DISK_IDX=0
  while true;
    do
    local CURRENT_DISK_VAR="DISK"
    if [ "$CURRENT_DISK_IDX" -gt 0 ]; then
      CURRENT_DISK_VAR="DISK_${CURRENT_DISK_IDX}"
    fi
    local CURRENT_DISK_FILENAME="${!CURRENT_DISK_VAR}"

    if [ -z "$CURRENT_DISK_FILENAME" ]; then
      break # No more disks configured
    fi

    local CURRENT_DISK_PATH="$VM_DIR/$CURRENT_DISK_FILENAME"
    if [ ! -f "$CURRENT_DISK_PATH" ]; then
      display_and_log "ERROR" "Disk image '$CURRENT_DISK_PATH' not found!"
      echo "" # Return empty string for DISK_ARGS
      echo "1" # Indicate error for next_dev_num (arbitrary non-zero to signal error)
      return 1
    fi
    DISK_ARGS+=" -s ${DISK_DEV_NUM}:0,virtio-blk,\"$CURRENT_DISK_PATH\""
    DISK_DEV_NUM=$((DISK_DEV_NUM + 1))
    CURRENT_DISK_IDX=$((CURRENT_DISK_IDX + 1))
  done
  echo "$DISK_ARGS"
  echo "$DISK_DEV_NUM" # Echo the next available device number
  return 0
}

