#!/bin/bash

# Script to send ntfy.sh notification after reboot if triggered by connectivity issue.
# Runs on boot via cron @reboot.
# Checks for flag, waits for internet connectivity, sends message if present, then deletes flag.

# Configuration
REBOOT_FLAG="/var/log/reboot_connectivity.flag"
NTFY_TOPIC="yourtopic"  # Replace with your specific ntfy.sh topic (e.g., "xdc-masternode-alerts")
NTFY_MESSAGE="System has rebooted due to internet connectivity issue."  # Customize message as needed
NTFY_URL="https://ntfy.sh/$NTFY_TOPIC"
PING_ADDR1="8.8.8.8"   # Google DNS
PING_ADDR2="1.1.1.1"   # Cloudflare DNS
PING_COUNT=1           # Number of pings to send per address
PING_TIMEOUT=5         # Timeout in seconds for each ping
MAX_WAIT=300           # Max wait time in seconds (5 minutes) before giving up
WAIT_INTERVAL=10       # Check every 10 seconds

# Function to check if internet is up by pinging an address
check_ping() {
    local addr=$1
    ping -c $PING_COUNT -W $PING_TIMEOUT $addr > /dev/null 2>&1
    return $?
}

# Check for flag
if [ -f "$REBOOT_FLAG" ]; then
    # Wait for connectivity with timeout
    waited=0
    while [ $waited -lt $MAX_WAIT ]; do
        if check_ping $PING_ADDR1 || check_ping $PING_ADDR2; then
            # Internet is up, send notification
            curl -s -d "$NTFY_MESSAGE" "$NTFY_URL"
            rm "$REBOOT_FLAG"
            exit 0
        fi
        sleep $WAIT_INTERVAL
        ((waited += WAIT_INTERVAL))
    done
    # If timed out, log (optional) but don't send; delete flag to avoid stale state
    logger "Post-reboot notification timed out waiting for connectivity."
    rm "$REBOOT_FLAG"
fi
