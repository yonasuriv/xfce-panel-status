#!/bin/bash
# kali_upgrade.sh - Compare your installed Kali version with the latest available release.
# Designed for use with genmon. On error, prints "?".
# Note: Kali is a rolling release, so use this only if you wish to compare against the website's published version.

# Get the current installed version from /etc/os-release.
if [ -f /etc/os-release ]; then
  . /etc/os-release
  [ "$ID" != "kali" ] && exit 0
  current_version="$VERSION_ID"
else
  exit 0
fi

# Fetch the official Kali download page.
download_page=$(curl -s https://www.kali.org/get-kali/) || exit 0

# Parse the page for the latest version.
# This regex assumes the page contains a string like "Kali Linux 2022.4" (adjust if needed).
latest_version=$(echo "$download_page" | grep -oP 'Kali Linux\s+\K[0-9]+\.[0-9]+' | head -n 1)
[ -z "$latest_version" ] && exit 0

# Determine status.
if [ "$current_version" != "$latest_version" ]; then
  printf "<icon>update-high</icon>"
  printf "<txt> Kali $latest_version available</txt>"
else
  printf "<txt></txt>"
fi

exit 0
