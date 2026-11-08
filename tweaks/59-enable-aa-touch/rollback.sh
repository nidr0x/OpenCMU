#!/bin/sh
# shellcheck disable=SC2154
rollback_path "$OPENCMU_ROOT/etc/aap_system_attributes.xml"
rollback_path "$OPENCMU_ROOT/etc/aap_system_attributes_UCP.xml"
rollback_path "$OPENCMU_ROOT/jci/sm/sm.conf"
