#!/bin/sh
# shellcheck disable=SC2154
target="$OPENCMU_ROOT/data/opencmu/boot.d/62-disable-touchscreen.sh"
# Send SpeedRestriction(0) only on a live root. On a mounted image there is no
# running bus, so removing the boot entry is the whole rollback.
if [ "${OPENCMU_ROOT%/}" = "" ] && [ -x "$target" ]; then
    "$target" --release >/dev/null 2>&1 || true
fi
rollback_path "$target"
