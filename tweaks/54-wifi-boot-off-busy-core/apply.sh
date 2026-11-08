#!/bin/sh
# shellcheck disable=SC2154
# start_wifi loads the modules and brings the interface up; NMS_svc and
# blm_nms_svc do the network management around it. Pinning all three keeps the
# whole bring-up on the second core.
sm_set_affinity "$OPENCMU_ROOT/jci/sm/sm.conf" 0x02 \
  start_wifi \
  NMS_svc \
  blm_nms_svc
