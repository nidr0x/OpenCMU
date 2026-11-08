#!/bin/sh
# shellcheck disable=SC2154
# Order matters: if the stage rewiring does not match, nothing else runs.
target="$OPENCMU_ROOT/jci/sm/sm.conf"

patch_subst_all "$target" \
  'value="blm_ira_aha"' \
  'value="stage_ir"' \
  3

sm_disable_services "$target" blm_ira_aha
