#!/usr/local/bin/bash

# === Function to load main configuration ===
load_config() {
  if [ -f "$MAIN_CONFIG_FILE" ]; then
      # shellcheck disable=SC1090
    . "$MAIN_CONFIG_FILE"
  fi
  # Set default log file if not set in config
  GLOBAL_LOG_FILE="${GLOBAL_LOG_FILE:-/var/log/bhyve-cli.log}"
  VM_CONFIG_BASE_DIR="${VM_CONFIG_BASE_DIR:-$CONFIG_DIR/vm.d}" # Ensure default if not in config
}

# === Function to check if the script has been initialized ===
check_initialization() {
  if [ "$1" != "init" ] && [ ! -f "$MAIN_CONFIG_FILE" ]; then
    echo_message "
[ERROR] bhyve-cli has not been initialized."
    echo_message "Please run the command '$(basename "$0") init' to generate the required configuration files."
    exit 1
  fi
}


# === Function to load VM configuration ===
# Arg1: VMNAME
# Arg2: Optional: custom_datastore_path
load_vm_config() {
  VMNAME="$1"
  local custom_datastore_path="$2"

  if [ -n "$custom_datastore_path" ]; then
    VM_DIR="$custom_datastore_path/$VMNAME" # Construct VM_DIR from datastore path and VMNAME
  else
    VM_DIR="$VM_CONFIG_BASE_DIR/$VMNAME"
  fi
  CONF_FILE="$VM_DIR/vm.conf"

  if [ ! -f "$CONF_FILE" ]; then
    display_and_log "ERROR" "VM configuration '$VMNAME' not found: $CONF_FILE"
    exit 1
  fi
    # shellcheck disable=SC1090
  . "$CONF_FILE"
  LOG_FILE="$VM_DIR/vm.log" # Set LOG_FILE after loading config
  BOOTLOADER_TYPE="${BOOTLOADER_TYPE:-bhyveload}" # Default to bhyveload if not set
}

# Tries to detect the vm-bhyve primary datastore from /etc/rc.conf,
# then reads its system.conf to find any additional datastores.
#
# Returns:
#   A space-separated list of "name:path" pairs for each found datastore.
#   e.g., "default:/opt/bhvye datastore2:/home/bhyve"
get_vm_bhyve_dir() {
    local primary_path_line
    local primary_path
    local system_conf
    local all_datastores=""

    # 1. Find primary path from /etc/rc.conf
    primary_path_line=$(grep '^vm_dir=' /etc/rc.conf 2>/dev/null)
    if [ -z "$primary_path_line" ]; then
        echo ""
        return 1
    fi
    primary_path=$(echo "$primary_path_line" | cut -d'=' -f2 | tr -d '"' | sed 's#/\.*$##')

    # Validate primary path
    if [ ! -d "$primary_path" ]; then
        echo ""
        return 1
    fi

    # Add primary datastore (named as "default") to our list
    local primary_name="default"
    all_datastores="$primary_name:$primary_path "

    # 2. Look for additional datastores in the primary datastore's system.conf
    system_conf="$primary_path/.config/system.conf"
    if [ -f "$system_conf" ]; then
        # 3. Get the list of additional datastore names
        local datastore_list_line
        datastore_list_line=$(grep '^datastore_list=' "$system_conf" 2>/dev/null)
        if [ -n "$datastore_list_line" ]; then
            local datastore_names
            datastore_names=$(echo "$datastore_list_line" | cut -d'=' -f2 | tr -d '"' )

            # 4. For each name, get its path
            for name in $datastore_names; do
                local path_line
                path_line=$(grep "^path_${name}=" "$system_conf" 2>/dev/null)
                if [ -n "$path_line" ]; then
                    local datastore_path
                    datastore_path=$(echo "$path_line" | cut -d'=' -f2 | tr -d '"' | sed 's#/\.*$##')
                    # Validate and add the datastore if its path is a directory
                    if [ -d "$datastore_path" ]; then
                         all_datastores="${all_datastores}${name}:${datastore_path} "
                    fi
                fi
            done
        fi
    fi

    # Print all valid datastores, trimming any trailing space
    echo "$all_datastores" | sed 's/ *$//'
    return 0
}

# Gets the path for a given bhyve-cli datastore name.
# Arg1: datastore_name
# Returns:
#   The absolute path of the datastore, or an empty string if not found.
get_datastore_path() {
  local ds_name="$1"

  if [ "$ds_name" == "default" ]; then
    echo "$VM_CONFIG_BASE_DIR"
    return 0
  fi

  # Grep for the specific datastore variable in the main config file
  local ds_line
  ds_line=$(grep -E "^DATASTORE_${ds_name}=" "$MAIN_CONFIG_FILE" 2>/dev/null)

  if [ -z "$ds_line" ]; then
    echo ""
    return 1
  fi

  # Extract path: everything after the first =
  local ds_path
  ds_path=$(echo "$ds_line" | cut -d'=' -f2- | tr -d '"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  echo "$ds_path"
  return 0
}

# Gets all bhyve-cli datastores (name:path pairs).
# Returns:
#   A space-separated list of "name:path" pairs for each found datastore.
#   e.g., "default:/usr/local/etc/bhyve-cli/vm.d custom_ds:/tmp/custom_vms"
get_all_bhyve_cli_datastores() {
  local all_datastores=""
  local additional_datastores_output=""

  # 1. Add the default datastore
  all_datastores="default:$VM_CONFIG_BASE_DIR "

  # 2. Find and add additional DATASTORE_ variables from the main config file
  additional_datastores_output=$(grep -E '^DATASTORE_[A-Za-z0-9_]+' "$MAIN_CONFIG_FILE" | while IFS= read -r line || [[ -n "$line" ]]; do
    local clean_line
    clean_line=$(echo "$line" | sed 's/#.*//')
    [ -z "$clean_line" ] && continue

    local name
    local path
    name=$(echo "$clean_line" | cut -d'=' -f1 | sed 's/DATASTORE_//')
    path=$(echo "$clean_line" | cut -d'=' -f2- | tr -d '"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Validate path exists before adding
    if [ -d "$path" ]; then
      echo "${name}:${path}" # Echo the name:path pair
    fi
  done)

  all_datastores="${all_datastores}${additional_datastores_output}"

  # Print all valid datastores, trimming any trailing space
  echo "$all_datastores" | sed 's/ *$//'
  return 0
}

# Finds a VM across ALL datastores (bhyve-cli and vm-bhyve).
# Arg1: vmname
# Returns:
#   A single line in the format "source:datastore_name:datastore_path" if found.
#   - source is either "bhyve-cli" or "vm-bhyve".
#   - e.g., "bhyve-cli:local_ds1:/home/alif/vmbhvye"
#   - e.g., "vm-bhyve:datastore2:/vm/datastore2"
#   Returns an empty string if not found.
#   If a VM with the same name exists in multiple places, it returns the first one found (bhyve-cli takes precedence).
find_any_vm() {
  local vmname="$1"

  # 1. Search in bhyve-cli datastores first
  local bhyve_cli_datastores
  bhyve_cli_datastores=$(get_all_bhyve_cli_datastores)
  for datastore_pair in $bhyve_cli_datastores; do
    local ds_name
    local ds_path
    ds_name=$(echo "$datastore_pair" | cut -d':' -f1)
    ds_path=$(echo "$datastore_pair" | cut -d':' -f2)

    if [ -d "$ds_path/$vmname" ] && [ -f "$ds_path/$vmname/vm.conf" ]; then
      echo "bhyve-cli:${ds_name}:${ds_path}"
      return 0
    fi
  done

  # 2. If not found, search in vm-bhyve datastores
  local vm_bhyve_datastores
  vm_bhyve_datastores=$(get_vm_bhyve_dir)
  if [ -n "$vm_bhyve_datastores" ]; then
    for datastore_pair in $vm_bhyve_datastores; do
      local ds_name
      local ds_path
      ds_name=$(echo "$datastore_pair" | cut -d':' -f1)
      ds_path=$(echo "$datastore_pair" | cut -d':' -f2)

      # vm-bhyve VMs have a directory and a .conf file with the same name inside
      if [ -d "$ds_path/$vmname" ] && [ -f "$ds_path/$vmname/$vmname.conf" ]; then
        echo "vm-bhyve:${ds_name}:${ds_path}"
        return 0
      fi
    done
  fi

  # 3. If not found anywhere
  echo ""
  return 1
}