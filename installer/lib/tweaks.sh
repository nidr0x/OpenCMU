#!/bin/sh
# shellcheck disable=SC1091
# OpenCMU tweak helpers. Sourced by install.sh.

list_tweaks() {
  for dir in "$OPENCMU_USB"/tweaks/*/; do
    [ -f "$dir/tweak.env" ] || continue
    id=$(basename "$dir")
    (
      . "$dir/tweak.env"
      printf '%s\t%s\t%s\t%s\n' \
        "$id" "${TWEAK_RISK:-unknown}" "${TWEAK_EXPERIMENTAL:-0}" "${TWEAK_NAME:-$id}"
    )
  done
}

valid_tweak_id() {
  case "$1" in
    ''|.|..|*[!A-Za-z0-9._-]*) return 1 ;;
  esac
  return 0
}

preflight_tweak() {
  id=$1
  valid_tweak_id "$id" || die "invalid tweak id: $id"
  dir="$OPENCMU_USB/tweaks/$id"
  [ -f "$dir/tweak.env" ] || die "unknown tweak: $id"
  [ -f "$dir/apply.sh" ] || die "tweak has no apply.sh: $id"

  . "$dir/tweak.env"

  if [ "${TWEAK_EXPERIMENTAL:-0}" = "1" ] && [ "${OPENCMU_ENABLE_EXPERIMENTAL:-0}" != "1" ]; then
    die "experimental tweak requires --experimental: $id"
  fi
}

apply_tweak() {
  id=$1
  valid_tweak_id "$id" || die "invalid tweak id: $id"
  dir="$OPENCMU_USB/tweaks/$id"
  [ -f "$dir/tweak.env" ] || die "unknown tweak: $id"
  [ -f "$dir/apply.sh" ] || die "tweak has no apply.sh: $id"

  . "$dir/tweak.env"

  if [ "${TWEAK_EXPERIMENTAL:-0}" = "1" ] && [ "${OPENCMU_ENABLE_EXPERIMENTAL:-0}" != "1" ]; then
    if [ "$OPENCMU_DRY_RUN" -eq 1 ]; then
      warn "experimental tweak skipped without --experimental: $id"
      return 0
    fi
    die "experimental tweak requires --experimental: $id"
  fi

  if [ "$OPENCMU_DRY_RUN" -eq 1 ]; then
    log "would apply: $id - ${TWEAK_NAME:-$id}"
    return 0
  fi

  log "applying: $id - ${TWEAK_NAME:-$id}"
  printf '%s\n' "$id" >> "$OPENCMU_STATE/installed.list"
  ( set -eu; . "$dir/apply.sh" ) || die "tweak failed: $id (recorded for rollback)"
}

rollback_tweak() {
  id=$1
  valid_tweak_id "$id" || die "invalid tweak id: $id"
  dir="$OPENCMU_USB/tweaks/$id"

  [ -d "$dir" ] || die "tweak not present in payload: $id (keep the original USB)"
  [ -f "$dir/rollback.sh" ] || die "no rollback.sh for tweak: $id"

  log "rolling back: $id"
  ( set -eu; . "$dir/rollback.sh" ) || die "rollback failed: $id"
}
