#!/bin/sh
# shellcheck disable=SC2154
# Each service is a <service name="..."> block with an autorun attribute.
# Names this firmware does not define are reported and skipped.
sm_disable_services "$OPENCMU_ROOT/jci/sm/sm.conf" \
  blm_ira_stitcher
