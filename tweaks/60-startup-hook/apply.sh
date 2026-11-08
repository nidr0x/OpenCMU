#!/bin/sh
# shellcheck disable=SC2154
# A new sm.conf service would be a boot-path change we cannot validate without
# a bench unit. Hooking the end of a stock stage script is smaller: the block
# runs after the stage did its work, in the background, and does nothing when
# the directory is empty.
stage="${OPENCMU_HOOK_STAGE:-jci/scripts/stage_gap2.sh}"
target="$OPENCMU_ROOT/$stage"
[ -f "$target" ] || die "stage script not found: $target"

append_once "$target" 'opencmu:boot-hook' "$dir/boot-hook.sh"

readme="$OPENCMU_ROOT/data/opencmu/boot.d/README.txt"
mkdir -p "$(dirname "$readme")" || die "cannot create boot.d"
record_created "$readme"
backup_file "$readme" >/dev/null || die "backup failed: $readme"
cp "$dir/README.txt" "$readme.opencmu-new.$$" || die "copy failed: $readme"
atomic_write "$readme" "$readme.opencmu-new.$$"
rm -f "$readme.opencmu-new.$$"
log "boot.d ready: $readme"
