#!/usr/local/bin/bash

# === Subcommand: iso download ===
cmd_iso_download() {
  if [ "$1" = "--help" ] || [ -z "$1" ]; then
    cmd_iso_usage
    exit 1
  fi
  local ISO_URL="$1"
  local ISO_FILE="$(basename "$ISO_URL")"
  local ISO_PATH="$ISO_DIR/$ISO_FILE"

  mkdir -p "$ISO_DIR" || { display_and_log "ERROR" "Failed to create ISO directory '$ISO_DIR'."; exit 1; }

  log "Downloading ISO from $ISO_URL to $ISO_PATH..."
  log "Downloading $ISO_FILE... This may take a while."
  fetch "$ISO_URL" -o "$ISO_PATH" || {
    display_and_log "ERROR" "Failed to download ISO from $ISO_URL."
    exit 1
  }
  display_and_log "INFO" "ISO downloaded successfully to $ISO_PATH."
}
