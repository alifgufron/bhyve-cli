#!/usr/local/bin/bash

# === Usage function for vmnet ===
cmd_vmnet_usage() {
  echo_message "Usage: $0 vmnet <subcommand> [options/arguments]"
  echo_message "\nSubcommands:"
  echo_message "  create --name <bridge_name> [--ip <ip_address/cidr>] - Creates a new isolated virtual network bridge."
  echo_message "  list                                                 - Lists all configured vmnet bridges."
  echo_message "  destroy <bridge_name>                                - Destroys an isolated virtual network bridge."
  echo_message "  init                                                 - Initializes all saved vmnet configurations."
  echo_message "\nOptions for create:"
  echo_message "  --name <bridge_name>         - Name of the isolated bridge to create (e.g., myvmnet0)."
  echo_message "  --ip <ip_address/cidr>       - Optional. IP address and CIDR for the bridge interface (e.g., 192.168.1.1/24)."
  echo_message "\nExamples:"
  echo_message "  $0 vmnet create --name myvmnet0 --ip 192.168.1.1/24"
  echo_message "  $0 vmnet list"
  echo_message "  $0 vmnet destroy myvmnet0"
}
