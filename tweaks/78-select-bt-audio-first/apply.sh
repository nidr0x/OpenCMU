#!/bin/sh
# shellcheck disable=SC2154
# One appended block at end of file: by the time it runs, the stock class has
# finished assigning its prototype methods, so the wrapper can capture the
# stock handler safely. The block re-checks everything it depends on and turns
# itself off when a shape it does not recognize shows up.
target="$OPENCMU_ROOT/jci/gui/apps/system/js/systemApp.js"
[ -f "$target" ] || die "systemApp.js not found: $target"

append_once "$target" 'opencmu:select-bt-audio-first' "$dir/impl.js"
log "select-bt-audio-first installed"
