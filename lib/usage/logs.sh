#!/usr/local/bin/bash

# === Usage function for logs ===
cmd_logs_usage() {
  echo_message "Usage: $0 logs <vm_name> [--tail <number_of_lines>] [-f]"
  echo_message "\nDescription:"
  echo_message "  Displays log messages for a specified virtual machine."
  echo_message "  By default, shows the last 100 lines of the log file."
  echo_message "\nOptions:"
  echo_message "  <vm_name>             The name of the virtual machine."
  echo_message "  --tail <number_of_lines>  Display the last <number_of_lines> of the log file."
  echo_message "  -f                    Follow (tail -f) the log file in real-time."
  echo_message "\nExamples:"
  echo_message "  $0 logs my_vm                 # Show last 100 lines of my_vm's log"
  echo_message "  $0 logs my_vm --tail 50       # Show last 50 lines of my_vm's log"
  echo_message "  $0 logs my_vm -f              # Follow my_vm's log in real-time"
}