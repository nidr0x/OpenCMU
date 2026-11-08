#!/bin/sh
# shellcheck disable=SC2154
# The stock start_wifi.sh loads the WIFI modules from the start branch. Waiting
# for the interface before that point keeps the module load from racing the
# boot sequence. The anchor is the stock comment, not a line number.
insert_before_once \
  "$OPENCMU_ROOT/jci/scripts/start_wifi.sh" \
  'opencmu:earlier-wifi-init' \
  '# Load the WIFI modules' \
  "$dir/wait-wlan0.sh"
