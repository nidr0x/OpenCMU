#!/bin/sh
# Build the OpenCMU USB payload in dist/opencmu-usb.
# Usage: build-usb.sh [DEST]
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
DIST=${1:-$ROOT_DIR/dist/opencmu-usb}

[ -f "$ROOT_DIR/manifest.env" ] || { echo "manifest.env missing in $ROOT_DIR" >&2; exit 1; }

case "$DIST" in
  ''|/|.|..) echo "refusing to remove destination: '$DIST'" >&2; exit 1 ;;
esac
[ "$DIST" != "$ROOT_DIR" ] || { echo "refusing to remove the source tree" >&2; exit 1; }
case "$ROOT_DIR/" in
  "$DIST"/*) echo "refusing to remove a parent of the source tree: $DIST" >&2; exit 1 ;;
esac

rm -rf "$DIST"
mkdir -p "$DIST/lib"

cp "$ROOT_DIR/manifest.env" "$DIST/manifest.env"
cp "$ROOT_DIR/installer/install.sh" "$DIST/install.sh"
cp "$ROOT_DIR/installer/bootstrap.sh" "$DIST/bootstrap.sh"
cp "$ROOT_DIR"/installer/lib/*.sh "$DIST/lib/"
cp -R "$ROOT_DIR/tweaks" "$DIST/tweaks"
cp -R "$ROOT_DIR/app" "$DIST/app"

# Never ship per-user tweak configuration.
find "$DIST/tweaks" -name tweak.local.env -delete

# The updater looks for this marker on the USB root.
: > "$DIST/jci-autoupdate"

chmod +x "$DIST/install.sh" "$DIST/bootstrap.sh"

# Seed the dashboard with a sample state so it renders before an install.
cp "$ROOT_DIR/app/state.example.json" "$DIST/app/state.json"

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

LIST=$(mktemp "${TMPDIR:-/tmp}/opencmu-sums.XXXXXX")
trap 'rm -f "$LIST"' EXIT INT TERM

(
  cd "$DIST"
  find . -type f ! -name SHA256SUMS | sed 's|^\./||' | LC_ALL=C sort > "$LIST"
)
(
  cd "$DIST"
  while IFS= read -r f; do
    printf '%s  %s\n' "$(hash_file "$f")" "$f"
  done < "$LIST" > SHA256SUMS
)
rm -f "$LIST"

echo "built $DIST"
