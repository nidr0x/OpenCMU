#!/bin/sh
# OpenCMU verify helpers. Sourced by install.sh.
#
# write_installed_hashes records the SHA-256 of every file the install left
# behind, so --verify can later detect drift: an external update, a service
# repair, or a manual edit that silently undid a tweak.
#
# do_verify is read-only: it compares the live files against that snapshot.

# write_installed_hashes -> called once, after the apply loop succeeds
write_installed_hashes() {
  _wh_out="$OPENCMU_STATE/installed.hashes.tmp"
  : > "$_wh_out"

  # Every backed-up file was patched; hash the live copy as the install left it.
  # backup_file stores each path with its leading slash stripped inside the
  # backup directory, so the live path is always "/" + the stored suffix.
  for _wh_bfile in $(find "$OPENCMU_BACKUP" -type f ! -name '.created' | sort); do
    _wh_rel=${_wh_bfile#"$OPENCMU_BACKUP"/}
    _wh_live="/$_wh_rel"
    [ -f "$_wh_live" ] || { warn "no live file for backup: $_wh_live"; continue; }
    printf '%s  %s\n' "$(sha256_file "$_wh_live")" "$_wh_live" >> "$_wh_out"
  done

  # Created files have no backup; hash them so their removal or change is caught.
  if [ -f "$OPENCMU_BACKUP/.created" ]; then
    while IFS= read -r _wh_cfile; do
      [ -n "$_wh_cfile" ] || continue
      [ -f "$_wh_cfile" ] || continue
      printf '%s  %s\n' "$(sha256_file "$_wh_cfile")" "$_wh_cfile" >> "$_wh_out"
    done < "$OPENCMU_BACKUP/.created"
  fi

  mv "$_wh_out" "$OPENCMU_STATE/installed.hashes"
  log "hashes: $OPENCMU_STATE/installed.hashes"
}

do_verify() {
  [ -f "$OPENCMU_STATE/receipt.env" ] || die "no receipt in $OPENCMU_STATE; nothing to verify"
  # shellcheck disable=SC1090,SC1091
  . "$OPENCMU_STATE/receipt.env"
  [ -f "$OPENCMU_STATE/installed.hashes" ] ||
    die "no hash snapshot in $OPENCMU_STATE (install predates --verify)"

  log "verifying install from ${INSTALLED_AT:-unknown} (firmware: ${FIRMWARE:-unknown})"

  intact=0
  drifted=0
  missing=0

  while IFS= read -r _v_line; do
    [ -n "$_v_line" ] || continue
    _v_hash=${_v_line%%  *}
    _v_path=${_v_line#*  }
    if [ ! -f "$_v_path" ]; then
      warn "MISSING: $_v_path (the install left it in place, file is gone)"
      missing=$((missing + 1))
      continue
    fi
    if [ "$(sha256_file "$_v_path")" = "$_v_hash" ]; then
      log "intact: $_v_path"
      intact=$((intact + 1))
    else
      warn "DRIFT: $_v_path (changed since the install)"
      drifted=$((drifted + 1))
    fi
  done < "$OPENCMU_STATE/installed.hashes"

  log "verify: $intact intact, $drifted drifted, $missing missing"

  [ "$drifted" -eq 0 ] && [ "$missing" -eq 0 ]
}
