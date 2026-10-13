#!/bin/bash
# WakeMate failsafe watchdog — runs as root via LaunchDaemon every 60 seconds.
#
# Purpose: guarantee `pmset -a disablesleep 0` is restored even if WakeMate is
# SIGKILLed, crashes, or hangs (cases where in-process handlers cannot run).
#
# Contract with the app (see SleepLeaseStore in SleepController.swift):
#   The app writes a lease file *before* disabling sleep and deletes it *after*
#   restoring sleep. While a session runs, the app refreshes `heartbeat` every 30s.
#   Lease format (key=value, epoch seconds, expires=0 means indefinite):
#       pid=1234
#       expires=1760380000
#       heartbeat=1760376400
#
# Sleep is restored when SleepDisabled=1 and ANY of the following holds:
#   - the lease is missing or malformed
#   - the lease's pid is not a running WakeMate process
#   - the heartbeat is older than HEARTBEAT_TIMEOUT seconds
#   - the session deadline has passed (plus a grace period)
#
# Usage: wakemate-watchdog.sh /path/to/sleep.lease
set -u

readonly PMSET="/usr/bin/pmset"
readonly HEARTBEAT_TIMEOUT=120
readonly EXPIRY_GRACE=60
readonly LEASE_FILE="${1:-}"

log() { /usr/bin/logger -t wakemate-watchdog "$*"; }

restore_sleep() {
    local reason="$1"
    if "$PMSET" -a disablesleep 0; then
        log "restored system sleep: ${reason}"
        [[ -n "$LEASE_FILE" ]] && /bin/rm -f "$LEASE_FILE"
    else
        log "ERROR: failed to restore system sleep (${reason})"
        exit 1
    fi
}

sleep_disabled="$("$PMSET" -g | /usr/bin/awk '/SleepDisabled/ { print $2; exit }')"
[[ "$sleep_disabled" == "1" ]] || exit 0

if [[ -z "$LEASE_FILE" || ! -f "$LEASE_FILE" ]]; then
    restore_sleep "SleepDisabled=1 with no active WakeMate lease"
    exit 0
fi

read_key() { /usr/bin/awk -F= -v k="$1" '$1 == k { print $2; exit }' "$LEASE_FILE"; }
pid="$(read_key pid)"
expires="$(read_key expires)"
heartbeat="$(read_key heartbeat)"
now="$(/bin/date +%s)"

is_int() { [[ "$1" =~ ^[0-9]+$ ]]; }
if ! is_int "$pid" || ! is_int "$expires" || ! is_int "$heartbeat"; then
    restore_sleep "malformed lease"
    exit 0
fi

if ! /bin/kill -0 "$pid" 2>/dev/null; then
    restore_sleep "owner pid ${pid} is not running"
    exit 0
fi

if ! /bin/ps -p "$pid" -o comm= | /usr/bin/grep -q "WakeMate"; then
    restore_sleep "pid ${pid} is not WakeMate"
    exit 0
fi

if (( now - heartbeat > HEARTBEAT_TIMEOUT )); then
    restore_sleep "heartbeat stale by $(( now - heartbeat ))s (app hung?)"
    exit 0
fi

if (( expires > 0 && now > expires + EXPIRY_GRACE )); then
    restore_sleep "session deadline passed"
    exit 0
fi

exit 0
