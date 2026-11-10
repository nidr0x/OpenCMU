#!/bin/sh
# shellcheck disable=SC2154
# On 74.00.324 the "Powered by Gracenote" detail line is drawn by the USB audio
# app, not by the shared NowPlaying4 control: the call lives in usbaudioApp.js
# (three sites, lines ~4298, ~6116 and ~6441 in the stock file). Blank all
# three; no call site may be left behind.
target="$OPENCMU_ROOT/jci/gui/apps/usbaudio/js/usbaudioApp.js"

patch_subst_all "$target" \
  'setDetailLine3({detailTextId: "Gracenote"});' \
  'setDetailLine3({detailTextId: ""});' \
  3
