#!/bin/sh
# OpenCMU USB entrypoint.
# Finds the payload directory and hands control to install.sh.
set -eu

SELF=$0
case "$SELF" in
  */*) USB_DIR=$(CDPATH='' cd -- "$(dirname -- "$SELF")" && pwd) ;;
  *)   USB_DIR=$(pwd) ;;
esac

exec /bin/sh "$USB_DIR/install.sh" --usb "$USB_DIR" "$@"
