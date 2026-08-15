#!/bin/bash
# kali_upgrade.sh - Indicate when a newer Kali Linux release is available.
# Designed for use with genmon. Prints nothing when the system is up to date
# or when the check cannot be performed.
#
# The upstream release version is read from the apt package index
# (kali-linux-core). This uses only local data and does not scrape the
# Kali website, so it cannot be broken by a change in the site layout.

# Verify that we are running on Kali Linux.
if [ -f /etc/os-release ]; then
    . /etc/os-release
    [ "$ID" != "kali" ] && exit 0
    current_version="$VERSION_ID"
else
    exit 0
fi

# Read the release version of the newest available kali-linux-core package.
latest_version=$(apt show kali-linux-core 2>/dev/null \
  | awk -F'[: ]+' '/^Version:/{print $2; exit}')

# If the version could not be determined, show nothing.
[ -z "$latest_version" ] && exit 0

# Compare release series only: the kali-linux-core package version may carry
# an in-release point bump (e.g. 2026.3.2), which is not a new release.
latest_release=${latest_version%.*}

# Notify only when a newer release is available.
if [ "$latest_release" != "$current_version" ]; then
    printf "<icon>update-high</icon> "
    printf "<txt>Kali %s available (%s)</txt>" "$latest_release" "$current_version"
else
    printf "<txt></txt>"
fi

exit 0