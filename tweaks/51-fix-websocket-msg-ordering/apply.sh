#!/bin/sh
# shellcheck disable=SC2154
# The rest of the file calls this._isStack(...) and this._delStack(...), but the
# stock build declares them as bare functions. Attaching them to the prototype
# fixes the ordering of the messages the framework keeps in its stacks.
target="$OPENCMU_ROOT/jci/gui/framework/js/Websockets.js"

patch_subst "$target" \
  'function _isStack(' \
  'Websockets.prototype._isStack = function('

patch_subst "$target" \
  'function _delStack(' \
  'Websockets.prototype._delStack = function('
