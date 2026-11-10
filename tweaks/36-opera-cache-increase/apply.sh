#!/bin/sh
# shellcheck disable=SC2154
# Stock 74.00.324 ships the Opera disk cache disabled ([Disk Cache] Enabled=0)
# and tiny (Size=2000 KB), so every redraw re-reads images from the unit.
# Enable it and raise the size. The memory cache ([Cache] Figure/Document) is
# left alone on purpose: raising it trades RAM the UI needs.
target="$OPENCMU_ROOT/jci/opera/opera_home/opera.ini"

patch_line_after_once "$target" '[Disk Cache]' 'Enabled=0' 'Enabled=1'
patch_number "$target" 'Size=2000' '2000' '8000'
