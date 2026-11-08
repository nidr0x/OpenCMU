#!/bin/sh
# shellcheck disable=SC2154
stage="${OPENCMU_HOOK_STAGE:-jci/scripts/stage_gap2.sh}"
rollback_path "$OPENCMU_ROOT/$stage"
rollback_path "$OPENCMU_ROOT/data/opencmu/boot.d/README.txt"
