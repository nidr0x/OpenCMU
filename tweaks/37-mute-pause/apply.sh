#!/bin/sh
# shellcheck disable=SC2154
target="$OPENCMU_ROOT/jci/vim/JCI_KEY_CONFIG.xml"

patch_subst "$target" \
  'codeSW1Button6="JCI_KEY_MUTE"' \
  'codeSW1Button6="JCI_KEY_PLAYPAUSE"'
