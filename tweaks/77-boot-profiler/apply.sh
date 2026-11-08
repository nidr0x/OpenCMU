#!/bin/sh
# shellcheck disable=SC2154
# The runtime is only started by /data/opencmu/boot.d, which tweak 60 sets up.
# Like the other runtimes nothing here runs while installing on a mounted
# image, so the profiler only exists after the next boot.
boot="$OPENCMU_ROOT/data/opencmu/boot.d"
[ -f "$boot/README.txt" ] || die "boot.d missing: apply 60-startup-hook first"

src="$dir/boot-profiler.sh"
[ -f "$src" ] || die "runtime script missing: $src"
sh -n "$src" || die "runtime script has a syntax error: $src"

target="$boot/77-boot-profiler.sh"
record_created "$target"
backup_file "$target" >/dev/null || die "backup failed: $target"
cp "$src" "$target.opencmu-new.$$" || die "copy failed: $target"
chmod 755 "$target.opencmu-new.$$"
atomic_write "$target" "$target.opencmu-new.$$"
rm -f "$target.opencmu-new.$$"
log "installed boot profiler runtime: $target"
