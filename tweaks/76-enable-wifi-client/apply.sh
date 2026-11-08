#!/bin/sh
# shellcheck disable=SC2154
boot="$OPENCMU_ROOT/data/opencmu/boot.d"
[ -f "$boot/README.txt" ] || die "boot.d missing: apply 60-startup-hook first"

ssid="${OPENCMU_WIFI_SSID:-}"
psk="${OPENCMU_WIFI_PSK:-}"
[ -n "$ssid" ] || die "set OPENCMU_WIFI_SSID to the network name"
[ -n "$psk" ] || die "set OPENCMU_WIFI_PSK to the WPA passphrase"
case "$ssid$psk" in
  *"
"*) die "SSID and passphrase must be single-line" ;;
esac
psk_len=${#psk}
[ "$psk_len" -ge 8 ] && [ "$psk_len" -le 63 ] ||
  die "WPA passphrase must be between 8 and 63 characters"

iface="${OPENCMU_WIFI_IFACE:-wlan0}"
case "$iface" in
  ''|*[!A-Za-z0-9._-]*) die "invalid interface name: $iface" ;;
esac

static="${OPENCMU_WIFI_STATIC_IP:-}"
netmask="${OPENCMU_WIFI_NETMASK:-255.255.255.0}"
gateway="${OPENCMU_WIFI_GATEWAY:-}"
case "$static$netmask$gateway" in
  *[!0-9.]*) die "static address, netmask and gateway must be IPv4 literals" ;;
esac
if [ -n "$static" ] && [ -z "$netmask" ]; then
  die "OPENCMU_WIFI_NETMASK is required with a static address"
fi

if [ "${OPENCMU_ROOT%/}" = "" ]; then
  command -v wpa_supplicant >/dev/null 2>&1 ||
    die "wpa_supplicant not found on this unit"
fi

# Quote a value for a shell-sourced config file and for wpa_supplicant.
quote_sh() { printf '%s' "$1" | sed "s/'/'\\\\''/g"; }
quote_wpa() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

conf="$OPENCMU_ROOT/data/opencmu/config/wifi-client.conf"
mkdir -p "$(dirname "$conf")" || die "cannot create $(dirname "$conf")"
chmod 700 "$(dirname "$conf")" 2>/dev/null || true
record_created "$conf"
backup_file "$conf" >/dev/null || die "backup failed: $conf"
{
  printf "WIFI_IFACE='%s'\n" "$(quote_sh "$iface")"
  printf "WIFI_SSID='%s'\n" "$(quote_sh "$ssid")"
  printf "WIFI_PSK='%s'\n" "$(quote_sh "$psk")"
  printf "WIFI_IFACE_WAIT='%s'\n" "${OPENCMU_WIFI_IFACE_WAIT:-30}"
  printf "WIFI_ASSOC_WAIT='%s'\n" "${OPENCMU_WIFI_ASSOC_WAIT:-30}"
  printf "WIFI_STATIC_IP='%s'\n" "$(quote_sh "$static")"
  printf "WIFI_NETMASK='%s'\n" "$(quote_sh "$netmask")"
  printf "WIFI_GATEWAY='%s'\n" "$(quote_sh "$gateway")"
} > "$conf.opencmu-new.$$" || { rm -f "$conf.opencmu-new.$$"; die "cannot write $conf"; }
atomic_write "$conf" "$conf.opencmu-new.$$"
chmod 600 "$conf"
rm -f "$conf.opencmu-new.$$"
log "wrote Wi-Fi client config: $conf"

wpa="$OPENCMU_ROOT/data/opencmu/wifi/wpa_supplicant.conf"
mkdir -p "$(dirname "$wpa")" || die "cannot create $(dirname "$wpa")"
chmod 700 "$(dirname "$wpa")" 2>/dev/null || true
record_created "$wpa"
backup_file "$wpa" >/dev/null || die "backup failed: $wpa"
{
  printf 'ctrl_interface=/var/run/wpa_supplicant\n'
  printf 'ap_scan=1\n\n'
  printf 'network={\n'
  printf '    ssid="%s"\n' "$(quote_wpa "$ssid")"
  printf '    psk="%s"\n' "$(quote_wpa "$psk")"
  printf '    key_mgmt=WPA-PSK\n'
  printf '    scan_ssid=1\n'
  printf '}\n'
} > "$wpa.opencmu-new.$$" || { rm -f "$wpa.opencmu-new.$$"; die "cannot write $wpa"; }
atomic_write "$wpa" "$wpa.opencmu-new.$$"
chmod 600 "$wpa"
rm -f "$wpa.opencmu-new.$$"
log "wrote wpa_supplicant config: $wpa"

src="$dir/wifi-client.sh"
[ -f "$src" ] || die "runtime script missing: $src"
sh -n "$src" || die "runtime script has a syntax error: $src"

target="$boot/76-wifi-client.sh"
record_created "$target"
backup_file "$target" >/dev/null || die "backup failed: $target"
cp "$src" "$target.opencmu-new.$$" || die "copy failed: $target"
chmod 755 "$target.opencmu-new.$$"
atomic_write "$target" "$target.opencmu-new.$$"
rm -f "$target.opencmu-new.$$"
log "installed Wi-Fi client runtime: $target"
