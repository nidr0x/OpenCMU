#!/bin/sh
# shellcheck disable=SC2154
# One self-contained expression instead of an inserted variable, so the patch
# cannot land outside the scope that owns msg.
#
# USB audio only: its notification payload carries artist and title
# (usbaudioApp.js, the USB track-info SBN). The Bluetooth app builds its
# notification from a payload that only has the precombined titleInfo string
# (btaudioApp.js, _Sbn_ObjectInfoMsgHandler), so artist and title cannot be
# reconstructed there without guessing. BT is deliberately left untouched.
expr='((msg.params.payload.artist && msg.params.payload.title) ? (msg.params.payload.artist + " - " + msg.params.payload.title) : msg.params.payload.title),'

patch_subst "$OPENCMU_ROOT/jci/gui/apps/usbaudio/js/usbaudioApp.js" \
  'text2 : msg.params.payload.title,' \
  "text2 : $expr"
