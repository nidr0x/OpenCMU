#!/bin/sh
# shellcheck disable=SC2154
# Four values, each on its own keyed line. Every one is required: a missing
# key means the firmware layout is not the one this tweak was written for.
target="$OPENCMU_ROOT/jci/gui/common/controls/List2/js/List2Ctrl.js"

patch_number "$target" 'autoscrollTier1Timeout' '1500' '150'
patch_number "$target" 'autoscrollTier2Timeout' '5000' '300'
patch_number "$target" 'autoscrollTier1Interval' '500' '200'
patch_number "$target" 'autoscrollTier2Interval' '1000' '300'
