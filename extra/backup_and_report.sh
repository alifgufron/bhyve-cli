#!/bin/sh

# ==============================================================================
# bhyve-cli VM Backup and Email Reporter
#
# Description:
#   This script exports specified bhyve VMs using bhyve-cli, then sends a
#   report via email for each one.
#
# Usage:
#   ./backup_and_report.sh <vm_name1> [vm_name2] [vm_name3] ...
#
# Dependencies:
#   - bhyve-cli
#   - sendmail
# ==============================================================================

# --- Configuration ---
# Email address to send the report to.
RECIPIENT_EMAIL="admin@example.com"

# Directory to store the exported VM archives.
BACKUP_DIR="/var/backups/bhyve"

# Full path to the bhyve-cli executable.
BHYVE_CLI_PATH="/usr/local/sbin/bhyve-cli"

# Log file for the script's operations.
LOG_FILE="/var/log/bhyve_backup.log"

# Export options
COMPRESSION_FORMAT="zst"
# Set export mode: --force-export, --suspend-export, --stop-export, or "" (empty)
EXPORT_MODE="--force-export"
# --- End of Configuration ---


# --- Helper Functions ---
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

send_email() {
    local subject="$1"
    local body="$2"

    # Construct a full email with MIME headers to ensure UTF-8 emojis render correctly.
    (
        echo "To: $RECIPIENT_EMAIL"
        echo "Subject: $subject"
        echo "MIME-Version: 1.0"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo "Content-Transfer-Encoding: 8bit"
        echo ""
        echo "$body"
    ) | /usr/sbin/sendmail -t

    log "Email report sent to $RECIPIENT_EMAIL with subject: $subject"
}

# --- Core Logic for a Single VM ---
process_single_vm() {
    local VM_NAME="$1"

    # Capture start time for duration calculation
    start_time=$(date +%s)

    log "--- Starting backup for VM: $VM_NAME ---"

    # 2. Get VM Info before export
    vm_info=$($BHYVE_CLI_PATH vm info "$VM_NAME" 2>> "$LOG_FILE")
    if [ $? -ne 0 ]; then
        error_msg="Failed to get info for VM '$VM_NAME'. It might not exist."
        log "Error: $error_msg"
        send_email "❌ FAILURE: bhyve VM Backup - $VM_NAME" "$error_msg"
        return 1
    fi
    # Parse various info fields
    vm_disk_size=$(echo "$vm_info" | grep "Set" | head -n 1 | awk '{print $3}')
    datastore_line=$(echo "$vm_info" | grep "Datastore")
    vm_manager=$(echo "$datastore_line" | sed -E -n 's/.*\((.*)\).*/\1/p')
    datastore_name=$(echo "$datastore_line" | awk -F'[:(]' '{print $2}' | tr -d ' ')

    # 3. Perform Export
    log "Exporting VM '$VM_NAME' to '$BACKUP_DIR' with options: --compression $COMPRESSION_FORMAT $EXPORT_MODE"
    raw_export_output=$($BHYVE_CLI_PATH vm export "$VM_NAME" "$BACKUP_DIR" --compression "$COMPRESSION_FORMAT" "$EXPORT_MODE" 2>&1)
    export_status=$?

    # Clean ANSI escape codes (from spinners, etc.) from the output
    export_output=$(echo "$raw_export_output" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g')

    # Parse the original file path created by bhyve-cli
    original_file_path=$(echo "$export_output" | grep "exported successfully to" | sed -E -n 's/.* to (.*)\.[[:space:]]*$/\1/p')
    # Remove any stray single quotes from the parsed path
    original_file_path=$(echo "$original_file_path" | tr -d "'")

    # 4. Generate and Send Report
    if [ $export_status -eq 0 ] && [ -n "$original_file_path" ] && [ -f "$original_file_path" ]; then
        # SUCCESS
        # Create a new unique filename with a full timestamp and rename the file
        filename_only=$(basename "$original_file_path")
        file_extension=".${filename_only#*.}" # Robustly get the full extension, e.g., .tar.zst

        datetime_stamp=$(date '+%Y-%m-%d_%H%M%S')
        new_filename="${VM_NAME}_${datetime_stamp}${file_extension}"
        new_file_path="${BACKUP_DIR}/${new_filename}"

        mv "$original_file_path" "$new_file_path"
        log "Renamed backup file to '$new_file_path'"

        # Use the new, renamed path for the report
        EXPORTED_FILE_PATH="$new_file_path"

        # Capture end time and calculate duration
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        formatted_duration=$(printf "%dm %ds" $((duration / 60)) $((duration % 60)))

        file_size=$(du -h "$EXPORTED_FILE_PATH" | awk '{print $1}')
        subject="✅ SUCCESS: bhyve VM Backup - $VM_NAME"
        body=$(cat <<EOF
Backup Report
---------------------------------
VM Name:          $VM_NAME
Manager:          $vm_manager
Datastore:        $datastore_name
Status:           ✅ SUCCESS
Date:             $(date '+%Y-%m-%d %H:%M:%S')
Duration:         $formatted_duration
Backup Location:  $EXPORTED_FILE_PATH
VM Disk Size:     $vm_disk_size (from config)
Exported Size:    $file_size
---------------------------------
EOF
)
        log "Successfully exported VM '$VM_NAME' to '$EXPORTED_FILE_PATH'."
    else
        # FAILURE
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        formatted_duration=$(printf "%dm %ds" $((duration / 60)) $((duration % 60)))

        subject="❌ FAILURE: bhyve VM Backup - $VM_NAME"
        body=$(cat <<EOF
Backup Report
---------------------------------
VM Name:          $VM_NAME
Manager:          $vm_manager
Datastore:        $datastore_name
Status:           ❌ FAILURE
Date:             $(date '+%Y-%m-%d %H:%M:%S')
Duration:         $formatted_duration
---------------------------------
Error Details:
$export_output
EOF
)
        log "Error exporting VM '$VM_NAME'. Details: $export_output"
    fi

    send_email "$subject" "$body"
    log "--- Finished backup for VM: $VM_NAME ---"

    return $export_status
}


# --- Main Dispatcher ---
main() {
    if [ $# -eq 0 ]; then
        echo "Error: No VM names provided."
        echo "Usage: $0 <vm_name1> [vm_name2] ..."
        log "Error: Script called without any VM names."
        exit 1
    fi

    log "Batch backup started for $# VMs."

    for vm_name in "$@"; do
        echo "Processing backup for: $vm_name"
        process_single_vm "$vm_name"
    done

    log "Batch backup finished."
    echo "All specified backups processed."
}

# Run main function with all script arguments
main "$@"
