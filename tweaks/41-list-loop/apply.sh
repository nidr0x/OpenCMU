#!/bin/sh
# shellcheck disable=SC2154
# Appended wrapper. It only intercepts the edge case and hands everything else
# to the stock handler, so a list that already loops is left as it is.
append_once \
  "$OPENCMU_ROOT/jci/gui/common/controls/List2/js/List2Ctrl.js" \
  'opencmu:list-loop' \
  "$dir/impl.js"
