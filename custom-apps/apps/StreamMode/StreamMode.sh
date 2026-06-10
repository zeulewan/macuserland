#!/bin/bash

# Check if daemon is loaded (streaming mode ON)
if /usr/bin/sudo /bin/launchctl list | /usr/bin/grep -q "com.local.awdl.disable"; then
    # Streaming ON -> Turn OFF (unload daemons, enable interfaces)
    /usr/bin/sudo /bin/launchctl unload /Library/LaunchDaemons/com.local.awdl.disable.plist 2>/dev/null
    /usr/bin/sudo /bin/launchctl unload /Library/LaunchDaemons/com.local.llw.disable.plist 2>/dev/null
    /usr/bin/sudo /sbin/ifconfig awdl0 up
    /usr/bin/sudo /sbin/ifconfig llw0 up
    MSG="OFF"
else
    # Streaming OFF -> Turn ON (load daemons)
    /usr/bin/sudo /bin/launchctl load /Library/LaunchDaemons/com.local.awdl.disable.plist 2>/dev/null
    /usr/bin/sudo /bin/launchctl load /Library/LaunchDaemons/com.local.llw.disable.plist 2>/dev/null
    MSG="ON"
fi

/usr/bin/osascript -e "display notification \"$MSG\" with title \"Stream\""
