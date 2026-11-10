#!/bin/sh
# shellcheck disable=SC2154
# Two inputs are required on purpose:
#   OPENCMU_WCP_RULES   iptables-save output for the WCP interface
#   OPENCMU_FW_ANCHOR   exact line that opens the firewall function in jci-fw.sh
# The anchor is not guessed because a wrong insertion runs at boot: the tweak
# aborts instead, leaving both files untouched.
target="$OPENCMU_ROOT/jci/scripts/jci-fw.sh"
rules="$OPENCMU_ROOT/jci/scripts/jci-fw-wcp.rules"

[ -f "$target" ] || die "missing $target"
[ -n "${OPENCMU_WCP_RULES:-}" ] || die "set OPENCMU_WCP_RULES to an iptables-save ruleset"
[ -n "${OPENCMU_FW_ANCHOR:-}" ] || die "set OPENCMU_FW_ANCHOR to the firewall function header"
[ -f "$OPENCMU_WCP_RULES" ] || die "rules file not found: $OPENCMU_WCP_RULES"

# Structure check before anything touches the unit.
grep -q '^\*filter' "$OPENCMU_WCP_RULES" || die "ruleset has no *filter table: $OPENCMU_WCP_RULES"
grep -q '^COMMIT' "$OPENCMU_WCP_RULES" || die "ruleset has no COMMIT: $OPENCMU_WCP_RULES"

# Parse the ruleset with the unit's own parser when it supports --test and the
# caller is root (iptables-restore --test needs CAP_NET_ADMIN even without
# rule application, so a non-root caller cannot use it). This only validates;
# it does not install anything.
if [ "$(id -u)" = 0 ] &&
   [ -x /usr/sbin/iptables-restore ] &&
   /usr/sbin/iptables-restore --help 2>&1 | grep -q -- '--test'; then
  /usr/sbin/iptables-restore --test < "$OPENCMU_WCP_RULES" ||
    die "ruleset rejected by iptables-restore --test"
  log "ruleset validated with iptables-restore --test"
else
  log "iptables-restore --test not available to this user; skipping parse check"
fi

record_created "$rules"
backup_file "$rules" >/dev/null || die "backup failed: $rules"
cp "$OPENCMU_WCP_RULES" "$rules.opencmu-new.$$" || die "copy failed: $rules"
atomic_write "$rules" "$rules.opencmu-new.$$"
rm -f "$rules.opencmu-new.$$"
log "installed WCP ruleset: $rules"

insert_after_once "$target" \
  'opencmu:firewall-iptables-restore' \
  "$OPENCMU_FW_ANCHOR" \
  "$dir/fastpath.sh"
