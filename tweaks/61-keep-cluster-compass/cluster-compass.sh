#!/bin/sh
# OpenCMU: keep the touchscreen usable while the navigation service runs.
#
# The body control module blocks touch input above a speed threshold unless
# something sends NoSpeedRestrict_TouchDisplay byte:1. On this unit the stock
# navigation service is what sends it, so the block returns whenever that
# service is not running. This runtime mirrors the navigation bus name on the
# service bus:
#
#   navigation appears    -> byte:1
#   navigation disappears -> byte:0
#
# Installed into /data/opencmu/boot.d and started by the boot hook from tweak
# 60. Nothing here runs at install time.

set -u

SOCKET=${OPENCMU_DBUS_SOCKET:-unix:path=/tmp/dbus_service_socket}
NAVI=${OPENCMU_NAVI_SERVICE:-com.jci.navi2NNG}
LOCK=${OPENCMU_COMPASS_LOCK:-/tmp/opencmu-cluster-compass.lock}
LOG=${OPENCMU_COMPASS_LOG:-/data/opencmu/logs/cluster-compass.log}
PIDFILE=$LOCK/pid
MONFILE=$LOCK/monitor.pid
MAXLOG=65536

RULE="type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='$NAVI'"
DEST=com.jci.vbs.bcm
OBJ=/com/jci/vbs/bcm
MEMBER=com.jci.vbs.bcm.NoSpeedRestrict_TouchDisplay

DBUS_SEND=$(command -v dbus-send 2>/dev/null || true)
DBUS_MONITOR=$(command -v dbus-monitor 2>/dev/null || true)
[ -n "$DBUS_SEND" ] || DBUS_SEND=/usr/bin/dbus-send
[ -n "$DBUS_MONITOR" ] || DBUS_MONITOR=/usr/bin/dbus-monitor

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

send_byte() {
    "$DBUS_SEND" --address="$SOCKET" --type=signal --dest="$DEST" \
        "$OBJ" "$MEMBER" "byte:$1" >/dev/null 2>&1
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
    rm -f "$PIDFILE" "$MONFILE" 2>/dev/null
    rmdir "$LOCK" 2>/dev/null
    mkdir "$LOCK" 2>/dev/null || { say "cannot acquire $LOCK"; return 1; }
    printf '%s\n' "$$" > "$PIDFILE" 2>/dev/null || true
    return 0
}

release() {
    rm -f "$PIDFILE" "$MONFILE" 2>/dev/null
    rmdir "$LOCK" 2>/dev/null
}

stop() {
    _old=$(cat "$PIDFILE" 2>/dev/null || true)
    _mon=$(cat "$MONFILE" 2>/dev/null || true)
    if [ -n "$_old" ] && kill -0 "$_old" 2>/dev/null; then
        kill "$_old" 2>/dev/null || true
        say "stopped pid $_old"
    fi
    if [ -n "$_mon" ] && kill -0 "$_mon" 2>/dev/null; then
        kill "$_mon" 2>/dev/null || true
    fi
    release
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

# Establish the state that matches the bus right now, instead of waiting for
# the next NameOwnerChanged.
initial() {
    if "$DBUS_SEND" --address="$SOCKET" --print-reply --dest=org.freedesktop.DBus \
         /org/freedesktop/DBus org.freedesktop.DBus.GetNameOwner "string:$NAVI" \
         >/dev/null 2>&1; then
        send_byte 1
        say "navigation service already owns $NAVI; sent byte:1"
    else
        send_byte 0
        say "navigation service not running; sent byte:0"
    fi
}

watch() {
    while :; do
        say "watching $NAVI on $SOCKET"
        "$DBUS_MONITOR" --address="$SOCKET" "$RULE" 2>/dev/null | {
            in_sig=0
            count=0
            while IFS= read -r line; do
                case $line in
                    *member=NameOwnerChanged*)
                        in_sig=1
                        count=0
                        ;;
                    *'string "'*)
                        [ "$in_sig" = 1 ] || continue
                        count=$((count + 1))
                        value=${line#*\"}
                        value=${value%\"*}
                        if [ "$count" -eq 3 ]; then
                            in_sig=0
                            if [ -n "$value" ]; then
                                send_byte 1
                                say "navigation started; sent byte:1"
                            else
                                send_byte 0
                                say "navigation stopped; sent byte:0"
                            fi
                        fi
                        ;;
                esac
            done
        }
        say "monitor exited; retrying in 5s"
        sleep 5
    done
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
    --send)
        send_byte "${2:-0}"
        exit $?
        ;;
    --probe)
        # Print every NameOwnerChanged on the service bus. Use it on the bench
        # to confirm the navigation bus name before trusting the default.
        "$DBUS_MONITOR" --address="$SOCKET" \
            "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged'"
        exit $?
        ;;
esac

if [ ! -x "$DBUS_MONITOR" ]; then
    say "dbus-monitor not found at $DBUS_MONITOR; refusing to run"
    exit 1
fi

acquire || exit 0
trap 'release' EXIT
trap 'release; exit 0' INT TERM HUP
initial
watch
