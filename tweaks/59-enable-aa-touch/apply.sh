#!/bin/sh
# shellcheck disable=SC2154
# The XML alone does nothing without the shim: it points Android Auto at
# /dev/input/aa-touchscreen, a node the shim creates. So the shim must already
# be installed (tweak 58 in the same run, or a previous one).
shim="$OPENCMU_ROOT/data_persist/oem-aa-mod/libpatch-blmjciaapa.so"
[ -f "$shim" ] || die "shim missing: run 58-install-aatouch first"

sm="$OPENCMU_ROOT/jci/sm/sm.conf"

insert_after_once "$OPENCMU_ROOT/etc/aap_system_attributes.xml" \
  'opencmu:aa-touch' \
  '</input_devices>' \
  "$dir/touch-primary.xml"

insert_after_once "$OPENCMU_ROOT/etc/aap_system_attributes_UCP.xml" \
  'opencmu:aa-touch' \
  '</input_devices>' \
  "$dir/touch-secondary.xml"

# reset_board="no" keeps a crashing shim from resetting the whole unit: at most
# Android Auto drops out until the next start.
sm_set_attribute "$sm" reset_board no jciAAPA

sm_add_child "$sm" jciAAPA \
  '<environ_var env_name="LD_PRELOAD" env_value="/data_persist/oem-aa-mod/libpatch-blmjciaapa.so"/>'
