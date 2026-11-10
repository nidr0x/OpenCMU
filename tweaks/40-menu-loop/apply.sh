#!/bin/sh
# shellcheck disable=SC2154
# The stock menu clamps the selection at both edges with a two-line block per
# edge (MainMenuCtrl.js, in the _offsetFocus body). Rewriting both edges as
# wraps over this._coins.length removes the hardcoded 5-item assumption: if a
# firmware build changes the coin count, the wrap follows it.
#
# The two stock literals below are unique in the stock file; any other result
# aborts before writing.
target="$OPENCMU_ROOT/jci/gui/apps/system/controls/MainMenu/js/MainMenuCtrl.js"

patch_subst "$target" \
  '        index = 0;' \
  '        index = this._coins.length - 1; // opencmu:menu-loop'

patch_subst "$target" \
  '    if (index > 4)' \
  '    if (index > this._coins.length - 1) // opencmu:menu-loop'
