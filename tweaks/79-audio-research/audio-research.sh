#!/bin/sh
# OpenCMU: a passive look at the audio stack after boot.
#
# A read-only profiler. It finds the lastModeSvc process and the file it
# persists to, watches that file for changes, polls the stock audio readiness
# flags, and listens passively to two broadcast D-Bus signals. It starts
# nothing, stops nothing, calls no getters and never touches smdb-read (an
# aborted smdb-read keeps the service-manager lock and reboots the unit; see
# docs/safety.md). The only load is one dbus-monitor process for the window
# plus cheap file probes once per second.
#
# What it records, all stock facts for fw74.00.324:
#   AUDIO_START   /var/run/audio_start, touched by /jci/am/start_audio.sh
#   READY_*       the four ready flags sm.conf starts the audio daemons with:
#                   /tmp/dbus/com.xse.service.AudioControl           (audioCtrl)
#                   /tmp/dbus/com.xsembedded.service.AudioAmplifier  (audioAmp)
#                   /tmp/dbus/com.xsembedded.service.AudioManagement (audioMgr)
#                   /tmp/dbus/com.xsembedded.service.xsesvc2dbus.tau
#   LASTMODE      the lastModeSvc process found via /proc/*/cmdline and the
#                 argument after -f. The usage string documents -f, but
#                 nothing in the static tree starts lastModeSvc, so whether
#                 it runs at all on NA is exactly what this answers.
#   DBUS_SIG      a tally of com.jci.vbs.vdt and com.jci.vbs.bcm broadcast
#                 members seen by a passive dbus-monitor on
#                 /tmp/dbus_service_socket (present at /usr/bin/dbus-monitor).
#   VBS_HANDLER   /usr/bin/audioCtrl_VBS.lua, the AM/FM extHdlr referenced by
#                 ControlConfig.json inputs 2 and 3; absent on NA stock.
#
# Installed into /data/opencmu/boot.d and started by the boot hook from tweak
# 60. It can also be run by hand from SSH; then it simply reports current
# state for its window.

set -u

LOG=${OPENCMU_AUDIO_LOG:-/data/opencmu/logs/audio-research.log}
UPFILE=${OPENCMU_AUDIO_UPTIME:-/proc/uptime}
WINDOW=${OPENCMU_AUDIO_WINDOW:-90}
STEADY=${OPENCMU_AUDIO_STEADY:-45}
LOCK=${OPENCMU_AUDIO_LOCK:-/tmp/opencmu-audio-research.lock}
SVC_BUS=${OPENCMU_AUDIO_SVC_BUS:-/tmp/dbus_service_socket}
READY_DIR=${OPENCMU_AUDIO_READY_DIR:-/tmp/dbus}
AUDIO_START=${OPENCMU_AUDIO_START_FLAG:-/var/run/audio_start}
VBS_HANDLER=${OPENCMU_AUDIO_VBS_HANDLER:-/usr/bin/audioCtrl_VBS.lua}
LASTMODE_NAME=${OPENCMU_AUDIO_LASTMODE_NAME:-lastModeSvc.lua}
# shellcheck disable=SC2016
READY_FLAGS=${OPENCMU_AUDIO_READY_FLAGS:-'com.xse.service.AudioControl com.xsembedded.service.AudioAmplifier com.xsembedded.service.AudioManagement com.xsembedded.service.xsesvc2dbus.tau'}
MAXLOG=131072
DBUS_MON_PID=
MON_OUT=/tmp/opencmu-audio-research.mon.$$

have() {
    command -v "$1" >/dev/null 2>&1
}

up_now() {
    awk '{ printf "%s", $1 }' "$UPFILE" 2>/dev/null || echo 0
}

# elapsed BOOT -> whole seconds since BOOT, never negative
elapsed() {
    C=$(up_now)
    awk -v n="$C" -v s="$1" 'BEGIN { d = n - s; if (d < 0) d = 0; printf "%.1f", d }'
}

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
    printf '%s %s\n' "$(up_now)" "$*" >> "$LOG" 2>/dev/null
}

acquire() {
    if mkdir "$LOCK" 2>/dev/null; then
        printf '%s\n' "$$" > "$LOCK/pid" 2>/dev/null || true
        return 0
    fi
    _old=$(cat "$LOCK/pid" 2>/dev/null || true)
    if [ -n "$_old" ] && kill -0 "$_old" 2>/dev/null; then
        say "another audio research run is active (pid $_old); exiting"
        return 1
    fi
    rm -f "$LOCK/pid" 2>/dev/null
    rmdir "$LOCK" 2>/dev/null
    mkdir "$LOCK" 2>/dev/null || { say "cannot take $LOCK"; return 1; }
    printf '%s\n' "$$" > "$LOCK/pid" 2>/dev/null || true
    return 0
}

release() {
    if [ -n "$DBUS_MON_PID" ]; then
        kill "$DBUS_MON_PID" 2>/dev/null
        wait "$DBUS_MON_PID" 2>/dev/null
    fi
    rm -f "$MON_OUT" 2>/dev/null
    rm -f "$LOCK/pid" 2>/dev/null
    rmdir "$LOCK" 2>/dev/null
}

# Find a running lastModeSvc and the token after -f. Scans /proc/*/cmdline
# because nothing in the static tree references lastModeSvc; if it is not
# running this returns 1 and the run logs its absence instead.
find_lastmode() {
    LASTMODE_PID=''
    LASTMODE_FILE=''
    for _d in /proc/[0-9]*; do
        [ -r "$_d/cmdline" ] || continue
        _line=$(tr '\0' ' ' < "$_d/cmdline" 2>/dev/null) || continue
        case $_line in
            *"$LASTMODE_NAME"*)
                LASTMODE_PID=${_d#/proc/}
                _prev=
                # shellcheck disable=SC2086
                for _t in $_line; do
                    if [ "$_prev" = "-f" ]; then
                        LASTMODE_FILE=$_t
                        break
                    fi
                    _prev=$_t
                done
                return 0
                ;;
        esac
    done
    return 1
}

# size and md5 of a file, as a single stable token pair
digest() {
    _sz=$(wc -c < "$1" 2>/dev/null | tr -d ' ')
    _md=$(md5sum "$1" 2>/dev/null | awk '{ print $1 }')
    echo "size=${_sz:-?} md5=${_md:-none}"
}

start_dbus_mon() {
    if ! have dbus-monitor; then
        say "SKIP DBUS_MON (no dbus-monitor)"
        return 1
    fi
    if [ ! -S "$SVC_BUS" ]; then
        say "SKIP DBUS_MON (no $SVC_BUS)"
        return 1
    fi
    rm -f "$MON_OUT" 2>/dev/null
    dbus-monitor --address "unix:path=$SVC_BUS" \
        "type='signal',interface='com.jci.vbs.vdt'" \
        "type='signal',interface='com.jci.vbs.bcm'" \
        > "$MON_OUT" 2>/dev/null &
    DBUS_MON_PID=$!
    say "DBUS_MON started pid=$DBUS_MON_PID"
}

# Stop the listener and tally the members it saw. The raw dump is deleted;
# only deduplicated counts reach the log.
collect_dbus() {
    [ -n "$DBUS_MON_PID" ] || return 0
    kill "$DBUS_MON_PID" 2>/dev/null
    wait "$DBUS_MON_PID" 2>/dev/null
    DBUS_MON_PID=
    _n=$(grep -oE 'interface=[^;]+; member=[A-Za-z0-9_]+' "$MON_OUT" 2>/dev/null |
        sort | uniq -c | sort -rn)
    if [ -n "$_n" ]; then
        printf '%s\n' "$_n" | while IFS= read -r _row; do
            say "DBUS_SIG $_row"
        done
    else
        say "DBUS_SIG none seen"
    fi
    rm -f "$MON_OUT" 2>/dev/null
}

BOOT=$(up_now)

acquire || exit 0
trap 'release' EXIT
trap 'release; exit 0' INT TERM HUP

say "BOOT"

start_dbus_mon || true

# Locate lastModeSvc once; if it is not up yet it may still appear, so the
# window loop re-checks until found.
LASTMODE_PID=''
LASTMODE_FILE=''
find_lastmode || say "SKIP LASTMODE_SVC (not running yet)"
[ -n "$LASTMODE_FILE" ] &&
    say "FOUND LASTMODE_SVC pid=$LASTMODE_PID file=$LASTMODE_FILE"

AUDIO_START_OK=0
READY_SEEN=' '
_last_digest=

i=0
while [ "$i" -lt "$WINDOW" ]; do
    E=$(elapsed "$BOOT")

    if [ "$AUDIO_START_OK" = 0 ] && [ -e "$AUDIO_START" ]; then
        AUDIO_START_OK=1
        say "EVENT AUDIO_START elapsed=$E"
    fi

    for _f in $READY_FLAGS; do
        case $READY_SEEN in
            *" $_f "*) continue ;;
        esac
        if [ -e "$READY_DIR/$_f" ]; then
            READY_SEEN="$READY_SEEN$_f "
            say "EVENT READY $_f elapsed=$E"
        fi
    done

    if [ -z "$LASTMODE_PID" ]; then
        if find_lastmode; then
            say "FOUND LASTMODE_SVC pid=$LASTMODE_PID file=$LASTMODE_FILE elapsed=$E"
            [ -n "$LASTMODE_FILE" ] && _last_digest=$(digest "$LASTMODE_FILE")
        fi
    elif [ -n "$LASTMODE_FILE" ] && [ -f "$LASTMODE_FILE" ]; then
        _d=$(digest "$LASTMODE_FILE")
        if [ -n "$_last_digest" ] && [ "$_d" != "$_last_digest" ]; then
            say "EVENT LASTMODE_CHANGE elapsed=$E $_d"
        fi
        _last_digest=$_d
    fi

    i=$((i + 1))
    sleep 1
done

# Steady snapshot once boot traffic settles, bounded by STEADY from BOOT.
_to=$(awk -v n="$(up_now)" -v s="$BOOT" -v t="$STEADY" \
    'BEGIN { r = t - (n - s); if (r < 0) r = 0; printf "%.0f", r }')
[ "$_to" -gt 0 ] 2>/dev/null && sleep "$_to"

E=$(elapsed "$BOOT")
say "STEADY"
[ -e "$AUDIO_START" ] && say "SNAPSHOT AUDIO_START"
for _f in $READY_FLAGS; do
    [ -e "$READY_DIR/$_f" ] && say "SNAPSHOT READY $_f"
done
if [ -n "$LASTMODE_PID" ]; then
    if [ -n "$LASTMODE_FILE" ] && [ -f "$LASTMODE_FILE" ]; then
        say "SNAPSHOT LASTMODE_SVC pid=$LASTMODE_PID file=$LASTMODE_FILE $(digest "$LASTMODE_FILE")"
    else
        say "SNAPSHOT LASTMODE_SVC pid=$LASTMODE_PID (no persistence file seen)"
    fi
else
    say "SNAPSHOT LASTMODE_ABSENT (lastModeSvc never ran in the window)"
fi
[ -e "$VBS_HANDLER" ] && say "SNAPSHOT VBS_HANDLER present"
[ -e "$VBS_HANDLER" ] || say "SNAPSHOT VBS_HANDLER absent"
collect_dbus
say "DONE"
