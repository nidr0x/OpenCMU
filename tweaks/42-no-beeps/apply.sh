#!/bin/sh
# shellcheck disable=SC2154
# Rename the stock implementation first, so the stub inserted below is the one
# the rest of the UI resolves.
target="$OPENCMU_ROOT/jci/gui/common/js/Common.js"

patch_subst "$target" \
  'Common.prototype.beep = function(pressType, eventCause)' \
  'Common.prototype.beep_stock = function(pressType, eventCause)'

insert_before_once "$target" \
  'opencmu:no-beeps' \
  'Common.prototype.beep_stock = function' \
  "$dir/impl.js"
