#!/bin/sh
# Build the read-only stock collector payload in dist/opencmu-collect.
#
# This is deliberately separate from dist/opencmu-usb and from the installer.
# It exists for one job: copy a whitelist of stock firmware files to the USB so
# a tweak can be written against the real files. It writes nothing to the unit.
#
# The .up filename is a command injection that the factory updater evaluates.
# That is the same technique third-party packages use, and it is the only
# on-unit trigger known to work on this hardware. It is opt-in: nothing in the
# supported installer path does this.
#
# Usage: build-collect.sh [DEST]

set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
DIST=${1:-$ROOT_DIR/dist/opencmu-collect}

case "$DIST" in
  ''|/|.|..) echo "refusing to remove destination: '$DIST'" >&2; exit 1 ;;
esac
[ "$DIST" != "$ROOT_DIR" ] || { echo "refusing to remove the source tree" >&2; exit 1; }
case "$ROOT_DIR/" in
  "$DIST"/*) echo "refusing to remove a parent of the source tree: $DIST" >&2; exit 1 ;;
esac

command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

rm -rf "$DIST"
mkdir -p "$DIST"

cp "$ROOT_DIR/builder/collect.sh" "$DIST/collect.sh"
cp "$ROOT_DIR/builder/collect.files" "$DIST/files.txt"
chmod +x "$DIST/collect.sh"

cat > "$DIST/bootstrap.sh" <<'EOF'
#!/bin/sh
D=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
exec sh "$D/collect.sh" "$D"
EOF
chmod +x "$DIST/bootstrap.sh"

# Marker used by the collector to identify its own USB.
: > "$DIST/.opencmu-collect"

cat > "$DIST/README.txt" <<'EOF'
OpenCMU stock collector (read-only)

What it does
  Copies a whitelist of stock Mazda Connect files from the unit to
  opencmu-dump/ on this USB, with a SHA-256 manifest. It does not modify,
  delete, remount, or execute anything on the unit.

How to use
  1. Format a USB drive as FAT32 with an MBR partition table.
  2. Copy the CONTENTS of this directory to the root of the drive.
     The root must contain bootstrap.sh, collect.sh, files.txt,
     .opencmu-collect, and the .up file.
  3. With the ignition on, insert the drive in a media USB port.
  4. Wait until the unit is idle, then remove the drive.
  5. Check that opencmu-dump/DONE exists, then send back opencmu-dump/.

If opencmu-dump/ does not appear, the trigger did not run. Nothing was
changed on the unit; the drive is reusable.

The .up file name is a command injection evaluated by the factory updater.
It is why this payload runs at all. It is a one-off diagnostic tool, not part
of the installer.
EOF

python3 "$ROOT_DIR/builder/make-up.py" --out "$DIST/opencmu-collect.up" --force >/dev/null

# Evaluated by the updater's filename handling: find the mounted USB that
# carries our marker, then run its bootstrap. No literal slash may appear in
# the name, so the separator comes from ${S}. The single quotes are the point:
# the text must reach the updater verbatim.
# shellcheck disable=SC2016
UP_NAME='$(S=${HOME%root};for d in sda1 sdb1 sdc1 sdd1;do U=${S}tmp${S}mnt${S}$d;[ -f ${U}${S}.opencmu-collect ]&&sh ${U}${S}bootstrap.sh&&break;done).up'
mv "$DIST/opencmu-collect.up" "$DIST/$UP_NAME"

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

LIST=$(mktemp "${TMPDIR:-/tmp}/opencmu-collect-sums.XXXXXX")
trap 'rm -f "$LIST"' EXIT INT TERM

(
  cd "$DIST"
  find . -type f ! -name SHA256SUMS | sed 's|^\./||' | LC_ALL=C sort > "$LIST"
)
(
  cd "$DIST"
  while IFS= read -r f; do
    printf '%s  %s\n' "$(hash_file "$f")" "$f"
  done < "$LIST"
) > "$DIST/SHA256SUMS"
rm -f "$LIST"

echo "built $DIST"
echo "copy the contents to a FAT32 USB root, not the directory itself"
