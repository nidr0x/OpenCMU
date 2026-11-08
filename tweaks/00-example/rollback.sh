#!/bin/sh
# Example tweak rollback: restore the previous marker, or remove ours.
# Sourced by rollback_tweak with OPENCMU_BACKUP pointing at the receipt backup.

rollback_path "$OPENCMU_ROOT/data/opencmu/example-marker.txt"
