#!/bin/sh
# shellcheck disable=SC2154
# Stock 74.00.324 binds the disclaimer to the template's displayedFunction
# (systemApp.js:337); "readyFunction" is not used for it. Point that binding at
# our handler, then define it just before the stock handler so the file keeps
# its original order.
#
# Both steps abort if their anchor is missing or ambiguous; nothing is written
# on a mismatch.

target="$OPENCMU_ROOT/jci/gui/apps/system/js/systemApp.js"

patch_subst "$target" \
  '"displayedFunction" : this._displayedDisclaimer.bind(this),' \
  '"displayedFunction" : this._noMoreDisclaimer.bind(this),'

insert_before_once "$target" \
  "opencmu:no-disclaimer" \
  'systemApp.prototype._displayedDisclaimer = function' \
  "$dir/impl.js"
