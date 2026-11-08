#!/bin/sh
# shellcheck disable=SC2154
append_once \
  "$OPENCMU_ROOT/jci/gui/apps/carplay/js/carplayApp.js" \
  'opencmu:carplay-autoforeground' \
  "$dir/impl.js"
