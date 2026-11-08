#!/bin/sh
# shellcheck disable=SC2154
target="$OPENCMU_ROOT/jci/opera/opera_home/opera.ini"

patch_number "$target" 'Figure Cache Size' '8000' '16000'
patch_number "$target" 'Document Cache Size' '1000' '4000'
