#!/bin/sh
# shellcheck disable=SC2154
# The shim is third-party AGPL-3.0 code. OpenCMU never bundles it: the user
# points at a file and pins its digest, and the tweak refuses if either is
# missing or the digest does not match.
dir_on_unit="$OPENCMU_ROOT/data_persist/oem-aa-mod"
shim="$dir_on_unit/libpatch-blmjciaapa.so"
conf="$dir_on_unit/libpatch.conf"
src="${OPENCMU_AATOUCH_SHIM:-}"
want="${OPENCMU_AATOUCH_SHA256:-}"

[ -n "$src" ] || die "set OPENCMU_AATOUCH_SHIM to the libpatch-blmjciaapa.so you provide"
[ -n "$want" ] || die "set OPENCMU_AATOUCH_SHA256 to that shim's sha256"
[ -f "$src" ] || die "shim not found: $src"

got=$(sha256_file "$src")
want=$(printf '%s' "$want" | tr 'A-F' 'a-f')
[ "$got" = "$want" ] || die "shim sha256 mismatch: $got"

mkdir -p "$dir_on_unit" || die "cannot create $dir_on_unit"

record_created "$shim"
backup_file "$shim" >/dev/null || die "backup failed: $shim"
cp "$src" "$shim.opencmu-new.$$" || die "copy failed: $shim"
chmod 755 "$shim.opencmu-new.$$"
atomic_write "$shim" "$shim.opencmu-new.$$"
rm -f "$shim.opencmu-new.$$"
log "installed shim: $shim"

record_created "$conf"
backup_file "$conf" >/dev/null || die "backup failed: $conf"
cp "$dir/libpatch.conf" "$conf.opencmu-new.$$" || die "copy failed: $conf"
atomic_write "$conf" "$conf.opencmu-new.$$"
rm -f "$conf.opencmu-new.$$"
log "wrote shim config: $conf"
