#!/bin/sh
# Full apply/rollback sweep against a stock rootfs, one tweak at a time.
#
# This is the opt-in, repo-shipped version of the bench sweep: it needs a
# pristine copy of the 74.00.324 rootfs (no .up unpacking happens here), so it
# only runs when OPENCMU_STOCK_ROOT points at one:
#
#   OPENCMU_STOCK_ROOT=/path/to/rootfs sh tests/stock-sweep.sh
#
# For every tweak it runs a single-tweak apply, records the result, rolls
# back, and then verifies the rollback byte-for-byte: every file the install
# backed up must compare equal to its live copy again, and every file the
# install created must be gone. A final full-tree manifest compares the whole
# rootfs against the state before the sweep.
#
# Tweaks whose external inputs are absent are skipped, not failed: the AGPL
# Android Auto shim (58/59) is never bundled, 75 needs a public key, 57 needs
# an iptables-save capture, and 90/91 need their tweak.local.env. Documented
# inputs get defaults (OPENCMU_AUDIO_ORDER, OPENCMU_OFFBOARD_SERVICE).
#
# 61/62/76/77 write into /data/opencmu/boot.d, so they are applied together
# with 60-startup-hook in the same run and rolled back as one.

set -u

ROOT=${OPENCMU_STOCK_ROOT:-}
if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
  echo "stock-sweep: set OPENCMU_STOCK_ROOT to a stock rootfs" >&2
  exit 2
fi

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
USB=$(CDPATH='' cd -- "$HERE/.." && pwd)
INST="$USB/installer/install.sh"

OUTDIR=${OPENCMU_SWEEP_OUT:-${TMPDIR:-/tmp}/opencmu-sweep.$$}
rm -rf "$OUTDIR"
mkdir -p "$OUTDIR"

# Documented defaults; anything already in the environment wins.
: "${OPENCMU_AUDIO_ORDER:=BTAudio,USB_A}"
: "${OPENCMU_OFFBOARD_SERVICE:=offboard_service}"
# 60 targets stage_gap2.sh by default; the value must be root-relative.
unset OPENCMU_HOOK_STAGE
export OPENCMU_AUDIO_ORDER OPENCMU_OFFBOARD_SERVICE

FAILED=0
SKIPPED=0
PASSED=0

report() {
  printf '%s\n' "$1"
}

# is_skippable ID -> prints the reason, or returns 1 when it should run.
is_skippable() {
  id=$1
  case $id in
    58-install-aatouch)
      [ -n "${OPENCMU_AATOUCH_SHIM:-}" ] || {
        echo "external AGPL shim (set OPENCMU_AATOUCH_SHIM to include it)"
        return 0
      }
      ;;
    59-enable-aa-touch)
      echo "needs 58 (external AGPL shim)"
      return 0
      ;;
    57-firewall-iptables-restore)
      [ -n "${OPENCMU_WCP_RULES:-}" ] || {
        echo "needs OPENCMU_WCP_RULES (iptables-save capture)"
        return 0
      }
      ;;
    76-enable-wifi-client)
      [ -n "${OPENCMU_WIFI_SSID:-}" ] || {
        echo "needs OPENCMU_WIFI_SSID and friends"
        return 0
      }
      ;;
    75-enable-ssh)
      [ -n "${OPENCMU_SSH_PUBKEY:-}" ] && [ -f "${OPENCMU_SSH_PUBKEY:-}" ] || {
        echo "needs OPENCMU_SSH_PUBKEY"
        return 0
      }
      ;;
    90-* | 91-*)
      [ -f "$USB/tweaks/$id/tweak.local.env" ] || {
        echo "needs tweaks/$id/tweak.local.env"
        return 0
      }
      ;;
  esac
  return 1
}

# verify_rollback -> 0 when the tree is back to the pre-apply state.
verify_rollback() {
  rc=0
  # Every backed-up file must equal its live copy again. backup_file stores
  # each path with its leading slash stripped inside the backup directory, so
  # the live path is the stored suffix with a leading slash added back.
  find "$ROOT/data/opencmu/backups" -type f ! -name '.created' \
    > "$OUTDIR/.backup-files" || return 1
  while IFS= read -r bfile; do
    # shellcheck disable=SC2295  # the unquoted expansion is the intended glob-free strip
    rel=${bfile#$ROOT/data/opencmu/backups/}
    rel=${rel#*/}
    live="/$rel"
    if [ ! -f "$live" ]; then
      report "  rollback: live file gone: $live"
      rc=1
      continue
    fi
    cmp -s "$bfile" "$live" || {
      report "  rollback: differs from backup: /$rel"
      rc=1
    }
  done < "$OUTDIR/.backup-files"
  # Files the run created must be gone.
  for cdir in "$ROOT/data/opencmu/backups"/*/; do
    [ -f "$cdir/.created" ] || continue
    while IFS= read -r cfile; do
      [ -n "$cfile" ] || continue
      if [ -e "$cfile" ]; then
        report "  rollback: created file still present: $cfile"
        rc=1
      fi
    done < "$cdir/.created"
  done
  return $rc
}

# Manifest of the whole tree, for the end-of-sweep comparison.
# sha256sum and shasum -a 256 both print "<hash>  <path>".
tree_manifest() {
  if command -v sha256sum >/dev/null 2>&1; then
    find "$ROOT" -type f -exec sha256sum {} + 2>/dev/null | sort
  else
    find "$ROOT" -type f -exec shasum -a 256 {} + 2>/dev/null | sort
  fi
}

tree_manifest > "$OUTDIR/manifest.before"

for d in "$USB"/tweaks/*/; do
  id=$(basename "$d")
  reason=""
  if reason=$(is_skippable "$id"); then
    report "SKIP $id :: $reason"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # boot.d tweaks need 60-startup-hook in the same run.
  case $id in
    61-* | 62-* | 76-* | 77-*) plan="60-startup-hook $id" ;;
    *) plan="$id" ;;
  esac

  sh "$INST" --usb "$USB" --root "$ROOT" --apply --experimental \
    --tweaks "$plan" > "$OUTDIR/$id.log" 2>&1
  rc=$?
  if [ $rc -eq 0 ]; then
    PASSED=$((PASSED + 1))
    report "OK   $id"
  else
    FAILED=$((FAILED + 1))
    report "FAIL $id :: $(grep -m1 'ERROR' "$OUTDIR/$id.log" || echo "exit $rc")"
  fi

  sh "$INST" --usb "$USB" --root "$ROOT" --apply --rollback \
    > "$OUTDIR/$id.rollback.log" 2>&1 || {
    FAILED=$((FAILED + 1))
    report "FAIL $id :: rollback itself failed"
    continue
  }
  if ! verify_rollback; then
    FAILED=$((FAILED + 1))
    report "FAIL $id :: rollback left the tree dirty"
  fi
done

# The backup directories are kept by design; remove the state tree before
# comparing the whole rootfs, so only stock files count.
rm -rf "$ROOT/data/opencmu"
tree_manifest > "$OUTDIR/manifest.after"
if cmp -s "$OUTDIR/manifest.before" "$OUTDIR/manifest.after"; then
  report "TREE byte-identical after the whole sweep"
else
  FAILED=$((FAILED + 1))
  report "FAIL tree changed after the whole sweep (see $OUTDIR manifests)"
fi
report "stock-sweep: $PASSED passed, $SKIPPED skipped, $FAILED failed; logs in $OUTDIR"
[ "$FAILED" -eq 0 ]
