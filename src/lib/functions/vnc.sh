#!/usr/local/bin/bash

# === Helper function to build VNC arguments ===
build_vnc_args() {
  local VNC_ARGS=""
  if [ -n "$VNC_PORT" ]; then
    VNC_ARGS="-s 29,fbuf,tcp=0.0.0.0:${VNC_PORT},w=800,h=600"
    if [ "$VNC_WAIT" = "yes" ]; then
      VNC_ARGS+=",wait"
    fi
    log "VNC arguments constructed: $VNC_ARGS"
  fi
  echo "$VNC_ARGS"
}
