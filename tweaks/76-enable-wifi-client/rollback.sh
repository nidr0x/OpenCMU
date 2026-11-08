#!/bin/sh
# shellcheck disable=SC2154
target="$OPENCMU_ROOT/data/opencmu/boot.d/76-wifi-client.sh"
if [ "${OPENCMU_ROOT%/}" = "" ] && [ -x "$target" ]; then
    "$target" --stop >/dev/null 2>&1 || true
fi
rollback_path "$target"
rollback_path "$OPENCMU_ROOT/data/opencmu/config/wifi-client.conf"
rollback_path "$OPENCMU_ROOT/data/opencmu/wifi/wpa_supplicant.conf"
