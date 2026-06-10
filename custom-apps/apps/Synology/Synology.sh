#!/bin/bash
CONFIG="${MACUSERLAND_SYNOLOGY_CONFIG:-$HOME/.config/macuserland/synology.conf}"
HOST=""
SHARE="home"
TITLE="Synology"

notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"$TITLE\""; }

if [ -f "$CONFIG" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG"
fi

if [ -z "$HOST" ]; then
    notify "Synology config missing"
    exit 1
fi

if [ -x /usr/local/bin/tailscale ]; then
    TAILSCALE=/usr/local/bin/tailscale
elif [ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]; then
    TAILSCALE=/Applications/Tailscale.app/Contents/MacOS/Tailscale
else
    TAILSCALE=
fi

if /sbin/mount | /usr/bin/grep -q "/Volumes/$SHARE"; then
    notify "Disconnecting..."
    if /usr/sbin/diskutil unmount "/Volumes/$SHARE" &>/dev/null; then
        notify "Disconnected"
    else
        notify "Failed to disconnect"
    fi
elif [ -z "$TAILSCALE" ] || ! "$TAILSCALE" status &>/dev/null; then
    notify "Tailscale is down"
elif ! /sbin/ping -c 1 -t 3 "$HOST" &>/dev/null; then
    notify "Synology unreachable"
else
    notify "Connecting..."
    if /usr/bin/osascript -e "tell application \"Finder\" to mount volume \"smb://$HOST/$SHARE\"" 2>/dev/null; then
        notify "Connected"
    else
        notify "Mount failed"
    fi
fi
