#!/bin/sh
# shellcheck disable=SC2154
# One key, RSA only: the unit ships OpenSSH 5.9, which cannot read ed25519.
target="$OPENCMU_ROOT/etc/ssh/sshd_config"
[ -f "$target" ] || die "sshd_config not found: $target"

pub="${OPENCMU_SSH_PUBKEY:-}"
[ -n "$pub" ] || die "set OPENCMU_SSH_PUBKEY to a file with one RSA public key"
[ -f "$pub" ] || die "public key not found: $pub"

key_count=$(awk 'NF && $1 !~ /^#/ { c++ } END { print c + 0 }' "$pub")
[ "$key_count" -eq 1 ] || die "public key file must contain exactly one key: $pub"
key=$(awk 'NF && $1 !~ /^#/ { print; exit }' "$pub")

case "$key" in
  ssh-rsa\ *) : ;;
  ssh-ed25519\ *) die "OpenSSH 5.9 cannot use ed25519 keys; use an RSA key" ;;
  *) die "unsupported public key type; use an ssh-rsa key" ;;
esac

b64=$(printf '%s\n' "$key" | awk '{ print $2 }')
case "$b64" in
  ''|*[!A-Za-z0-9+/=]*) die "public key does not contain a base64 body" ;;
esac

keys="$OPENCMU_ROOT/data/opencmu/ssh/authorized_keys"
mkdir -p "$(dirname "$keys")" || die "cannot create $(dirname "$keys")"
chmod 700 "$(dirname "$keys")" 2>/dev/null || true
record_created "$keys"
backup_file "$keys" >/dev/null || die "backup failed: $keys"
printf '%s\n' "$key" > "$keys.opencmu-new.$$" || die "cannot write $keys"
chmod 600 "$keys.opencmu-new.$$"
atomic_write "$keys" "$keys.opencmu-new.$$"
chmod 600 "$keys"
rm -f "$keys.opencmu-new.$$"
log "installed authorized key: $keys"

prepend_once "$target" 'opencmu:enable-ssh' "$dir/sshd-block.conf"

# Config and start checks only make sense against the live root. A failure to
# start is reported, not turned into a half-applied install.
if [ "${OPENCMU_ROOT%/}" = "" ]; then
  SSHDBIN=$(command -v sshd 2>/dev/null || true)
  [ -n "$SSHDBIN" ] || SSHDBIN=/usr/sbin/sshd
  if [ -x "$SSHDBIN" ]; then
    if "$SSHDBIN" -t >/dev/null 2>&1; then
      log "sshd accepted the new configuration"
      if [ "${OPENCMU_SSH_START:-1}" = "1" ]; then
        "$SSHDBIN" >/dev/null 2>&1 || warn "sshd did not start (already running?)"
      fi
    else
      warn "sshd -t rejected the new configuration; inspect $target"
    fi
  else
    warn "sshd not found; the config is installed but nothing was started"
  fi
fi
