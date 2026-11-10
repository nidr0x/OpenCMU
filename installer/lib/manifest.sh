#!/bin/sh
# shellcheck disable=SC1091
# OpenCMU manifest and firmware helpers. Sourced by install.sh.

load_manifest() {
  [ -f "$OPENCMU_USB/manifest.env" ] || die "manifest.env missing"
  . "$OPENCMU_USB/manifest.env"

  [ "${MANIFEST_SCHEMA:-}" = "1" ] || die "unsupported manifest schema: ${MANIFEST_SCHEMA:-none}"
  [ -n "${PROJECT_NAME:-}" ] || die "manifest missing PROJECT_NAME"
  [ -n "${PROJECT_VERSION:-}" ] || die "manifest missing PROJECT_VERSION"
  [ -n "${FIRMWARE_MIN:-}" ] || die "manifest missing FIRMWARE_MIN"
  [ -n "${FIRMWARE_MAX:-}" ] || die "manifest missing FIRMWARE_MAX"
  [ -n "${DEFAULT_TWEAKS:-}" ] || die "manifest missing DEFAULT_TWEAKS"
}

check_firmware() {
  vi="$OPENCMU_ROOT/jci/version.ini"

  if [ ! -f "$vi" ]; then
    if [ "$OPENCMU_FORCE" -eq 1 ]; then
      warn "missing $vi; continuing because --force was passed"
      ver="unknown"
      return 0
    fi
    die "missing $vi (use --force only on a bench root)"
  fi

  ver=$(awk -F= '/^[[:space:]]*JCI_SW_VER[[:space:]]*=/ {
    v = $2
    gsub(/[[:space:]"]/, "", v)
    # Stock 74.00.324 ships JCI_SW_VER="MAZ_CMU-150_74.00.324". Versions are
    # compared on the numeric part only: drop everything up to the last "_",
    # which leaves bare versions such as 74.00.324 untouched.
    sub(/^.*_/, "", v)
    print v
    exit
  }' "$vi")

  [ -n "$ver" ] || die "JCI_SW_VER not found in $vi"
  log "firmware: $ver (allowed: $FIRMWARE_MIN .. $FIRMWARE_MAX)"

  version_ge "$ver" "$FIRMWARE_MIN" || die "firmware $ver is older than $FIRMWARE_MIN"
  version_le "$ver" "$FIRMWARE_MAX" || die "firmware $ver is newer than $FIRMWARE_MAX"
}
