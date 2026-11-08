#!/bin/sh
# shellcheck disable=SC2154
# The stock UI binds _AtSpeedMsgHandler on startup; that handler is what marks
# the session as "at speed" and gates touch input. Dropping the binding leaves
# the gate closed. NVRAM speed limits are deliberately untouched.
target="$OPENCMU_ROOT/jci/gui/common/js/Common.js"

patch_subst "$target" \
  '        "Global.AtSpeed" : this._AtSpeedMsgHandler.bind(this),' \
  '        // opencmu:touch-while-driving'
