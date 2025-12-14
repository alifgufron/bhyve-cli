#!/usr/bin/env bash
#
# vmdump.sh - Unified Bhyve VM Backup Script
#
# This script can run in two modes:
# 1. Controller Mode: Reads a config file, and orchestrates backups on remote nodes via SSH.
# 2. Worker Mode (--local): Runs on a local or remote machine to perform the actual backup of a specific VM.

set -euo pipefail

# --- SCRIPT LOGIC ---

# Find and load the configuration file
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
CONFIG_FILE="${SCRIPT_DIR}/backup.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found at $CONFIG_FILE. This file is mandatory." >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_FILE"

# --- HELPER FUNCTIONS (for Worker Mode) ---

log() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') - $1"
    # Always write to the log file
    echo "$message" >> "$LOG_FILE"
    # Also write to console if running interactively
    if [ -t 1 ]; then
        echo "$message"
    fi
}

send_email() {
    local subject="$1"
    local body="$2"
    (   echo "To: $RECIPIENT_EMAIL";
        echo "Subject: $subject";
        echo "MIME-Version: 1.0";
        echo "Content-Type: text/plain; charset=UTF-8";
        echo "Content-Transfer-Encoding: 8bit";
        echo "";
        echo -e "$body";
    ) | /usr/sbin/sendmail -t
    log "Email report sent to $RECIPIENT_EMAIL with subject: $subject"
}

format_bytes() {
    local bytes=$1
    if [ -z "$bytes" ] || [ "$bytes" -eq 0 ]; then echo "0B"; return;
    elif (( bytes < 1024 )); then echo "${bytes}B";
    elif (( bytes < 1024 * 1024 )); then printf "%.2fK" $(echo "$bytes / 1024" | bc -l);
    elif (( bytes < 1024 * 1024 * 1024 )); then printf "%.2fM" $(echo "$bytes / (1024*1024)" | bc -l);
    else printf "%.2fG" $(echo "$bytes / (1024*1024*1024)" | bc -l); fi
}

cleanup_old_backups() {
    local VM_NAME="$1"
    if [ "$RETENTION_COUNT" -le 0 ]; then log "Retention is disabled. Skipping cleanup."; return 0; fi
    log "Checking old backups for $VM_NAME (retention: $RETENTION_COUNT)"
    local backups
    backups=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "${VM_NAME}_*.tar.*" -print0 | xargs -0 ls -t)
    local num_backups=$(echo "$backups" | wc -l | tr -d ' ')
    if [ "$num_backups" -gt "$RETENTION_COUNT" ]; then
        local to_delete
        to_delete=$(echo "$backups" | tail -n "$((num_backups - RETENTION_COUNT))")
        log "Found $num_backups backups. Deleting $((num_backups - RETENTION_COUNT)) oldest..."
        echo "$to_delete" | while IFS= read -r file; do
            if [ -f "$file" ]; then log "Deleting old backup: $file"; rm "$file"; fi
        done
    fi
}

process_single_vm() {
    local VM_NAME="$1"
    local HOSTNAME
    HOSTNAME=$(hostname -s)
    local subject=""
    local body=""
    local return_status=0

    start_time=$(date +%s)
    log "--- Starting backup for VM: $VM_NAME on node $HOSTNAME ---"

    vm_info=$($BHYVE_CLI_PATH vm info "$VM_NAME" 2>> "$LOG_FILE")
    if [ $? -ne 0 ]; then
        error_msg="Failed to get info for VM '$VM_NAME'. It might not exist."
        log "Error: $error_msg"
        subject="❌ [Backup FAILURE] VM Bhyve $VM_NAME - From $HOSTNAME"
        body="$error_msg"
        return_status=1
    else
        vm_disk_size=$(echo "$vm_info" | grep "Set" | head -n 1 | awk '{print $3}')
        datastore_line=$(echo "$vm_info" | grep "Datastore")
        vm_manager=$(echo "$datastore_line" | sed -E -n 's/.*\((.*)\).*/\1/p')
        datastore_name=$(echo "$datastore_line" | awk -F'[:(]' '{print $2}' | tr -d ' ')

        log "Exporting VM '$VM_NAME' to '$BACKUP_DIR'..."
        raw_export_output=$($BHYVE_CLI_PATH vm export "$VM_NAME" "$BACKUP_DIR" --compression "$COMPRESSION_FORMAT" "$EXPORT_MODE" 2>&1)
        export_status=$?
        export_output=$(echo "$raw_export_output" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g')
        original_file_path=$(echo "$export_output" | grep "exported successfully to" | sed -E -n "s/.* to '(.*)'\.[[:space:]]*$/\1/p")

        if [ $export_status -eq 0 ] && [ -n "$original_file_path" ] && [ -f "$original_file_path" ]; then
            datetime_stamp=$(date '+%Y-%m-%d_%H%M%S')
            new_filename="${VM_NAME}_${datetime_stamp}.tar.${COMPRESSION_FORMAT}"
            new_file_path="${BACKUP_DIR}/${new_filename}"
            mv "$original_file_path" "$new_file_path"
            log "Renamed backup file to '$new_file_path'"

            end_time=$(date +%s)
            duration=$((end_time - start_time))
            formatted_duration=$(printf "%dm %ds" $((duration / 60)) $((duration % 60)))
            file_size=$(du -h "$new_file_path" | awk '{print $1}')

            cleanup_old_backups "$VM_NAME"

            retained_info_temp=""
            retained_list_raw=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "${VM_NAME}_*.tar.*" -print0 | xargs -0 ls -t)
            total_size_bytes=0
            if [ -n "$retained_list_raw" ]; then
                retained_info_temp="🗄️ List VM Backup:\n"
                while IFS= read -r file; do
                    file_date=$(date -r "$file" '+%Y-%m-%d %H:%M:%S')
                    size_k=$(du -k "$file" | awk '{print $1}')
                    total_size_bytes=$((total_size_bytes + size_k))
                    size_h=$(du -h "$file" | awk '{print $1}')
                    retained_info_temp+="   - $file_date  $(basename "$file")  $size_h\n"
                done <<< "$retained_list_raw"
            fi
            total_size_human=$(format_bytes "$((total_size_bytes * 1024))")

            subject="✅ [Backup SUCCESS] VM Bhyve $VM_NAME - From $HOSTNAME"
            body="Backup Report for $VM_NAME from $HOSTNAME\n\n"
            body+="📦 VM Name:          $VM_NAME\n"
            body+="⚙️ Manager:          $vm_manager\n"
            body+="💾 Datastore:        $datastore_name\n"
            body+="❤️ Status:           SUCCESS\n"
            body+="📅 Date:             $(date '+%Y-%m-%d %H:%M:%S')\n"
            body+="⌛ Duration:         $formatted_duration\n"
            body+="🔗 Backup Location:  $new_file_path\n"
            body+="💽 VM Disk Size:     $vm_disk_size (from config)\n"
            body+="🗃️ Exported Size:    $file_size\n\n"
            body+="$(printf '%b' "$retained_info_temp")\n"
            body+="Total Backuped $VM_NAME: $total_size_human"
            log "Successfully exported VM '$VM_NAME' to '$new_file_path'."
            return_status=0
        else
            subject="❌ [Backup FAILURE] VM Bhyve $VM_NAME - From $HOSTNAME"
            body="Backup Report for $VM_NAME from $HOSTNAME\n\n... (error details) ...\n$export_output"
            log "Error exporting VM '$VM_NAME'. Details: $export_output"
            return_status=1
        fi
    fi
    log "--- Finished backup for VM: $VM_NAME ---"
    
    # Return a structured string: status_code###subject###body
    echo "$return_status###$subject###$body"
}

usage() {
    echo "Usage: $0 --config <path>

This script backs up bhyve VMs based on the provided configuration file.

The behavior of the script is determined by the BACKUP_MODE variable
set inside the config file:
  - BACKUP_MODE=\"local\":  Backs up VMs listed in LOCAL_VMS on the local machine.
  - BACKUP_MODE=\"remote\": Backs up VMs on remote nodes defined in VM_GROUPS.

OPTIONS:
  --config=<path>        (Required) Path to the configuration file.
  -h, --help             Show this help message.
" >&2
    exit 1
}

# --- MAIN DISPATCHER ---

main() {
    local custom_config_file=""
    local worker_vm_name=""

    # Pre-parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -h | --help) usage ;;
            --config)
                if [ -z "$2" ]; then echo "Error: --config requires a path." >&2; exit 1; fi
                custom_config_file=$2
                shift 2
                ;;
            --worker)
                if [ -z "$2" ]; then echo "Error: --worker requires a VM name." >&2; exit 1; fi
                worker_vm_name=$2
                shift 2
                ;;
            *) echo "Error: Unknown argument or value: $1" >&2; usage ;;
        esac
    done

    # --- Mode Execution ---

    # WORKER MODE (executed on remote node)
    # This mode is special and runs first. It requires a config file.
    if [ -n "$worker_vm_name" ]; then
        if [ -z "$custom_config_file" ]; then
            echo "Error: The --worker flag requires a --config flag to be specified." >&2
            exit 1
        fi
        if [ ! -f "$custom_config_file" ]; then
            echo "Error: Configuration file not found at $custom_config_file." >&2
            exit 1
        fi
        # shellcheck source=/dev/null
        source "$custom_config_file"
        process_single_vm "$worker_vm_name"
        exit $?
    fi

    # For any other mode, a config file must be provided.
    if [ -z "$custom_config_file" ]; then
        echo "Error: You must specify a configuration file using --config <path>." >&2
        usage
    fi
    if [ ! -f "$custom_config_file" ]; then
        echo "Error: Configuration file not found at $custom_config_file." >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$custom_config_file"

    # --- Main Logic Dispatcher ---
    if [ "$BACKUP_MODE" == "local" ]; then
        # LOCAL MODE
        log "Running in Local Mode for VMs: ${LOCAL_VMS}"
        local vms_to_backup=($LOCAL_VMS) # Convert space-separated string to array
        if [ ${#vms_to_backup[@]} -eq 0 ]; then
            log "Warning: BACKUP_MODE is 'local' but LOCAL_VMS is empty. Nothing to do."
            exit 0
        fi

        local success_count=0
        local failure_count=0
        local total_count=${#vms_to_backup[@]}
        local summary_body="Summary Report for Local Backup Run on $(hostname -s)\n\n"

        for vm_name in "${vms_to_backup[@]}"; do
            result=$(process_single_vm "$vm_name")
            status_code=$(echo "$result" | cut -d'#' -f1)
            subject=$(echo "$result" | cut -d'#' -f2)
            body=$(echo "$result" | cut -d'#' -f3)

            if [ "$status_code" -eq 0 ]; then
                ((success_count++))
                summary_body+="✅ $vm_name: SUCCESS\n"
            else
                ((failure_count++))
                summary_body+="❌ $vm_name: FAILURE\n"
            fi

            if [ "$REPORTING_MODE" == "individual" ]; then
                send_email "$subject" "$body"
            fi
        done

        summary_body+="\nTotal VMs: $total_count | Successful: $success_count | Failed: $failure_count"
        log "Local backup run finished. Total: $total_count, Successful: $success_count, Failed: $failure_count"

        if [ "$REPORTING_MODE" == "summary" ] && [ "$total_count" -gt 0 ]; then
            summary_subject="[Backup Summary] Local Run on $(hostname -s) - ${success_count} SUCCESS, ${failure_count} FAILURE"
            send_email "$summary_subject" "$summary_body"
        fi
        log "========== Local Backup Process Finished =========="

    elif [ "$BACKUP_MODE" == "remote" ]; then
        # CONTROLLER (REMOTE) MODE
        log "========== Backup Process Started (Controller Mode) =========="
        if [ ${#VM_GROUPS[@]} -eq 0 ]; then
            log "Error: BACKUP_MODE is 'remote' but VM_GROUPS array is empty in $custom_config_file. Nothing to do."
            exit 1
        fi

        local remote_script_path
        remote_script_path=$(realpath "$0")

        for node in "${!VM_GROUPS[@]}"; do
            local vms_on_node="${VM_GROUPS[$node]}"
            log "--- Processing Node: $node ---"
            
            local success_count=0
            local failure_count=0
            local total_count=0
            local summary_body="Summary Report for Node: $node\n\n"

            for vm_name in $vms_on_node; do
                ((total_count++))
                log "Triggering backup for VM '$vm_name' on node '$node'"
                
                remote_cmd="bash ${remote_script_path} --worker ${vm_name} --config=${custom_config_file}"
                ssh_opts="-p ${SSH_PORT} -i ${SSH_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10"
                result=$(ssh $ssh_opts "${SSH_USER}@${node}" "${remote_cmd}")
                ssh_exit_code=$?

                if [ $ssh_exit_code -ne 0 ]; then
                    ((failure_count++))
                    log "Error: SSH command failed for node '$node' (exit code: $ssh_exit_code)."
                    summary_body+="❌ $vm_name: SSH FAILURE (Could not connect or execute)\n"
                    if [ "$REPORTING_MODE" == "individual" ]; then
                        send_email "❌ [Backup FAILURE] VM Bhyve $vm_name - From $node" "Failed to connect to node $node via SSH."
                    fi
                    continue
                fi
                
                status_code=$(echo "$result" | cut -d'#' -f1)
                subject=$(echo "$result" | cut -d'#' -f2)
                body=$(echo "$result" | cut -d'#' -f3)

                if [ "$status_code" -eq 0 ]; then
                    ((success_count++))
                    summary_body+="✅ $vm_name: SUCCESS\n"
                else
                    ((failure_count++))
                    summary_body+="❌ $vm_name: FAILURE\n"
                fi

                if [ "$REPORTING_MODE" == "individual" ]; then
                    send_email "$subject" "$body"
                fi
            done
            
            summary_body+="\nTotal VMs: $total_count | Successful: $success_count | Failed: $failure_count"
            log "Node '$node' finished. Total: $total_count, Successful: $success_count, Failed: $failure_count"

            if [ "$REPORTING_MODE" == "summary" ] && [ "$total_count" -gt 0 ]; then
                summary_subject="[Backup Summary] Node: $node - ${success_count} SUCCESS, ${failure_count} FAILURE"
                send_email "$summary_subject" "$summary_body"
            fi
            log "--- Finished Node: $node ---"
        done

        log "========== Controller Mode Finished =========="
    else
        log "Error: Invalid BACKUP_MODE specified in $custom_config_file. Must be 'local' or 'remote'."
        exit 1
    fi
}

# Run the main dispatcher with all script arguments
main "$@"
