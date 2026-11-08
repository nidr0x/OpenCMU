#!/bin/sh
# OpenCMU common helpers. Sourced by install.sh and tweak scripts.

log()  { printf '%s %s\n' "[opencmu]" "$*"; }
warn() { printf '%s WARN: %s\n' "[opencmu]" "$*" >&2; }
die()  { printf '%s ERROR: %s\n' "[opencmu]" "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  else
    die "no sha256 tool found (need sha256sum, shasum, or openssl)"
  fi
}

# version_cmp A B -> prints -1, 0 or 1
version_cmp() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    n = split(a, x, ".");
    m = split(b, y, ".");
    for (i = 1; i <= n || i <= m; i++) {
      xi = (i <= n) ? x[i] + 0 : 0;
      yi = (i <= m) ? y[i] + 0 : 0;
      if (xi < yi) { print -1; exit }
      if (xi > yi) { print 1; exit }
    }
    print 0
  }'
}

version_ge() { [ "$(version_cmp "$1" "$2")" -ge 0 ]; }
version_le() { [ "$(version_cmp "$1" "$2")" -le 0 ]; }

# reverse_file FILE -> prints lines in reverse order
reverse_file() {
  awk '{ a[NR] = $0 } END { for (i = NR; i >= 1; i--) print a[i] }' "$1"
}

# backup_file PATH -> copies PATH under OPENCMU_BACKUP and prints the backup path
backup_file() {
  path=$1
  [ -e "$path" ] || return 0
  [ -L "$path" ] && die "refusing to back up through symlink: $path"
  rel=${path#"/"}
  dest="$OPENCMU_BACKUP/$rel"
  # First backup wins: a tweak that patches the same file twice must roll back
  # to the pre-install content, not to an intermediate state.
  if [ -f "$dest" ]; then
    printf '%s\n' "$dest"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  cp -p "$path" "$dest"
  printf '%s\n' "$dest"
}

# restore_file PATH -> restores PATH from OPENCMU_BACKUP
restore_file() {
  path=$1
  [ -L "$path" ] && die "refusing to restore through symlink: $path"
  rel=${path#"/"}
  src="$OPENCMU_BACKUP/$rel"
  [ -f "$src" ] || { warn "no backup for $path"; return 1; }
  mkdir -p "$(dirname "$path")"
  cp -p "$src" "$path"
}

# record_created PATH -> remembers that PATH did not exist before this run
record_created() {
  path=$1
  [ -e "$path" ] && return 0
  mkdir -p "$OPENCMU_BACKUP"
  printf '%s\n' "$path" >> "$OPENCMU_BACKUP/.created"
}

# rollback_path PATH -> restore from backup, or remove a file this run created
rollback_path() {
  path=$1
  rel=${path#"/"}
  if [ -f "$OPENCMU_BACKUP/$rel" ]; then
    restore_file "$path" || return 1
    log "restored $path"
  elif grep -qxF "$path" "$OPENCMU_BACKUP/.created" 2>/dev/null; then
    rm -f "$path"
    log "removed $path"
  else
    warn "nothing to roll back for $path"
  fi
}

# atomic_write DEST CONTENT_FILE
atomic_write() {
  dest=$1
  src=$2
  [ -L "$dest" ] && die "refusing to write through symlink: $dest"
  [ -f "$src" ] || die "content file not found: $src"
  mkdir -p "$(dirname "$dest")"
  tmp="$dest.opencmu-tmp.$$"
  trap 'rm -f "$tmp"' EXIT HUP INT TERM
  if [ -f "$dest" ]; then
    cp -p "$dest" "$tmp"
    cat "$src" > "$tmp"
  else
    cp "$src" "$tmp"
  fi
  sync "$tmp" 2>/dev/null || sync
  mv "$tmp" "$dest"
  trap - EXIT HUP INT TERM
}

# install_replacement TARGET REPLACEMENT [EXPECTED_SHA256]
# Backs up TARGET, verifies the backup against EXPECTED_SHA256 (when given),
# checks that TARGET did not change during the backup, then installs
# REPLACEMENT atomically. Used by the experimental tweak templates.
install_replacement() {
  target=$1
  repl=$2
  expected=${3:-}
  [ -f "$repl" ] || die "replacement file not found: $repl"
  [ -f "$target" ] || die "target file not found: $target"
  [ -L "$target" ] && die "refusing to replace symlink: $target"

  backup=$(backup_file "$target") || die "backup failed: $target"
  [ -n "$backup" ] || die "backup failed: $target"

  if [ -n "$expected" ]; then
    actual=$(sha256_file "$backup")
    [ "$actual" = "$expected" ] || die "target hash mismatch: expected $expected, got $actual"
  fi

  [ "$(sha256_file "$target")" = "$(sha256_file "$backup")" ] ||
    die "target changed while preparing the replacement: $target"

  atomic_write "$target" "$repl"
}
