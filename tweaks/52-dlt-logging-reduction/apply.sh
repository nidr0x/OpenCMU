#!/bin/sh
# shellcheck disable=SC2154
# Values only: the stock numbers differ between builds, so the keys are the
# anchor and the value is replaced in place.
target="$OPENCMU_ROOT/etc/dlt.conf"

patch_key_value "$target" 'SendMessageTime' '0'
patch_key_value "$target" 'SharedMemorySize' '1048576'
