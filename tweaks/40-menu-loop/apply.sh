#!/bin/sh
# shellcheck disable=SC2154
# The stock menu clamps the selection at both edges. Turning each clamp into a
# wrap is a one-line change per edge.
target="$OPENCMU_ROOT/jci/gui/apps/system/controls/MainMenu/js/MainMenuCtrl.js"

patch_subst "$target" \
  'if (index < 0)index = 0;' \
  'index = 4; // opencmu:menu-loop'

patch_subst "$target" \
  'if (index > 4)index = 4;' \
  'index = 0; // opencmu:menu-loop'
