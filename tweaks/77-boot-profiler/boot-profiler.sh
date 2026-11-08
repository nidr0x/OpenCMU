#!/bin/sh
# OpenCMU: record how boot reaches its readiness milestones.
#
# A read-only profiler. It polls a short list of artifacts, writes one line
# per milestone into its log, and ends with a steady-state snapshot and a
# DONE line. It starts nothing, stops nothing and edits nothing, so the only
# load it puts on the unit is a few cheap process probes per second during
# its window.
#
# Milestones, in stock order as far as the evidence shows:
#   HMI_UP        the HMI process (stock name jciMMUI) is running
#   WIFI_MODULES  wlan0 exists, meaning the wireless modules are loaded
#   HOSTAPD_UP    the stock access-point hostapd is running
#   WIFI_READY    the stock readiness flag /var/run/start_wifi_ready exists
#   CARPLAY_UP    an ESTABLISHED CarPlay session is visible to netstat
#
# Installed into /data/opencmu/boot.d and started by the boot hook from tweak
# 60, so on a real boot its BOOT line lands right after stage_gap2. It can
# also be run by hand from SSH; then it simply reports current state.

set -u

LOG=${OPENCMU_PROFILER_LOG:-/data/opencmu/logs/boot-profiler.log}
UPFILE=${OPENCMU_PROFILER_UPTIME:-/proc/uptime}
WLAN=${OPENCMU_PROFILER_WLAN:-/sys/class/net/wlan0}
READY_FLAG=${OPENCMU_PROFILER_READY_FLAG:-/var/run/start_wifi_ready}
HMI_PROC=${OPENCMU_PROFILER_HMI_PROC:-jciMMUI}
CARPLAY_HOSTS=${OPENCMU_PROFILER_CARPLAY_HOSTS:-'192.168.53. 192.168.100.'}
CARPLAY_PORTS=${OPENCMU_PROFILER_CARPLAY_PORTS:-':7000 :7100'}
WINDOW=${OPENCMU_PROFILER_WINDOW:-120}
STEADY=${OPENCMU_PROFILER_STEADY:-45}
LOCK=${OPENCMU_PROFILER_LOCK:-/tmp/opencmu-boot-profiler.lock}
MAXLOG=131072

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

running() {
    if have pidof; then
        pidof "$1" >/dev/null 2>&1
    elif have ps; then
        # shellcheck disable=SC2009
        ps 2>/dev/null | grep -v grep | grep -qw "$1"
    else
        return 2
    fi
}

# Any TCP line that carries one of the CarPlay ranges and one of its ports as
# ESTABLISHED counts. The ranges and ports are stock facts: the phone joins
# the unit over 192.168.53.0/24 or 192.168.100.0/24 and CarPlay lives on
# 7000/7100.
carplay_up() {
    have netstat || return 2
    netstat -tn 2>/dev/null | grep -F ESTABLISHED |
        while IFS= read -r _line; do
            for _h in $CARPLAY_HOSTS; do
                case $_line in
                    *"$_h"*)
                        for _p in $CARPLAY_PORTS; do
                            case $_line in *"$_p"*) exit 0 ;; esac
                        done
                        ;;
                esac
            done
        done
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
        say "another profiler run is active (pid $_old); exiting"
        return 1
    fi
    rm -f "$LOCK/pid" 2>/dev/null
    rmdir "$LOCK" 2>/dev/null
    mkdir "$LOCK" 2>/dev/null || { say "cannot take $LOCK"; return 1; }
    printf '%s\n' "$$" > "$LOCK/pid" 2>/dev/null || true
    return 0
}

release() {
    rm -f "$LOCK/pid" 2>/dev/null
    rmdir "$LOCK" 2>/dev/null
}

BOOT=$(up_now)

acquire || exit 0
trap 'release' EXIT
trap 'release; exit 0' INT TERM HUP

say "BOOT"

HMI_OK=0 WIFI_MOD_OK=0 HOSTAPD_OK=0 WIFI_READY_OK=0 CARPLAY_OK=0

# Tools missing now cannot appear during the window; log the affected
# milestones as skipped so the run does not spin for the full window.
if ! (have pidof || have ps); then
    HMI_OK=1
    HOSTAPD_OK=1
    say "SKIP HMI_UP HOSTAPD_UP (no process probe tool)"
fi
if ! have netstat; then
    CARPLAY_OK=1
    say "SKIP CARPLAY_UP (no netstat)"
fi

probe() {
    E=$(elapsed "$BOOT")
    if [ "$HMI_OK" = 0 ]; then
        if running "$HMI_PROC" 2>/dev/null; then
            HMI_OK=1
            say "EVENT HMI_UP elapsed=$E"
        fi
    fi
    if [ "$WIFI_MOD_OK" = 0 ]; then
        if [ -e "$WLAN" ]; then
            WIFI_MOD_OK=1
            say "EVENT WIFI_MODULES elapsed=$E"
        fi
    fi
    if [ "$HOSTAPD_OK" = 0 ]; then
        if running hostapd 2>/dev/null; then
            HOSTAPD_OK=1
            say "EVENT HOSTAPD_UP elapsed=$E"
        fi
    fi
    if [ "$WIFI_READY_OK" = 0 ]; then
        if [ -e "$READY_FLAG" ]; then
            WIFI_READY_OK=1
            say "EVENT WIFI_READY elapsed=$E"
        fi
    fi
    if [ "$CARPLAY_OK" = 0 ]; then
        if carplay_up 2>/dev/null; then
            CARPLAY_OK=1
            say "EVENT CARPLAY_UP elapsed=$E"
        fi
    fi
    [ "$HMI_OK$WIFI_MOD_OK$HOSTAPD_OK$WIFI_READY_OK$CARPLAY_OK" = "11111" ] &&
        return 0
    return 1
}

i=0
while [ "$i" -lt "$WINDOW" ]; do
    probe && break
    i=$((i + 1))
    sleep 1
done

# Steady snapshot once boot traffic settles, bounded by STEADY from BOOT.
_to=$(awk -v n="$(up_now)" -v s="$BOOT" -v t="$STEADY" \
    'BEGIN { r = t - (n - s); if (r < 0) r = 0; printf "%.0f", r }')
[ "$_to" -gt 0 ] 2>/dev/null && sleep "$_to"

E=$(elapsed "$BOOT")
say "STEADY"
running "$HMI_PROC" 2>/dev/null && say "SNAPSHOT HMI_UP"
[ -e "$WLAN" ] && say "SNAPSHOT WIFI_UP"
running hostapd 2>/dev/null && say "SNAPSHOT AP_UP"
[ -e "$READY_FLAG" ] && say "SNAPSHOT READY_FLAG"
if have netstat && netstat -tn 2>/dev/null | grep -qF ESTABLISHED; then
    say "SNAPSHOT TCP_ESTABLISHED"
fi
say "DONE"
