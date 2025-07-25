#!/usr/local/bin/bash

# === Subcommand: switch init ===
cmd_switch_init() {
    if [ ! -f "$SWITCH_CONFIG_FILE" ]; then
        display_and_log "INFO" "Switch configuration file not found. Nothing to do."
        return
    fi

    display_and_log "INFO" "Initializing switches from $SWITCH_CONFIG_FILE..."
    while read -r bridge_name phys_if vlan_tag; do
        local args=("--name" "$bridge_name" "--interface" "$phys_if" "--no-save")
        if [ -n "$vlan_tag" ]; then
            args+=("--vlan" "$vlan_tag")
        fi
        cmd_switch_add "${args[@]}"
    done < "$SWITCH_CONFIG_FILE"
    display_and_log "INFO" "Switch initialization complete."
}
