#!/bin/sh
# shellcheck disable=SC2154
target="$OPENCMU_ROOT/jci/gui/common/controls/NowPlaying4/js/NowPlaying4Ctrl.js"

patch_subst "$target" \
  'setDetailLine3({detailTextId: "Gracenote"});' \
  'setDetailLine3({detailTextId: ""});'
