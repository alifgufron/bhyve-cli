#!/usr/local/bin/bash

# === Subcommand: delete ===
cmd_delete() {
  local VMNAME=""
  local EXPLICIT_DATASTORE_PROVIDED="false"
  local DATASTORE_NAME="" # Will be set if --datastore is used

  # Parse named arguments
  while (( "$#" )); do
    case "$1" in
      --datastore)
        shift
        DATASTORE_NAME="$1"
        EXPLICIT_DATASTORE_PROVIDED="true"
        ;;
      *)
        if [[ -z "$VMNAME" ]]; then
          VMNAME="$1"
        else
          log_error "Unknown argument: $1"
          cmd_delete_usage
          return 1
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$VMNAME" ]]; then
    log_error "VM name not specified."
    cmd_delete_usage
    return 1
  fi

  # Source the VM's configuration
  if ! source_vm_config "$VMNAME" "$DATASTORE_NAME"; then
    log_error "Failed to load configuration for VM '$VMNAME'."
    return 1
  fi

  # Confirm deletion
  read -p "Are you sure you want to delete VM '$VMNAME' and all its associated files? (y/N): " -n 1 -r
  echo
  if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    log_info "VM deletion cancelled."
    return 0
  fi

  # Stop the VM if it's running
  if is_vm_running "$VMNAME"; then
    log_info "VM '$VMNAME' is running. Attempting to stop it..."
    if ! cmd_stop "$VMNAME" --silent; then
      log_error "Failed to stop VM '$VMNAME'. Cannot delete a running VM."
      return 1
    fi
  fi

  # Delete VM files
  log_info "Deleting VM files for '$VMNAME'..."
  if [[ -d "$VM_DIR" ]]; then
    if rm -rf "$VM_DIR"; then
      log_success "Successfully deleted VM directory: $VM_DIR"
    else
      log_error "Failed to delete VM directory: $VM_DIR"
      return 1
    fi
  else
    log_warn "VM directory '$VM_DIR' not found. Skipping."
  fi

  # Delete vm.pid file if it exists (should be handled by cmd_stop, but as a fallback)
  delete_vm_pid "$VMNAME"

  # Clean up network interfaces (if any were associated and not cleaned by stop)
  cleanup_vm_network_interfaces "$VMNAME"

  log_success "VM '$VMNAME' and all its associated files have been deleted."
  update_changelog "Deleted VM '$VMNAME'."
}

# === Usage: delete ===
cmd_delete_usage() {
  echo "Usage: bhyve-cli vm delete <vm_name> [--datastore <datastore_name>]"
  echo ""
  echo "Delete a virtual machine and all its associated files."
  echo ""
  echo "Arguments:"
  echo "  <vm_name>           The name of the virtual machine to delete."
  echo ""
  echo "Options:"
  echo "  --datastore <name>  Specify the datastore where the VM is located."
  echo "                      If not specified, the default datastore will be used."
}