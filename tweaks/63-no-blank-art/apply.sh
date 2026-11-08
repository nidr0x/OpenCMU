#!/bin/sh
# shellcheck disable=SC2154
# The literal is inserted between the two stock assignments in the
# "if (imagePath)" branch, which is why the anchor is the function header: the
# same assignment text also appears in other artwork helpers.
target="$OPENCMU_ROOT/jci/gui/common/controls/NowPlaying4/js/NowPlaying4Ctrl.js"

patch_line_after_once "$target" \
  'NowPlaying4Ctrl.prototype.setArtworkImagePath = function(imagePath)' \
  'this.properties.artworkImagePath = imagePath;' \
  'this.properties.artworkImagePath = imagePath;
        this._artworkImageFrame.className = "NowPlaying4CtrlArtworkImageDiv"; // opencmu:no-blank-art' \
  'opencmu:no-blank-art'
