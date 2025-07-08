#!/bin/sh

BASEPATH="/home/admin/vm-bhvye/vm"

printf "%-20s %-10s %-17s %-7s %-6s\n" "VM NAME" "STATUS" "MAC ADDRESS" "TAP" "PID"
echo "--------------------------------------------------------------------------"

for VMCONF in "$BASEPATH"/*/vm.conf; do
  [ -f "$VMCONF" ] || continue
  . "$VMCONF"

  # ==== Cek status VM dan ambil PID
  PID=$(pgrep -f "bhyve.*$VMNAME")
  if [ -n "$PID" ]; then
    STATUS="RUNNING"
  else
    STATUS="STOPPED"
    PID="-"
  fi

  printf "%-20s %-10s %-17s %-7s %-6s\n" "$VMNAME" "$STATUS" "$MAC" "$TAP" "$PID"
done
