#!/usr/local/bin/bash

# This script is intended to be run during bhyve-cli uninstallation
# to clean up all network interfaces (bridges and TAPs) created by bhyve-cli.

# Source core functions for logging and configuration paths
# Assuming this script will be run from the project root or sourced appropriately
# For direct execution during uninstall, we need to define these paths directly.

# Define paths (should match Makefile and main script definitions)
PREFIX="/usr/local"
ETC_DIR="${PREFIX}/etc"
APP_NAME="bhyve-cli"
ETC_APP_DIR="${ETC_DIR}/${APP_NAME}"
SWITCH_CONFIG_FILE="${ETC_APP_DIR}/switch.conf"
VMNET_CONFIG_FILE="${ETC_APP_DIR}/vmnet.conf"

log_info() {
  echo "[INFO] $1"
}

log_warn() {
  echo "[WARNING] $1"
}

log_error() {
  echo "[ERROR] $1"
}

echo "Starting comprehensive network cleanup for bhyve-cli..."

# --- Cleanup Bridges ---
echo "Cleaning up bhyve-cli created bridges..."

# Bridges from switch.conf
if [ -f "$SWITCH_CONFIG_FILE" ]; then
  while IFS= read -r line; do
    BRIDGE_NAME=$(echo "$line" | awk '{print $1}')
    if [ -n "$BRIDGE_NAME" ]; then
      echo "Attempting to destroy bridge: $BRIDGE_NAME (from switch.conf)"
      if ifconfig "$BRIDGE_NAME" > /dev/null 2>&1; then
        if ! ifconfig "$BRIDGE_NAME" destroy; then
          echo "WARNING: Failed to destroy bridge '$BRIDGE_NAME'. It might be in use."
        else
          echo "Bridge '$BRIDGE_NAME' destroyed."
        fi
      else
        echo "Bridge '$BRIDGE_NAME' not found, skipping."
      fi
    fi
  done < "$SWITCH_CONFIG_FILE"
  rm -f "$SWITCH_CONFIG_FILE"
  echo "Removed $SWITCH_CONFIG_FILE."
else
  echo "No switch.conf found, skipping bridge cleanup from switch config."
fi

# Bridges from vmnet.conf
if [ -f "$VMNET_CONFIG_FILE" ]; then
  while IFS= read -r line; do
    BRIDGE_NAME=$(echo "$line" | awk '{print $1}')
    if [ -n "$BRIDGE_NAME" ]; then
      echo "Attempting to destroy vmnet bridge: $BRIDGE_NAME (from vmnet.conf)"
      if ifconfig "$BRIDGE_NAME" > /dev/null 2>&1; then
        if ! ifconfig "$BRIDGE_NAME" destroy; then
          echo "WARNING: Failed to destroy vmnet bridge '$BRIDGE_NAME'. It might be in use."
        else
          echo "Vmnet bridge '$BRIDGE_NAME' destroyed."
        fi
      else
        echo "Vmnet bridge '$BRIDGE_NAME' not found, skipping."
      fi
    fi
  done < "$VMNET_CONFIG_FILE"
  rm -f "$VMNET_CONFIG_FILE"
  echo "Removed $VMNET_CONFIG_FILE."
else
  echo "No vmnet.conf found, skipping bridge cleanup from vmnet config."
fi

# --- Cleanup TAP interfaces ---
echo "Cleaning up bhyve-cli created TAP interfaces..."

ALL_TAPS=$(ifconfig -l | tr ' ' '\n' | grep '^tap')
if [ -z "$ALL_TAPS" ]; then
  echo "No TAP interfaces found on the system."
else
  for tap_if in $ALL_TAPS; do
    TAP_DESC=$(ifconfig "$tap_if" | grep 'description:' | sed 's/^[[:space:]]*description: //')
    # Check if the description indicates it was created by bhyve-cli
    # The pattern vmnet/<VMNAME>/<NIC_IDX>/<BRIDGE_NAME> is used by bhyve-cli
    if [[ "$TAP_DESC" == "vmnet/"* ]]; then
      echo "Found bhyve-cli related TAP interface: $tap_if with description '$TAP_DESC'"
      # Remove from any bridge it might be a member of
      bridge_if=$(ifconfig -a | grep -B 5 "member: ${tap_if}" | grep '^bridge' | cut -d':' -f1)
      if [ -n "$bridge_if" ]; then
        echo "Removing TAP '$tap_if' from bridge '$bridge_if'..."
        if ! ifconfig "$bridge_if" deletem "$tap_if"; then
          echo "WARNING: Failed to remove TAP '$tap_if' from bridge '$bridge_if'."
        fi
      fi
      # Destroy the TAP interface
      echo "Destroying TAP interface: $tap_if"
      if ! ifconfig "$tap_if" destroy; then
        echo "WARNING: Failed to destroy TAP interface '$tap_if'. It might be in use."
      else
        echo "TAP interface '$tap_if' destroyed."
      fi
    fi
  done
fi

echo "Comprehensive network cleanup complete."
