#!/bin/sh
# shellcheck disable=SC1091
# OpenCMU installer.
# Runs on the CMU, or against a fake root for testing.
set -eu

SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SELF_DIR/lib/common.sh"
. "$SELF_DIR/lib/manifest.sh"
. "$SELF_DIR/lib/patch.sh"
. "$SELF_DIR/lib/tweaks.sh"

USB_DIR=""
ROOT="/"
DRY_RUN=1
ROLLBACK=0
FORCE=0
EXPERIMENTAL=0
TWEAKS=""
LIST=0

usage() {
  cat <<'EOF'
usage: install.sh [options]

  --usb PATH          payload directory (default: this script's directory)
  --root PATH         target root (default: /; use a fake root for testing)
  --apply             actually change files (default is dry-run)
  --dry-run           print the plan only (default)
  --rollback          restore the last receipt's backup (needs --apply)
  --tweaks "A B"      tweak ids to apply (default: manifest DEFAULT_TWEAKS)
  --list              list available tweaks and exit
  --experimental      allow tweaks marked TWEAK_EXPERIMENTAL=1
  --force             allow a missing /jci/version.ini (bench roots only)
  -h, --help          show this help
EOF
}

need_value() {
  [ $# -ge 2 ] || die "missing value for $1"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --usb)          need_value "$@"; USB_DIR=$2; shift 2 ;;
    --root)         need_value "$@"; ROOT=$2; shift 2 ;;
    --apply)        DRY_RUN=0; shift ;;
    --dry-run)      DRY_RUN=1; shift ;;
    --rollback)     ROLLBACK=1; shift ;;
    --tweaks)       need_value "$@"; TWEAKS=$2; shift 2 ;;
    --list)         LIST=1; shift ;;
    --experimental) EXPERIMENTAL=1; shift ;;
    --force)        FORCE=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *)              die "unknown argument: $1" ;;
  esac
done

[ -n "$USB_DIR" ] || USB_DIR=$SELF_DIR
[ -d "$USB_DIR" ] || die "payload directory not found: $USB_DIR"
[ -f "$USB_DIR/manifest.env" ] || die "manifest.env not found in $USB_DIR"

ROOT=${ROOT%/}
[ -n "$ROOT" ] || ROOT=/

export OPENCMU_ROOT="$ROOT"
export OPENCMU_USB="$USB_DIR"
export OPENCMU_STATE="$ROOT/data/opencmu/state"
OPENCMU_BACKUP="$ROOT/data/opencmu/backups/$(date +%Y%m%d-%H%M%S)-$$"
export OPENCMU_BACKUP
export OPENCMU_LOG="$ROOT/data/opencmu/logs/install.log"
export OPENCMU_DRY_RUN="$DRY_RUN"
export OPENCMU_FORCE="$FORCE"
export OPENCMU_ENABLE_EXPERIMENTAL="$EXPERIMENTAL"

ver="unknown"

ensure_state() {
  mkdir -p "$OPENCMU_STATE" "$OPENCMU_BACKUP" "$(dirname "$OPENCMU_LOG")"
  [ -f "$OPENCMU_STATE/installed.list" ] || : > "$OPENCMU_STATE/installed.list"
  [ -w "$OPENCMU_STATE" ] || die "state directory is not writable: $OPENCMU_STATE"
  avail=$(df -Pk "$OPENCMU_ROOT" 2>/dev/null | awk 'NR==2 {print $4}')
  case "$avail" in
    ''|*[!0-9]*) : ;;
    *) [ "$avail" -ge 10240 ] || die "less than 10 MB free on $OPENCMU_ROOT" ;;
  esac
}

write_receipt() {
  ids=$1
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  {
    echo "PROJECT=\"$PROJECT_NAME\""
    echo "VERSION=\"$PROJECT_VERSION\""
    echo "INSTALLED_AT=$ts"
    echo "FIRMWARE=\"${ver:-unknown}\""
    echo "BACKUP_DIR=\"$OPENCMU_BACKUP\""
    echo "TWEAKS=\"$ids\""
  } > "$OPENCMU_STATE/receipt.env.tmp"
  mv "$OPENCMU_STATE/receipt.env.tmp" "$OPENCMU_STATE/receipt.env"

  case "$PROJECT_NAME$PROJECT_VERSION${ver:-}$OPENCMU_BACKUP$ids" in
    *\"*|*\\*) die "receipt contains characters that are unsafe for JSON" ;;
  esac

  json_ids=""
  for id in $ids; do
    json_ids="${json_ids}\"$id\","
  done
  json_ids=${json_ids%,}
  printf '{"project":"%s","version":"%s","installed_at":"%s","firmware":"%s","tweaks":[%s],"backup_dir":"%s"}\n' \
    "$PROJECT_NAME" "$PROJECT_VERSION" "$ts" "${ver:-unknown}" "$json_ids" "$OPENCMU_BACKUP" \
    > "$OPENCMU_STATE/receipt.json.tmp"
  mv "$OPENCMU_STATE/receipt.json.tmp" "$OPENCMU_STATE/receipt.json"
}

do_rollback() {
  [ -f "$OPENCMU_STATE/receipt.env" ] || die "no receipt; cannot rollback automatically"
  . "$OPENCMU_STATE/receipt.env"
  [ -n "${BACKUP_DIR:-}" ] || die "receipt has no BACKUP_DIR"
  [ -d "$BACKUP_DIR" ] || die "backup directory missing: $BACKUP_DIR"

  OPENCMU_BACKUP="$BACKUP_DIR"
  export OPENCMU_BACKUP

  if [ ! -s "$OPENCMU_STATE/installed.list" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log "rollback plan (dry-run): no tweaks recorded"
      return 0
    fi
    if [ -s "$OPENCMU_BACKUP/.created" ] || [ -n "$(find "$OPENCMU_BACKUP" -type f ! -name .created | head -n 1)" ]; then
      warn "installed.list is empty but $OPENCMU_BACKUP contains backups"
      warn "nothing was rolled back; inspect the backup and remove $OPENCMU_STATE/receipt.env manually"
      return 1
    fi
    log "no changes recorded; clearing receipt"
    rm -f "$OPENCMU_STATE/receipt.env" "$OPENCMU_STATE/receipt.json"
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "rollback plan (dry-run): $(tr '\n' ' ' < "$OPENCMU_STATE/installed.list")"
    log "re-run with --apply --rollback to restore"
    return 0
  fi

  for id in $(reverse_file "$OPENCMU_STATE/installed.list"); do
    rollback_tweak "$id"
  done

  rm -f "$OPENCMU_STATE/installed.list" "$OPENCMU_STATE/receipt.env" "$OPENCMU_STATE/receipt.json"
  log "rollback complete; backups kept in $OPENCMU_BACKUP"
}

main() {
  need_cmd awk
  load_manifest

  if [ "$LIST" -eq 1 ]; then
    list_tweaks
    return 0
  fi

  if [ "$ROLLBACK" -eq 1 ]; then
    do_rollback || return 1
    return 0
  fi

  check_firmware

  plan=${TWEAKS:-$DEFAULT_TWEAKS}
  [ -n "$plan" ] || die "no tweaks selected"

  log "payload: $PROJECT_NAME $PROJECT_VERSION"
  log "root: $OPENCMU_ROOT"
  log "plan: $plan"

  if [ "$DRY_RUN" -eq 1 ]; then
    for id in $plan; do
      apply_tweak "$id"
    done
    log "dry-run complete; re-run with --apply to change files"
    return 0
  fi

  for id in $plan; do
    preflight_tweak "$id"
  done

  if [ -f "$OPENCMU_STATE/receipt.env" ]; then
    die "a previous install is recorded in $OPENCMU_STATE; run --apply --rollback first"
  fi

  ensure_state
  write_receipt "$plan"
  for id in $plan; do
    apply_tweak "$id"
  done

  write_receipt "$plan"
  log "install complete"
  log "receipt: $OPENCMU_STATE/receipt.env"
}

main
