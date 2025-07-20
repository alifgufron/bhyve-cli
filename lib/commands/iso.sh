#!/usr/local/bin/bash

# === Subcommand: iso ===
cmd_iso() {
  if [ -z "$1" ]; then
    cmd_iso_usage
    exit 1
  fi

  local SUBCOMMAND="$1"
  shift

  case "$SUBCOMMAND" in
    list)
      log "Listing ISO files in $ISO_DIR..."
      if [ ! -d "$ISO_DIR" ]; then
        display_and_log "INFO" "ISO directory '$ISO_DIR' not found. Creating it."
        mkdir -p "$ISO_DIR"
      fi
      mapfile -t ISO_LIST < <(find "$ISO_DIR" -type f -name "*.iso" 2>/dev/null)
      if [ ${#ISO_LIST[@]} -eq 0 ]; then
        display_and_log "INFO" "No ISO files found in $ISO_DIR."
      else
        echo_message "\nAvailable ISOs in $ISO_DIR:"
        local count=1
        for iso in "${ISO_LIST[@]}"; do
          local iso_filename=$(basename "$iso")
          local iso_size_bytes=$(stat -f %z "$iso")
          local iso_size_gb=$(echo "scale=2; $iso_size_bytes / (1024 * 1024 * 1024)" | bc)
          echo_message "$((count++)). $iso_filename (${iso_size_gb}GB)"
        done
      fi
      ;;
    http://*|https://*)
      local ISO_URL="$SUBCOMMAND"
      local ISO_FILE="$(basename "$ISO_URL")"
      local ISO_PATH="$ISO_DIR/$ISO_FILE"

      mkdir -p "$ISO_DIR" || { display_and_log "ERROR" "Failed to create ISO directory '$ISO_DIR'."; exit 1; }

      log "Downloading ISO from $ISO_URL to $ISO_PATH..."
      display_and_log "INFO" "Downloading $ISO_FILE... This may take a while."
      fetch "$ISO_URL" -o "$ISO_PATH" || {
        display_and_log "ERROR" "Failed to download ISO from $ISO_URL."
        exit 1
      }
      display_and_log "INFO" "ISO downloaded successfully to $ISO_PATH."
      ;;
    *)
      display_and_log "ERROR" "Invalid subcommand or URL for 'iso': $SUBCOMMAND"
      cmd_iso_usage
      exit 1
      ;;
  esac
}
