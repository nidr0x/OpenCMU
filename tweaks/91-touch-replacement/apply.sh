#!/bin/sh
# shellcheck disable=SC2154,SC1090
# Template tweak. It does not contain a firmware patch.
# The user must extract the stock file, patch it themselves, and describe it
# in tweak.local.env:
#
#   TARGET_FILE=/path/on/the/unit
#   REPLACEMENT_FILE=/path/on/the/usb/to/patched-file
#   EXPECTED_SHA256=<hash of the stock TARGET_FILE>
#
# See docs/tweaks.md.

local_env="$dir/tweak.local.env"
[ -f "$local_env" ] || die "missing $local_env; see docs/tweaks.md"
. "$local_env"

[ -n "${TARGET_FILE:-}" ] || die "tweak.local.env must set TARGET_FILE"
[ -n "${REPLACEMENT_FILE:-}" ] || die "tweak.local.env must set REPLACEMENT_FILE"

install_replacement "$TARGET_FILE" "$REPLACEMENT_FILE" "${EXPECTED_SHA256:-}"
log "replaced $TARGET_FILE"
