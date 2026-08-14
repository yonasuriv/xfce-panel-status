#!/bin/bash
# kali_updates.sh - Check the number of available package updates on Kali Linux.
# Designed for use with genmon. On error or when no updates exist, prints nothing.
# Requires passwordless sudo for apt-get update.

# Verify that we are running on Kali Linux.
if [ -f /etc/os-release ]; then
    . /etc/os-release
    [ "$ID" != "kali" ] && exit 0
else
    exit 0
fi

# Update the package cache quietly using sudo -n (no password prompt).
sudo -n apt-get update -qq >/dev/null 2>&1

# List upgradable packages and remove the header line.
updates=$(apt list --upgradable 2>/dev/null | sed '1d')
count=$(echo "$updates" | grep -c .)

# Print output only if the count is greater than 0.
if [ "$count" -gt 0 ]; then
    if [ "$count" -eq 1 ]; then
        printf "<icon>update-low</icon> "
        printf "<txt> $count update available</txt>"
    else
        printf "<icon>update-low</icon> "
        printf "<txt> $count updates available</txt>"
    fi
else
    printf "<txt></txt>"
fi

exit 0
