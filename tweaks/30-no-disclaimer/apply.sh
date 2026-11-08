#!/bin/sh
# shellcheck disable=SC2154
# Point the Disclaimer template at our own handler, then define it just before
# the stock handler so the file keeps its original order.
#
# Both steps abort if their anchor is missing or ambiguous; nothing is written
# on a mismatch.

target="$OPENCMU_ROOT/jci/gui/apps/system/js/systemApp.js"

patch_subst "$target" \
  '"readyFunction" : this._displayedDisclaimer.bind(this),' \
  '"readyFunction" : this._noMoreDisclaimer.bind(this),'

insert_before_once "$target" \
  "opencmu:no-disclaimer" \
  'systemApp.prototype._displayedDisclaimer = function' \
  "$dir/impl.js"
