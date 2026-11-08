#!/bin/sh
# Verify a built USB payload against its SHA256SUMS.
# Usage: verify-usb.sh [DIR]
set -eu

DIR=${1:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)/dist/opencmu-usb}
[ -f "$DIR/SHA256SUMS" ] || { echo "SHA256SUMS not found in $DIR" >&2; exit 1; }

cd "$DIR"
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum -c SHA256SUMS
else
  shasum -a 256 -c SHA256SUMS
fi

LIST=$(mktemp "${TMPDIR:-/tmp}/opencmu-verify.XXXXXX")
trap 'rm -f "$LIST" "$LIST.expected"' EXIT INT TERM

find . -type f ! -name SHA256SUMS | sed 's|^\./||' | LC_ALL=C sort > "$LIST"
sed 's/^[0-9a-f]\{64\}  //' SHA256SUMS | LC_ALL=C sort > "$LIST.expected"

if ! diff "$LIST.expected" "$LIST"; then
  echo "payload has files that are not listed in SHA256SUMS (or the reverse)" >&2
  exit 1
fi
