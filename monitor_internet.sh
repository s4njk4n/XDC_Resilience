#!/bin/bash

# Script to monitor internet connectivity and reboot if it fails for a specified period.
# Checks by pinging two reliable addresses: 8.8.8.8 (Google DNS) and 1.1.1.1 (Cloudflare DNS).
# If both pings fail, it increments a failure counter.
# If the counter reaches the threshold (e.g., 3 consecutive failures), it reboots the system.
# Reset the counter on success.
# Intended to be run every 1 minute via cron.
# Failure threshold of 3 means at least 2 minutes of confirmed downtime (since checks are 1 min apart).

# Configuration
PING_ADDR1="8.8.8.8"
PING_ADDR2="1.1.1.1"
PING_COUNT=1          # Number of pings to send per address
PING_TIMEOUT=5        # Timeout in seconds for each ping
FAILURE_FILE="/tmp/internet_failure_count"
FAILURE_THRESHOLD=3   # Number of consecutive failures before reboot (adjust as needed; 3 = ~2-3 min downtime)
REBOOT_FLAG="/var/log/reboot_connectivity.flag"  # Persistent flag to trigger post-reboot notification

# Function to check if internet is up by pinging an address
check_ping() {
    local addr=$1
    ping -c $PING_COUNT -W $PING_TIMEOUT $addr > /dev/null 2>&1
    return $?
}

# Read current failure count or initialize to 0
if [ -f "$FAILURE_FILE" ]; then
    failure_count=$(cat "$FAILURE_FILE")
else
    failure_count=0
fi

# Check connectivity
if check_ping $PING_ADDR1 || check_ping $PING_ADDR2; then
    # Internet is up, reset counter
    echo 0 > "$FAILURE_FILE"
else
    # Both pings failed, increment counter
    ((failure_count++))
    echo $failure_count > "$FAILURE_FILE"
    
    # If threshold reached, prepare for reboot
    if [ $failure_count -ge $FAILURE_THRESHOLD ]; then
        # Log the reboot action (optional, for debugging)
        logger "Internet connectivity failed for $FAILURE_THRESHOLD checks. Rebooting system."
        # Set flag for post-reboot notification
        touch "$REBOOT_FLAG"
        # Reboot the system
        /sbin/reboot
    fi
fi
