#!/bin/sh
# shellcheck disable=SC2154
# The daemon is deliberately left alone: an operator may still be connected.
rollback_path "$OPENCMU_ROOT/etc/ssh/sshd_config"
rollback_path "$OPENCMU_ROOT/data/opencmu/ssh/authorized_keys"
