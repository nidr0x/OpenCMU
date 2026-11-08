#!/bin/sh
# shellcheck disable=SC2154,SC1090
# Restore TARGET_FILE from the backup taken by apply.sh.
# Safe no-op when the tweak never ran (no tweak.local.env).

local_env="$dir/tweak.local.env"
if [ ! -f "$local_env" ]; then
  warn "no tweak.local.env; nothing to roll back for this tweak"
  return 0
fi
. "$local_env"

if [ -z "${TARGET_FILE:-}" ]; then
  warn "tweak.local.env has no TARGET_FILE; nothing to roll back"
  return 0
fi

rollback_path "$TARGET_FILE"
