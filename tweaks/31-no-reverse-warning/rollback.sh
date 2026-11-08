#!/bin/sh
# shellcheck disable=SC2154
for f in "$OPENCMU_ROOT"/jci/gui/resources/js/backupparking/backupparkingAppDict_*.js; do
  [ -f "$f" ] || continue
  rel=${f#"/"}
  [ -f "$OPENCMU_BACKUP/$rel" ] || continue
  rollback_path "$f"
done
