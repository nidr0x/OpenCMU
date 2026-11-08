#!/bin/sh
# shellcheck disable=SC2154
# The dictionary file name carries a region suffix, so resolve it by content.
target=""
for f in "$OPENCMU_ROOT"/jci/gui/resources/js/backupparking/backupparkingAppDict_*.js; do
  [ -f "$f" ] || continue
  if grep -qF -- '"BUC-SafetyText"' "$f"; then
    target=$f
    break
  fi
done

[ -n "$target" ] || die "no backupparking dictionary with BUC-SafetyText found"

patch_quoted_value "$target" '"BUC-SafetyText"' ' '
