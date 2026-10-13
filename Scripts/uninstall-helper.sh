#!/bin/bash
# Removes everything install-helper.sh created and restores system sleep.
# Run with:  sudo ./Scripts/uninstall-helper.sh
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    echo "error: run with sudo: sudo $0" >&2
    exit 1
fi

DAEMON_LABEL="com.wakemate.watchdog"

/usr/bin/pmset -a disablesleep 0 && echo "✓ System sleep restored"

if /bin/launchctl print "system/$DAEMON_LABEL" >/dev/null 2>&1; then
    /bin/launchctl bootout "system/$DAEMON_LABEL" || true
fi
/bin/rm -f "/Library/LaunchDaemons/${DAEMON_LABEL}.plist"
/bin/rm -f "/Library/PrivilegedHelperTools/${DAEMON_LABEL}.sh"
echo "✓ Removed watchdog LaunchDaemon"

/bin/rm -f /etc/sudoers.d/wakemate
/usr/sbin/visudo -c >/dev/null
echo "✓ Removed /etc/sudoers.d/wakemate"
