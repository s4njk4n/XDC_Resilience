# XDC_Resilience

## Script creation:
- Create the internet monitoring script
```
sudo nano /usr/local/bin/monitor_internet.sh
```
- Add relevant script data as follows:
```
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
```

Then create the post-reboot notification script:
```
sudo nano /usr/local/bin/post_reboot_notify.sh
```
- Add relevant script content as follows:
```
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
```

- Make sure to customise the NTFY_TOPIC and NTFY_MESSAGE then save

- Make the scripts executable and make sure curl is installed so notifications can be sent
```
sudo chmod +x /usr/local/bin/monitor_internet.sh
sudo chmod +x /usr/local/bin/post_reboot_notify.sh
sudo apt update && sudo apt install curl -y
```

## Testing

To test the internet monitoring script:
Comment out the `/sbin/reboot`
Then run multiple times to reach check threshhold
Check if `/var/log/reboot_connectivity.flag` is created

To test the notification script:
Manually create the flag with 
```
sudo touch /var/log/reboot_connectivity.flag
```
Then run
```
sudo /usr/local/bin/post_reboot_notify.sh
```
Verify you receive the ntfy notification

## Update cron jobs

To edit the root crontab, run
```
sudo crontab -e
```
Add the monitoring line:
```
* * * * * /usr/local/bin/monitor_internet.sh
```
Add the post-reboot line: 
```
@reboot /usr/local/bin/post_reboot_notify.sh
```
Save and exit. The @reboot runs the script once after each system boot.

## Verify everything
Check cron logs:
```
sudo tail -f /var/log/syslog | grep CRON
```
To fully test, simulate a failure scenario: Disconnect internet, wait for the script to trigger reboot (after ~2-3 minutes with default threshold). After reboot, check if you receive the ntfy notification (system must regain connectivity post-boot for curl to work).
If the reboot was not due to this script (e.g., manual reboot), no notification is sent, as the flag won't exist.

