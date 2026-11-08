#!/bin/sh
# shellcheck disable=SC2154
# Which service is the off-board one depends on the market, so it is an input,
# not a guess. Empty means the tweak refuses to run.
[ -n "${OPENCMU_OFFBOARD_SERVICE:-}" ] ||
  die "set OPENCMU_OFFBOARD_SERVICE to the service to disable"

sm_disable_services "$OPENCMU_ROOT/jci/sm/sm.conf" "$OPENCMU_OFFBOARD_SERVICE"
