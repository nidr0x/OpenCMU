#!/bin/sh
# shellcheck disable=SC2154
target="$OPENCMU_ROOT/data/opencmu/boot.d/61-cluster-compass.sh"
# Stop a runtime that is already up before removing its boot entry. On a
# mounted image there is nothing to stop, so only do it on the live root.
if [ "${OPENCMU_ROOT%/}" = "" ] && [ -x "$target" ]; then
    "$target" --stop >/dev/null 2>&1 || true
fi
rollback_path "$target"
