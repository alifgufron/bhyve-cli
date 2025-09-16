#!/usr/local/bin/bash

# Usage function for the 'datastore' command

datastore_usage() {
  cat <<EOF
Usage: $(basename "$0") datastore <subcommand> [options]

  Manage bhyve-cli datastores.

Subcommands:
  list              List all available bhyve-cli datastores.
  add <name> <path> Add a new datastore.
  delete <name>     Delete a datastore.

EOF
}
