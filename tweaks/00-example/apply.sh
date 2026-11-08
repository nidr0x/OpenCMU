#!/bin/sh
# Example tweak: write a marker file and back up anything it replaces.
# Sourced by apply_tweak with OPENCMU_* exported and common.sh loaded.

target="$OPENCMU_ROOT/data/opencmu/example-marker.txt"

record_created "$target"
backup_file "$target" >/dev/null || die "backup failed: $target"

mkdir -p "$(dirname "$target")"
tmp="$target.tmp.$$"
{
  echo "OpenCMU example tweak"
  echo "installed: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "firmware: ${ver:-unknown}"
} > "$tmp"
mv "$tmp" "$target"

log "example marker written: $target"
