#!/bin/sh
# shellcheck disable=SC2154
target="$OPENCMU_ROOT/jci/gui/common/controls/Ump3/css/Ump3Ctrl.css"

append_once "$target" "opencmu:usb-audio-mod" "$dir/override.css"
