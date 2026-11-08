#!/bin/sh
# OpenCMU: keep the touchscreen locked at every speed.
#
# The HMI accepts touch input until something tells the LVDS block otherwise.
# This runtime sends com.jci.lvds.SpeedRestriction uint32:1 and re-asserts it
# on a timer, because the stock interface resets the restriction when it
# believes the vehicle is stopped. It does not change the speed thresholds in
# NVRAM and it does not patch a GUI file.
#
# Installed into /data/opencmu/boot.d and started by the boot hook from tweak
# 60. Nothing here runs at install time unless --start is passed by hand.

set -u

SOCKET=${OPENCMU_LVDS_SOCKET:-unix:path=/tmp/dbus_hmi_socket}
DEST=${OPENCMU_LVDS_SERVICE:-com.jci.lvds}
OBJ=${OPENCMU_LVDS_OBJECT:-/com/jci/lvds}
MEMBER=${OPENCMU_LVDS_MEMBER:-com.jci.lvds.SpeedRestriction}
POLL=${OPENCMU_LVDS_POLL:-5}
WAIT=${OPENCMU_LVDS_WAIT:-20}
LVDS_DIR=${OPENCMU_LVDS_DIR:-/jci/lvds_blm}
LOCK=${OPENCMU_TOUCH_LOCK:-/tmp/opencmu-disable-touchscreen.lock}
LOG=${OPENCMU_TOUCH_LOG:-/data/opencmu/logs/disable-touchscreen.log}
PIDFILE=$LOCK/pid
MAXLOG=65536

DBUS_SEND=$(command -v dbus-send 2>/dev/null || true)
[ -n "$DBUS_SEND" ] || DBUS_SEND=/usr/bin/dbus-send

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

send() {
    "$DBUS_SEND" --address="$SOCKET" --type=method_call --dest="$DEST" \
        --reply-timeout=4000 "$OBJ" "$MEMBER" "uint32:$1" >/dev/null 2>&1
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

stop() {
    _old=$(cat "$PIDFILE" 2>/dev/null || true)
    if [ -n "$_old" ] && kill -0 "$_old" 2>/dev/null; then
        kill "$_old" 2>/dev/null || true
        say "stopped pid $_old"
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

# Wait for the LVDS service files. A board that does not expose them still gets
# the restriction: a late lock is better than no lock, and the log says so.
wait_for_lvds() {
    _n=$WAIT
    while [ "$_n" -gt 0 ]; do
        if [ -e "$LVDS_DIR/svc" ] &&
           { [ -e "$LVDS_DIR/jcilvds_blm.so" ] || [ -e "$LVDS_DIR/svc/jcilvds_blm.so" ]; }; then
            say "jcilvds_blm settled after $((WAIT - _n))s"
            return 0
        fi
        _n=$((_n - 1))
        sleep 1
    done
    say "jcilvds_blm not found or not settled; locking anyway"
    return 1
}

case ${1:-} in
    --stop)
        stop
        exit 0
        ;;
    --release)
        stop
        if send 0; then
            say "SpeedRestriction(0) sent after release"
        else
            say "release send failed"
        fi
        exit 0
        ;;
    --status)
        status
        exit $?
        ;;
    --send)
        send "${2:-1}"
        exit $?
        ;;
esac

if [ ! -x "$DBUS_SEND" ]; then
    say "dbus-send not found at $DBUS_SEND; refusing to run"
    exit 1
fi

acquire || exit 0
trap 'release' EXIT
trap 'release; exit 0' INT TERM HUP

wait_for_lvds || true

i=0
while :; do
    if send 1; then
        if [ "$i" -eq 0 ] || [ $((i % 12)) -eq 0 ]; then
            say "SpeedRestriction(1) sent"
        fi
    else
        say "dbus-send failed; retrying in ${POLL}s"
    fi
    i=$((i + 1))
    sleep "$POLL"
done
