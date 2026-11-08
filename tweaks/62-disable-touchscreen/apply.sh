#!/bin/sh
# shellcheck disable=SC2154
# The runtime is only started by /data/opencmu/boot.d, which tweak 60 sets up.
# Reusing that path keeps this tweak from adding a Service Manager entry or
# editing a stage script of its own.
boot="$OPENCMU_ROOT/data/opencmu/boot.d"
[ -f "$boot/README.txt" ] || die "boot.d missing: apply 60-startup-hook first"

src="$dir/disable-touchscreen.sh"
[ -f "$src" ] || die "runtime script missing: $src"
sh -n "$src" || die "runtime script has a syntax error: $src"

target="$boot/62-disable-touchscreen.sh"
record_created "$target"
backup_file "$target" >/dev/null || die "backup failed: $target"
cp "$src" "$target.opencmu-new.$$" || die "copy failed: $target"
chmod 755 "$target.opencmu-new.$$"
atomic_write "$target" "$target.opencmu-new.$$"
rm -f "$target.opencmu-new.$$"
log "installed touchscreen lock runtime: $target"
