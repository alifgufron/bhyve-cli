#!/usr/local/bin/bash

# === Usage function for switch init ===
cmd_switch_init_usage() {
  echo_message "Usage: $0 switch init"
  echo_message "\nDescription:"
  echo_message "  Re-initializes all saved switch configurations from the switch config file."
  echo_message "  This is useful for restoring network configuration after a host reboot."
}

# === Usage function for switch add ===
cmd_switch_add_usage() {
  echo_message "Usage: $0 switch add --name <bridge_name> --interface <physical_interface> [--vlan <vlan_tag>]"
  echo_message "\nOptions:"
  echo_message "  --name <bridge_name>         - Name of the bridge or vSwitch."
  echo_message "  --interface <physical_interface> - Parent physical network interface (e.g., em0, igb1)."
  echo_message "  --vlan <vlan_tag>            - Optional. VLAN ID if the parent interface is in trunk mode. A VLAN interface (e.g., vlan100) will be created on top of the physical interface and tagged to the bridge."
}


# === Usage function for switch destroy ===
cmd_switch_destroy_usage() {
  echo_message "Usage: $0 switch destroy <bridge_name>"
  echo_message "\nArguments:"
  echo_message "  <bridge_name> - The name of the bridge to destroy."
}

# === Usage function for switch delete ===
cmd_switch_delete_usage() {
  echo_message "\nUsage: $0 switch delete --member <interface> --from <bridge_name>"
  echo_message "\nOptions:"
  echo_message "  --member <interface> \t- The specific member interface to remove (e.g., tap0, vlan100)."
  echo_message "  --from <bridge_name> \t- The bridge from which to remove the member."
}

# === Usage function for switch ===
cmd_switch_usage() {
  echo_message "Usage: $0 switch [subcommand] [Option] [Arguments]"
  echo_message "\nSubcommands:"
  echo_message "  init        - Re-initialize all saved switch configurations."
  echo_message "  add         - Create a bridge and add a physical interface"

  echo_message "  list        - List all bridge interfaces and their members"
  echo_message "  destroy     - Destroy a bridge and all its members"
  echo_message "  delete      - Remove a specific member from a bridge"
}
