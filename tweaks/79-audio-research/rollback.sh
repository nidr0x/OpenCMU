#!/bin/sh
# shellcheck disable=SC2154
# Like the profiler this runtime is bounded by its own window and exits by
# itself, so removing the boot entry is the whole rollback. A run in flight
# finishes its window and never outlives it.
rollback_path "$OPENCMU_ROOT/data/opencmu/boot.d/79-audio-research.sh"
