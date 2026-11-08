#!/bin/sh
# shellcheck disable=SC2154
target="$OPENCMU_ROOT/jci/gui/common/controls/NowPlaying4/css/NowPlaying4Ctrl.css"

append_once "$target" "opencmu:bigger-album-art" "$dir/override.css"
