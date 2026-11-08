#!/bin/sh
# OpenCMU read-only stock collector.
#
# Copies a whitelist of stock firmware files from the unit to the USB so that a
# tweak can be written against the real files instead of a guess.
#
# Guarantees:
#   - it only reads from the CMU,
#   - it only writes under OUT/opencmu-dump,
#   - it never mounts, remounts, deletes, or executes anything from the CMU,
#   - it records a SHA-256 for every file it copies, and a MISSING line for
#     every path in the whitelist that the unit does not have.
#
# Usage: collect.sh [USB_ROOT]
#   USB_ROOT defaults to the first mounted volume carrying .opencmu-collect.
#
# Testing: set OPENCMU_COLLECT_ROOT to a fake root prefix.

set -eu

SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
R=${OPENCMU_COLLECT_ROOT:-}

OUT=${1:-}
if [ -z "$OUT" ]; then
  S=${HOME%root}
  for d in sda1 sdb1 sdc1 sdd1; do
    U=${S}tmp${S}mnt${S}$d
    if [ -f "$U/.opencmu-collect" ]; then
      OUT=$U
      break
    fi
  done
fi

[ -n "$OUT" ] || { echo "collect: USB not found (no .opencmu-collect marker)" >&2; exit 1; }
[ -f "$OUT/.opencmu-collect" ] || { echo "collect: marker missing in $OUT" >&2; exit 1; }

DST="$OUT/opencmu-dump"
FILES=${OPENCMU_COLLECT_FILES:-$SELF_DIR/files.txt}
[ -f "$FILES" ] || { echo "collect: files.txt missing next to collect.sh" >&2; exit 1; }

mkdir -p "$DST/files"
LOG="$DST/collect.log"
: > "$LOG"

say() { printf '%s\n' "$*" | tee -a "$LOG"; }

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  elif command -v md5sum >/dev/null 2>&1; then
    printf 'md5:%s\n' "$(md5sum "$1" | awk '{print $1}')"
  else
    echo "unavailable"
  fi
}

say "OpenCMU stock collector"
say "root: $R/"
say "started: $(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
say ""

{
  echo "uname"
  uname -a 2>/dev/null || echo "unavailable"
  echo
  echo "version.ini"
  cat "$R/jci/version.ini" 2>/dev/null || echo "unavailable"
} > "$DST/system.txt"

if [ -d "$R/jci" ]; then
  if [ -n "$R" ]; then
    find "$R/jci" -type f 2>/dev/null | sed "s|^$R||" | LC_ALL=C sort > "$DST/listing-jci.txt"
  else
    find /jci -type f 2>/dev/null | LC_ALL=C sort > "$DST/listing-jci.txt"
  fi
else
  echo "no /jci directory" > "$DST/listing-jci.txt"
fi

MANIFEST="$DST/manifest.txt"
: > "$MANIFEST"
FOUND=0
MISSING=0

while IFS= read -r pattern || [ -n "$pattern" ]; do
  case "$pattern" in
    ''|'#'*) continue ;;
  esac

  matched=0
  for f in $R$pattern; do
    [ -f "$f" ] || continue
    matched=1
    rel=${f#"$R"}
    case "$rel" in
      /*) : ;;
      *) rel="/$rel" ;;
    esac
    dest="$DST/files/${rel#/}"
    mkdir -p "$(dirname "$dest")"
    if cp -p "$f" "$dest" 2>/dev/null; then
      printf '%s  %s  %s\n' "$(hash_file "$dest")" "$(wc -c < "$dest" | tr -d ' ')" "$rel" >> "$MANIFEST"
      FOUND=$((FOUND + 1))
    else
      printf '%s  %s\n' "UNREADABLE" "$rel" >> "$MANIFEST"
    fi
  done

  if [ "$matched" -eq 0 ]; then
    printf '%s  %s\n' "MISSING" "$pattern" >> "$MANIFEST"
    MISSING=$((MISSING + 1))
  fi
done < "$FILES"

say "collected: $FOUND"
say "missing:   $MISSING"
say "output:    $DST"
say ""

# Written last so its presence means the run reached the end.
printf 'done %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" > "$DST/DONE"

sync 2>/dev/null || : 

exit 0
