#!/bin/sh
# shellcheck disable=SC2154
# The animation is a normal Service Manager entry (type=process, ready_flag=
# /var/run/tranlogo_ready_flag, exit_allowed=yes). Disabling the service is the
# reversible way to skip it.
sm_disable_services "$OPENCMU_ROOT/jci/sm/sm.conf" tranlogo
