#!/usr/bin/env bash

# ==============================================================================
# Bhyve VM Backup Script (backup-vmbhyve.sh)
#
# Description:
#   A single script to back up bhyve VMs. It can operate in two modes
#   based on its configuration file:
#   1. local: Backs up specified VMs on the local machine.
#   2. remote: Acts as a controller to orchestrate backups on remote nodes via SSH,
#      by piping its own content to the remote host for execution.
#
# Usage:
#   ./backup-vmbhyve.sh --config /path/to/backup-vmbhyve.conf
# ==============================================================================

set -euo pipefail

# --- HELPER FUNCTIONS ---

# All functions needed by the script are defined here, so they are available
# whether the script is running as a controller or a remote worker.

log() {
    # This function formats a message and writes it to stdout and any configured log files.
    local message
    message="$(date '+%Y-%m-%d %H:%M:%S') - $1"
    
    # Always echo to stdout for interactive display.
    echo "$message"

    # Also log to the persistent log file if defined.
    if [ -n "${LOG_FILE:-}" ] && [ -w "$(dirname "${LOG_FILE:-.}")" ]; then
        echo "$message" >> "$LOG_FILE" || true # Make safe for set -e
    fi

    # Also log to the temporary run log file if defined (for the email summary).
    # This variable is only set in controller mode.
    if [ -n "${RUN_LOG_FILE:-}" ]; then
        echo "$message" >> "$RUN_LOG_FILE" || true # Make safe for set -e
    fi
}

format_bytes() {
    local bytes=$1
    if [ -z "$bytes" ] || [ "$bytes" -eq 0 ]; then echo "0B"; return; fi
    # Use awk for floating point math to avoid needing `bc`
    awk -v b="$bytes" 'BEGIN{
        s="BKMGT"; i=1;
        while(b >= 1024 && i < length(s)){ b/=1024; i++ }
        printf "%.2f%s\n", b, substr(s,i,1)
    }'
}

# --- WORKER LOGIC ---
# This function contains the logic to back up a single VM.
# It is called directly in local mode and by the worker in remote mode.

process_single_vm() {
    local VM_NAME="$1"
    local HOSTNAME
    HOSTNAME=$(hostname -s)
    local subject=""
    local body=""
    local return_status=0 # 0=success, 1=failure
    local start_time
    start_time=$(date +%s)

    log "--- [Worker on $HOSTNAME] Starting backup for VM: $VM_NAME ---"

    # 1. Prerequisite check: bhyve-cli
    if [ ! -x "$BHYVE_CLI_PATH" ]; then
        local error_msg="bhyve-cli not found or not executable at '$BHYVE_CLI_PATH' on node '$HOSTNAME'."
        log "Error: $error_msg"
        subject="❌ [Backup FAILURE] $VM_NAME @ $HOSTNAME"
        body="$error_msg"
        echo "1###$subject###$body"
        return 1
    fi

    # 2. Prerequisite check: Backup directory
    if ! mkdir -p "$BACKUP_DIR"; then
        local error_msg="Could not create backup directory '$BACKUP_DIR' on node '$HOSTNAME'. Check permissions."
        log "Error: $error_msg"
        subject="❌ [Backup FAILURE] $VM_NAME @ $HOSTNAME"
        body="$error_msg"
        echo "1###$subject###$body"
        return 1
    fi

    # 3. Get VM Info
    local vm_info
    vm_info=$($BHYVE_CLI_PATH vm info "$VM_NAME" 2>&1)
    if [ $? -ne 0 ]; then
        local error_msg="Failed to get info for VM '$VM_NAME' on node '$HOSTNAME'. It might not exist. Output: $vm_info"
        log "Error: $error_msg"
        subject="❌ [Backup FAILURE] $VM_NAME @ $HOSTNAME"
        body="$error_msg"
        echo "1###$subject###$body"
        return 1
    fi
    local vm_disk_size
    vm_disk_size=$(echo "$vm_info" | grep "Set" | head -n 1 | awk '{print $3}')
    local datastore_line
    datastore_line=$(echo "$vm_info" | grep "Datastore")
    # Corrected sed pattern to look for parentheses `()` instead of square brackets `[]`.
    local vm_manager
    vm_manager=$(echo "$datastore_line" | sed -E -n 's/.*\((.*)\).*/\1/p')
    local datastore_name
    datastore_name=$(echo "$datastore_line" | awk -F'[:(]' '{print $2}' | tr -d ' ')

    # 4. Perform Export
    log "[Worker on $HOSTNAME] Exporting VM '$VM_NAME' to '$BACKUP_DIR'..."
    local raw_export_output
    raw_export_output=$($BHYVE_CLI_PATH vm export "$VM_NAME" "$BACKUP_DIR" --compression "$COMPRESSION_FORMAT" "$EXPORT_MODE" 2>&1)
    local export_status=$?
    local export_output
    export_output=$(echo "$raw_export_output" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g') # Clean ANSI codes
    local original_file_path
    original_file_path=$(echo "$export_output" | grep "exported successfully to" | sed -E -n "s/.* to '(.*)'\.[[:space:]]*$/\1/p")

    # 5. Process result
    if [ $export_status -eq 0 ] && [ -n "$original_file_path" ] && [ -f "$original_file_path" ]; then
        # SUCCESS
        local datetime_stamp; datetime_stamp=$(date '+%Y-%m-%d_%H%M%S')
        local new_filename="${VM_NAME}_${datetime_stamp}.tar.${COMPRESSION_FORMAT}"
        local new_file_path="${BACKUP_DIR}/${new_filename}"
        mv "$original_file_path" "$new_file_path"
        log "[Worker on $HOSTNAME] Renamed backup file to '$new_file_path'"

        local end_time; end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local formatted_duration; formatted_duration=$(printf "%dm %ds" $((duration / 60)) $((duration % 60)))
        local file_size; file_size=$(du -h "$new_file_path" | awk '{print $1}')
        
        # Perform cleanup of old backups
        if [ "$RETENTION_COUNT" -gt 0 ]; then
            log "[Worker on $HOSTNAME] Cleaning old backups for $VM_NAME (retention: $RETENTION_COUNT)"
            # This complex command is safer than using xargs with rm
            find "$BACKUP_DIR" -maxdepth 1 -type f -name "${VM_NAME}_*.tar.*" -print0 | xargs -0 ls -t | tail -n "+$((RETENTION_COUNT + 1))" | xargs -r -I {} rm -- {}
        fi

        # --- Collect and format retained backup information ---
        local RETAINED_BACKUPS_INFO=""
        local RETAINED_BACKUPS_LIST
        RETAINED_BACKUPS_LIST=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "${VM_NAME}_*.tar.*" -print0 | xargs -0 ls -t 2>/dev/null)
        local TOTAL_BACKUP_SIZE_BYTES=0

        if [ -n "$RETAINED_BACKUPS_LIST" ]; then
            RETAINED_BACKUPS_INFO="🗄️ List VM Backup:\n"
            while IFS= read -r file; do
                local file_date; file_date=$(date -r "$file" '+%Y-%m-%d %H:%M:%S')
                # Use stat for more reliable size calculation in bytes
                local file_size_bytes; file_size_bytes=$(stat -f%z "$file")
                TOTAL_BACKUP_SIZE_BYTES=$((TOTAL_BACKUP_SIZE_BYTES + file_size_bytes))
                local file_size_human; file_size_human=$(format_bytes "$file_size_bytes")
                RETAINED_BACKUPS_INFO+="   - $file_date  $(basename "$file")  $file_size_human\n"
            done <<< "$RETAINED_BACKUPS_LIST"
        else
            RETAINED_BACKUPS_INFO="🗄️ No retained backups found for this VM.\n"
        fi
        local TOTAL_BACKUP_SIZE_HUMAN; TOTAL_BACKUP_SIZE_HUMAN=$(format_bytes "$TOTAL_BACKUP_SIZE_BYTES")
        # --- End of retained backup information collection ---

        subject="✅ [Backup SUCCESS] VM Bhyve $VM_NAME @ $HOSTNAME"
        body=$(cat <<EOF
Backup Report for $VM_NAME from $HOSTNAME

$(printf "%-18s: %s\n" "VM Name" "$VM_NAME")
$(printf "%-18s: %s\n" "Manager" "$vm_manager")
$(printf "%-18s: %s\n" "Datastore" "$datastore_name")
$(printf "%-18s: %s\n" "Status" "SUCCESS")
$(printf "%-18s: %s\n" "Date" "$(date '+%Y-%m-%d %H:%M:%S')")
$(printf "%-18s: %s\n" "Duration" "$formatted_duration")
$(printf "%-18s: %s\n" "Backup Location" "$new_file_path")
$(printf "%-18s: %s\n" "VM Disk Size" "$vm_disk_size (from config)")
$(printf "%-18s: %s\n" "Exported Size" "$file_size")

$(printf "%b" "$RETAINED_BACKUPS_INFO")
Total Backuped $VM_NAME: $TOTAL_BACKUP_SIZE_HUMAN
EOF
)
        log "[Worker on $HOSTNAME] Successfully backed up '$VM_NAME'."
        return_status=0
    else
        # FAILURE
        local end_time; end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local formatted_duration; formatted_duration=$(printf "%dm %ds" $((duration / 60)) $((duration % 60)))
        subject="❌ [Backup FAILURE] VM Bhyve $VM_NAME @ $HOSTNAME"
        body=$(cat <<EOF
Backup Report for $VM_NAME from $HOSTNAME

$(printf "%-18s: %s\n" "VM Name" "$VM_NAME")
$(printf "%-18s: %s\n" "Status" "FAILURE")
$(printf "%-18s: %s\n" "Date" "$(date '+%Y-%m-%d %H:%M:%S')")
$(printf "%-18s: %s\n" "Duration" "$formatted_duration")
---------------------------------
Error Details:
$export_output
EOF
)
        log "Error: [Worker on $HOSTNAME] Failed to back up '$VM_NAME'. Details: $export_output"
        return_status=1
    fi
    
    # Send the individual email report from the worker if enabled
    if [ "${SEND_INDIVIDUAL_REPORTS:-false}" == "true" ]; then
        log "[Worker on $HOSTNAME] Sending individual email report for $VM_NAME."
        send_email_report "$subject" "$body"
    fi
    
    return $return_status
}

# --- CONTROLLER LOGIC ---

# A self-contained mail function inspired by the user-provided script.
# It uses the system's 'sendmail' binary and constructs a proper email body with headers.
# Arg1: To, Arg2: From, Arg3: Subject, Arg4: Body
internal_sendmail() {
    local to="$1"
    local from="$2"
    local subject="$3"
    local body="$4"
    local sendmail_path

    # Find the system sendmail binary.
    if [ -x "/usr/sbin/sendmail" ]; then
        sendmail_path="/usr/sbin/sendmail"
    else
        # Fallback to checking PATH if not in the standard location.
        sendmail_path=$(command -v sendmail)
    fi

    if [ -z "$sendmail_path" ]; then
        log "  -> ERROR: 'sendmail' binary not found in /usr/sbin/sendmail or in PATH."
        return 1
    fi

    # Create the email content with headers
    local mail_content
    mail_content=$(cat <<EOF
From: ${from}
To: ${to}
Subject: ${subject}
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit

${body}
EOF
)

    # Pipe the content to sendmail -t, which reads headers from the content.
    echo -e "${mail_content}" | "$sendmail_path" -t

    return $?
}

send_email_report() {
    local subject="$1"
    local body="$2"
    
    # Call the new internal function
    internal_sendmail "$RECIPIENT_EMAIL" "$SENDER_EMAIL" "$subject" "$body"
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log "[Controller] ERROR: Failed to send email report (Subject: $subject, Exit Code: $exit_code)."
        log "[Controller] Please check mail system logs (e.g., /var/log/maillog) for details."
    else
        log "[Controller] Successfully sent email report (Subject: $subject)."
    fi
    return $exit_code
}

run_local_backups() {
    log "========== [Controller] Starting Local Backup Run =========="
    local vms_to_backup=($LOCAL_VMS)
    if [ ${#vms_to_backup[@]} -eq 0 ]; then
        log "Warning: BACKUP_MODE is 'local' but LOCAL_VMS is empty. Nothing to do."
        return
    fi

    local success_count=0
    local failure_count=0
    local summary_body="Summary for Local Backup Run on $(hostname -s):\n\n"

    for vm_name in "${vms_to_backup[@]}"; do
        local result; result=$(process_single_vm "$vm_name")
        local status; status=$(echo "$result" | cut -d'#' -f1)
        local subject; subject=$(echo "$result" | cut -d'#' -f2)
        local body; body=$(echo "$result" | cut -d'#' -f3)
        local duration; duration=$(echo "$result" | cut -d'#' -f4)

        if [ "$status" -eq 0 ]; then
            ((success_count++))
            log "[Controller] Result for '$vm_name': $subject (Duration: $duration)"
        else
            ((failure_count++))
            log "[Controller] Result for '$vm_name': $subject (Duration: $duration)"
        fi
        summary_body+="$subject (Duration: $duration)\n"
        if [ "$SEND_INDIVIDUAL_REPORTS" == "true" ]; then
            send_email_report "$subject" "$body"
        fi
    done

    local total_vms=$((success_count + failure_count))
    summary_body+="\nFinished. Total: $total_vms | Success: $success_count | Failed: $failure_count"
    log "$summary_body"

    log "========== [Controller] Local Backup Run Finished =========="
}

run_remote_backups() {
    log "========== [Controller] Starting Remote Backup Run =========="
    if [ ${#VM_GROUPS[@]} -eq 0 ]; then
        log "Error: BACKUP_MODE is 'remote' but VM_GROUPS is empty. Nothing to do."
        return
    fi

    local total_success=0
    local total_failure=0

    for node in "${!VM_GROUPS[@]}"; do
        local vms_on_node="${VM_GROUPS[$node]}"
        log "--- Processing Node: $node ---"
        
        local ssh_opts; ssh_opts="-T -p ${SSH_PORT} -i ${SSH_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10"

        # Pre-flight check for SSH connection
        if ! $CMD_SSH $ssh_opts "$SSH_USER@$node" "exit"; then
            log "Error: SSH connection to node '$node' failed. Skipping all VMs for this node."
            ((total_failure += $(echo "$vms_on_node" | wc -w)))
            continue
        fi
        log "[Controller] SSH Connection to '$node' successful."

        # Pre-flight check for remote backup directory
        if ! $CMD_SSH $ssh_opts "$SSH_USER@$node" "test -d \"$BACKUP_DIR\""; then
            log "Error: Backup directory '$BACKUP_DIR' not found on remote node '$node'. Skipping all VMs for this node."
            ((total_failure += $(echo "$vms_on_node" | wc -w)))
            continue
        fi
        log "[Controller] Remote backup directory '$BACKUP_DIR' found on '$node'."
        
        local node_success=0
        local node_failure=0
        
        for vm_name in $vms_on_node; do
            log "[Controller] Triggering backup for '$vm_name' on '$node'..."
            
            local config_base64; config_base64=$(base64 < "$custom_config_file" | tr -d '\n')
            local remote_cmd; remote_cmd="sudo /usr/local/bin/bash -s -- --worker '$vm_name' --config_base64 '$config_base64'"
            
            local start_time; start_time=$(date +%s)
            
            # Execute the remote command.
            $CMD_SSH $ssh_opts "$SSH_USER@$node" "$remote_cmd" < "$0" 1>/dev/null 2>> "$RUN_LOG_FILE"
            local ssh_exit_code=$?

            local end_time; end_time=$(date +%s)
            local duration=$((end_time - start_time))
            local formatted_duration; formatted_duration=$(printf "%dm %ds" $((duration / 60)) $((duration % 60)))

            if [ "$ssh_exit_code" -eq 0 ]; then
                log "[Controller] Result for '$vm_name' on '$node': ✅ SUCCESS (Duration: $formatted_duration)"
                # Use a safe block for arithmetic to prevent non-zero exit codes with `set -e`.
                if ((node_success++)); ((total_success++)); then :; fi
            else
                log "[Controller] Result for '$vm_name' on '$node': ❌ FAILED (Exit Code: $ssh_exit_code, Duration: $formatted_duration)"
                # Use a safe block for arithmetic to prevent non-zero exit codes with `set -e`.
                if ((node_failure++)); ((total_failure++)); then :; fi
            fi
        done
        log "Node '$node' summary: Success: $node_success, Failed: $node_failure"
    done
    
    log "Finished. Overall Success: $total_success, Overall Failure: $total_failure"

    log "========== [Controller] Remote Backup Run Finished =========="
}


# --- MAIN DISPATCHER ---

main() {
    # This script is designed to be self-contained. The same file is used
    # as the controller and piped over SSH to act as the worker.

    local custom_config_file=""
    local worker_vm_name=""
    local config_base64=""

    # 1. Parse Arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --config) 
                custom_config_file=$2; shift 2 ;;
            --worker) 
                worker_vm_name=$2; shift 2 ;;
            --config_base64)
                config_base64=$2; shift 2;;
            -h | --help) 
                echo "Usage: $0 --config /path/to/config"
                echo "  or internal worker call: $0 --worker <vm_name> --config_base64 <...>"
                exit 0 ;; 
            *)
                echo "Error: Unknown argument $1" >&2; exit 1 ;; 
        esac
    done

    # 2. Determine Execution Mode (Worker or Controller?)
    if [ -n "$worker_vm_name" ]; then
        # WORKER MODE
        # Redefine the log function for worker mode to ensure logs go to stderr,
        # keeping stdout clean for the result string.
        log() {
            echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
        }

        # Load configuration passed by the controller as a base64 string
        if [ -n "$config_base64" ]; then
            # Decode the config and evaluate it in the current bash context.
            eval "$(echo "$config_base64" | base64 -d)"
        else
            # This echo needs to go to stderr as well so it doesn't become the result line.
            echo "Error: Worker mode requires --config_base64." >&2
            exit 1
        fi
        process_single_vm "$worker_vm_name"
    else
        # CONTROLLER MODE
        if [ ! -f "$custom_config_file" ]; then
            log "Error: You must specify a configuration file using --config <path>."
            exit 1
        fi
        # shellcheck source=/dev/null
        source "$custom_config_file"

        # Define and export the temporary log file for this run.
        # It will be written to by the 'log' function and the ssh stderr redirection.
        export RUN_LOG_FILE; RUN_LOG_FILE=$(mktemp "/tmp/unified_backup_run.log.XXXXXX")
        
        # Ensure cleanup on script exit
        trap '[ -n "${RUN_LOG_FILE:-}" ] && rm -f "$RUN_LOG_FILE"' EXIT

        # --- Stage 1: Execute ---
        # Run the backup functions directly. The 'log' function and stderr redirection
        # will handle populating the RUN_LOG_FILE and persistent LOG_FILE.
        if [ "$BACKUP_MODE" == "local" ]; then
            run_local_backups
        elif [ "$BACKUP_MODE" == "remote" ]; then
            run_remote_backups
        else
            log "Error: Invalid BACKUP_MODE: '$BACKUP_MODE'. Must be 'local' or 'remote'."
        fi

        # --- Stage 2: Report ---
        # This stage is executed after the backup and logging are complete.
        if [ "${SEND_SUMMARY_REPORT:-false}" == "true" ]; then
            # Grep the completed run log file for success/failure markers.
            # `|| true` prevents the script from exiting if grep finds no matches.
            local success_count; success_count=$(grep -c '✅ SUCCESS' "$RUN_LOG_FILE" || true)
            local failure_count; failure_count=$(grep -c '❌ FAILED' "$RUN_LOG_FILE" || true)

            if [ "$((success_count + failure_count))" -gt 0 ]; then
                local summary_subject="[Backup VM Bhyve] Summary - Run Complete - ${success_count} Success, ${failure_count} Failed on $(hostname -s)"
                local full_log_body; full_log_body=$(<"$RUN_LOG_FILE")
                local email_body; email_body="Detail Log:\n\n${full_log_body}"
                
                send_email_report "$summary_subject" "$email_body"

                # Truncate the main log file if it's configured.
                if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE}" ]; then
                    log "Truncating main log file: ${LOG_FILE}"
                    > "${LOG_FILE}"
                fi
            fi
        fi
    fi
}

# Run the main function with all provided script arguments
main "$@"
