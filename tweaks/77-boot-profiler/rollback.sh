#!/bin/sh
# shellcheck disable=SC2154
# The profiler is one-shot: it exits by itself, so removing the boot entry is
# the whole rollback. A run in flight finishes its current window bounded by
# OPENCMU_PROFILER_WINDOW and never spins past it.
rollback_path "$OPENCMU_ROOT/data/opencmu/boot.d/77-boot-profiler.sh"
