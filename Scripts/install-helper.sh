#!/bin/bash
# Installs WakeMate's privileged pieces for personal (non-notarized) use:
#   1. /etc/sudoers.d/wakemate  — lets ONLY the invoking user run EXACTLY
#      `/usr/bin/pmset -a disablesleep 1` and `... 0` without a password.
#   2. A root LaunchDaemon watchdog that restores sleep if the app dies.
#
# Run with:  sudo ./Scripts/install-helper.sh
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    echo "error: run with sudo: sudo $0" >&2
    exit 1
fi

TARGET_USER="${SUDO_USER:-}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    echo "error: run via sudo from your normal user account (SUDO_USER is unset)" >&2
    exit 1
fi
if [[ ! "$TARGET_USER" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "error: unexpected characters in username '$TARGET_USER'" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_HOME="$(/usr/bin/dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory | /usr/bin/awk '{print $2}')"
LEASE_FILE="$USER_HOME/Library/Application Support/WakeMate/sleep.lease"

SUDOERS_FILE="/etc/sudoers.d/wakemate"
WATCHDOG_DST="/Library/PrivilegedHelperTools/com.wakemate.watchdog.sh"
DAEMON_LABEL="com.wakemate.watchdog"
DAEMON_PLIST="/Library/LaunchDaemons/${DAEMON_LABEL}.plist"

# --- 1. sudoers rule (validated before it goes live) -------------------------
TMP_SUDOERS="$(/usr/bin/mktemp)"
trap '/bin/rm -f "$TMP_SUDOERS"' EXIT
cat > "$TMP_SUDOERS" <<EOF
# Managed by WakeMate install-helper.sh — remove with uninstall-helper.sh
$TARGET_USER ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
EOF
/usr/sbin/visudo -cf "$TMP_SUDOERS" >/dev/null
/usr/bin/install -m 0440 -o root -g wheel "$TMP_SUDOERS" "$SUDOERS_FILE"
/usr/sbin/visudo -c >/dev/null
echo "✓ Installed $SUDOERS_FILE"

# --- 2. watchdog LaunchDaemon ------------------------------------------------
/bin/mkdir -p /Library/PrivilegedHelperTools
/usr/bin/install -m 0755 -o root -g wheel "$SCRIPT_DIR/wakemate-watchdog.sh" "$WATCHDOG_DST"

if /bin/launchctl print "system/$DAEMON_LABEL" >/dev/null 2>&1; then
    /bin/launchctl bootout "system/$DAEMON_LABEL" || true
fi

cat > "$DAEMON_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${DAEMON_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${WATCHDOG_DST}</string>
        <string>${LEASE_FILE}</string>
    </array>
    <key>StartInterval</key>
    <integer>60</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/var/log/wakemate-watchdog.log</string>
</dict>
</plist>
EOF
/usr/sbin/chown root:wheel "$DAEMON_PLIST"
/bin/chmod 0644 "$DAEMON_PLIST"
/usr/bin/plutil -lint "$DAEMON_PLIST" >/dev/null
/bin/launchctl bootstrap system "$DAEMON_PLIST"
echo "✓ Installed watchdog LaunchDaemon ($DAEMON_LABEL)"

# --- 3. verify as the target user -------------------------------------------
if /usr/bin/sudo -u "$TARGET_USER" /usr/bin/sudo -n -l /usr/bin/pmset -a disablesleep 0 >/dev/null 2>&1; then
    echo "✓ Verified: $TARGET_USER can toggle disablesleep without a password"
else
    echo "warning: verification failed — check $SUDOERS_FILE" >&2
    exit 1
fi
