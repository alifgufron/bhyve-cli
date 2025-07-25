#!/usr/local/bin/bash

# === Usage function for template ===
cmd_template_usage() {
  echo_message "Usage: $0 template <subcommand> [options/arguments]"
  echo_message "\nSubcommands:"
  echo_message "  create <source_vmname> <template_name> - Creates a new template from an existing VM."
  echo_message "  list                                   - Lists all available VM templates."
  echo_message "  delete <template_name>                 - Deletes a specified template."
  echo_message "\nExamples:"
  echo_message "  $0 template create myvm my_template"
  echo_message "  $0 template list"
  echo_message "  $0 template delete my_template"
}

