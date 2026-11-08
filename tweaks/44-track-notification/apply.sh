#!/bin/sh
# shellcheck disable=SC2154
# One self-contained expression instead of an inserted variable, so the patch
# cannot land outside the scope that owns msg.
expr='((msg.params.payload.artist && msg.params.payload.title) ? (msg.params.payload.artist + " - " + msg.params.payload.title) : msg.params.payload.title),'

for app in usbaudio btaudio; do
  patch_subst "$OPENCMU_ROOT/jci/gui/apps/$app/js/${app}App.js" \
    'text2 : msg.params.payload.title,' \
    "text2 : $expr"
done
