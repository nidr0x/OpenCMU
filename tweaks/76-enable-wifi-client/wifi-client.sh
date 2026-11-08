#!/bin/sh
# OpenCMU: use the Wi-Fi interface as a client instead of the stock access point.
#
# The stock boot scripts bring wlan0 up as an access point. This runtime stops
# the AP processes, starts wpa_supplicant with a client configuration and
# requests an address over DHCP or applies a static one. It never blocks boot:
# the boot hook starts it in the background and every wait is bounded.
#
# Installed into /data/opencmu/boot.d and started by the boot hook from tweak
# 60. The credentials live in /data/opencmu/config/wifi-client.conf (mode 600).

set -u

CONF=${OPENCMU_WIFI_CONF:-/data/opencmu/config/wifi-client.conf}
WPA_CONF=${OPENCMU_WPA_CONF:-/data/opencmu/wifi/wpa_supplicant.conf}
LOCK=${OPENCMU_WIFI_LOCK:-/tmp/opencmu-wifi-client.lock}
LOG=${OPENCMU_WIFI_LOG:-/data/opencmu/logs/wifi-client.log}
PIDFILE=$LOCK/pid
MAXLOG=65536

[ -f "$CONF" ] || {
    echo "wifi-client: missing $CONF" >&2
    exit 1
}

# The config is written by the installer with shell-quoted values.
# shellcheck disable=SC1090
. "$CONF"

IFACE=${WIFI_IFACE:-wlan0}
IFACE_WAIT=${WIFI_IFACE_WAIT:-30}
ASSOC_WAIT=${WIFI_ASSOC_WAIT:-30}
STATIC_IP=${WIFI_STATIC_IP:-}
NETMASK=${WIFI_NETMASK:-255.255.255.0}
GATEWAY=${WIFI_GATEWAY:-}

WPA_PID=/var/run/opencmu-wpa-$IFACE.pid
DHCP_PID=/var/run/opencmu-udhcpc-$IFACE.pid

# The boot hook may run with a short PATH, so resolve the tools once.
resolve_bin() {
    _name=$1
    _found=$(command -v "$_name" 2>/dev/null || true)
    if [ -n "$_found" ]; then
        printf '%s\n' "$_found"
        return 0
    fi
    for _dir in /usr/sbin /sbin /usr/bin /bin; do
        if [ -x "$_dir/$_name" ]; then
            printf '%s\n' "$_dir/$_name"
            return 0
        fi
    done
    return 1
}

WPA_BIN=$(resolve_bin wpa_supplicant || true)
WPA_CLI_BIN=$(resolve_bin wpa_cli || true)
IFCONFIG_BIN=$(resolve_bin ifconfig || true)
UDHCPC_BIN=$(resolve_bin udhcpc || true)
ROUTE_BIN=$(resolve_bin route || true)
IWCONFIG_BIN=$(resolve_bin iwconfig || true)

say() {
    [ -n "$LOG" ] || return 0
    _dir=$(dirname "$LOG")
    [ -d "$_dir" ] || mkdir -p "$_dir" 2>/dev/null || return 0
    if [ -f "$LOG" ]; then
        _size=$(wc -c < "$LOG" 2>/dev/null | tr -d ' ')
        case ${_size:-0} in
            ''|*[!0-9]*) _size=0 ;;
        esac
        [ "$_size" -le "$MAXLOG" ] || : > "$LOG"
    fi
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '-')" "$*" >> "$LOG" 2>/dev/null
}

acquire() {
    if mkdir "$LOCK" 2>/dev/null; then
        printf '%s\n' "$$" > "$PIDFILE" 2>/dev/null || true
        return 0
    fi
    _old=$(cat "$PIDFILE" 2>/dev/null || true)
    if [ -n "$_old" ] && kill -0 "$_old" 2>/dev/null; then
        say "another runtime is running (pid $_old); exiting"
        return 1
    fi
    rm -f "$PIDFILE" 2>/dev/null
    rmdir "$LOCK" 2>/dev/null
    mkdir "$LOCK" 2>/dev/null || { say "cannot acquire $LOCK"; return 1; }
    printf '%s\n' "$$" > "$PIDFILE" 2>/dev/null || true
    return 0
}

release() {
    rm -f "$PIDFILE" 2>/dev/null
    rmdir "$LOCK" 2>/dev/null
}

status() {
    _old=$(cat "$PIDFILE" 2>/dev/null || true)
    if [ -n "$_old" ] && kill -0 "$_old" 2>/dev/null; then
        echo "running pid $_old"
        return 0
    fi
    echo "not running"
    return 1
}

kill_matching() {
    # Filter the grep process itself out of the result: its command line
    # contains the pattern and would otherwise be killed before the target.
    # shellcheck disable=SC2009
    ps 2>/dev/null | grep -F -- "$1" | grep -v '[g]rep' | awk '{ print $1 }' |
        while IFS= read -r _pid; do
            kill "$_pid" 2>/dev/null || true
        done
}

stop_client() {
    if [ -f "$WPA_PID" ]; then
        _wpa=$(cat "$WPA_PID" 2>/dev/null || true)
        if [ -n "$_wpa" ] && kill -0 "$_wpa" 2>/dev/null; then
            kill "$_wpa" 2>/dev/null || true
            say "stopped wpa_supplicant pid $_wpa"
        fi
        rm -f "$WPA_PID"
    fi
    kill_matching "udhcpc.*$IFACE"
    say "client stopped; reboot to return to the stock access point"
}

stop() {
    stop_client
    release
}

wait_for_iface() {
    _n=$IFACE_WAIT
    while [ "$_n" -gt 0 ]; do
        [ -e "/sys/class/net/$IFACE" ] && return 0
        _n=$((_n - 1))
        sleep 1
    done
    say "interface $IFACE did not appear after ${IFACE_WAIT}s"
    return 1
}

stop_ap() {
    # The stock access point owns wlan0 until hostapd and its DHCP server stop.
    if command -v killall >/dev/null 2>&1; then
        killall hostapd udhcpd >/dev/null 2>&1 || true
    else
        kill_matching 'hostapd'
        kill_matching 'udhcpd'
    fi
    kill_matching "wpa_supplicant.*$IFACE"
    say "stopped stock access-point processes"
}

start_wpa() {
    mkdir -p /var/run/wpa_supplicant 2>/dev/null || true
    for drv in nl80211 wext; do
        rm -f "$WPA_PID"
        if "$WPA_BIN" -B -P "$WPA_PID" -i "$IFACE" -D "$drv" -c "$WPA_CONF" >/dev/null 2>&1; then
            sleep 1
            if [ -s "$WPA_PID" ]; then
                say "wpa_supplicant started with driver $drv"
                return 0
            fi
        fi
        say "wpa_supplicant did not start with driver $drv"
    done
    say "FAIL: wpa_supplicant would not start with any driver"
    return 1
}

wpa_running() {
    [ -f "$WPA_PID" ] || return 1
    _wpa=$(cat "$WPA_PID" 2>/dev/null || true)
    [ -n "$_wpa" ] && kill -0 "$_wpa" 2>/dev/null
}

wait_assoc() {
    _n=$ASSOC_WAIT
    _last=unknown
    while [ "$_n" -gt 0 ]; do
        if [ -n "$WPA_CLI_BIN" ]; then
            _state=$("$WPA_CLI_BIN" -i "$IFACE" status 2>/dev/null | awk -F= '$1 == "wpa_state" { print $2 }')
            _last=${_state:-unknown}
            [ "$_last" = "COMPLETED" ] && return 0
        elif [ -n "$IWCONFIG_BIN" ] && "$IWCONFIG_BIN" "$IFACE" 2>/dev/null | grep -q 'Access Point: [0-9A-Fa-f]'; then
            return 0
        fi
        _n=$((_n - 1))
        sleep 1
    done
    say "FAIL: association did not complete (wpa_state=$_last)"
    return 1
}

apply_address() {
    if [ -n "$STATIC_IP" ]; then
        "$IFCONFIG_BIN" "$IFACE" "$STATIC_IP" netmask "$NETMASK" up >/dev/null 2>&1 ||
            { say "ifconfig failed for $STATIC_IP"; return 1; }
        if [ -n "$GATEWAY" ]; then
            "$ROUTE_BIN" del default gw "$GATEWAY" >/dev/null 2>&1 || true
            "$ROUTE_BIN" add default gw "$GATEWAY" >/dev/null 2>&1 ||
                say "could not add default route via $GATEWAY"
        fi
        say "static address applied: $STATIC_IP/$NETMASK"
    else
        "$UDHCPC_BIN" -b -i "$IFACE" -p "$DHCP_PID" >/dev/null 2>&1 ||
            { say "udhcpc did not start"; return 1; }
        say "DHCP requested on $IFACE"
    fi
    return 0
}

run_once() {
    wait_for_iface || return 1
    stop_ap
    "$IFCONFIG_BIN" "$IFACE" down >/dev/null 2>&1 || true
    "$IFCONFIG_BIN" "$IFACE" up >/dev/null 2>&1 || true
    start_wpa || return 1
    wait_assoc || return 1
    apply_address
}

case ${1:-} in
    --stop)
        stop
        exit 0
        ;;
    --status)
        status
        exit $?
        ;;
    --probe)
        [ -n "$WPA_CLI_BIN" ] && "$WPA_CLI_BIN" -i "$IFACE" status
        [ -n "$IWCONFIG_BIN" ] && "$IWCONFIG_BIN" "$IFACE" 2>/dev/null
        exit 0
        ;;
esac

if [ -z "$WPA_BIN" ] || [ -z "$IFCONFIG_BIN" ]; then
    say "wpa_supplicant or ifconfig not found; refusing to run"
    exit 1
fi

acquire || exit 0
trap 'release' EXIT
trap 'release; exit 0' INT TERM HUP

# One attempt, then a bounded retry loop. A failed attempt leaves the unit
# without the stock AP, so the log is the only reliable way to see why.
while :; do
    if run_once; then
        while wpa_running; do
            sleep 30
        done
        say "wpa_supplicant exited; restarting"
    fi
    sleep 15
done
