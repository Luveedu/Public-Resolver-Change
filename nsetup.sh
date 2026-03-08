#!/bin/bash

# Path to the resolv.conf file
RESOLV_CONF="/etc/resolv.conf"

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root (use sudo)."
   exit 1
fi

# Function to update DNS
set_dns() {
    local provider=$1
    local dns1=$2
    local dns2=$3

    echo "Configuring DNS for: $provider..."
    
    # Backup current resolv.conf
    cp $RESOLV_CONF "${RESOLV_CONF}.bak"

    # Overwrite with new nameservers
    echo "nameserver $dns1" > $RESOLV_CONF
    echo "nameserver $dns2" >> $RESOLV_CONF

    echo "Successfully updated to $provider ($dns1, $dns2)"
}

# Logic to handle flags
case "$1" in
    --google)
        set_dns "Google" "8.8.8.8" "8.8.4.4"
        ;;
    --opendns)
        set_dns "OpenDNS" "208.67.222.222" "208.67.220.220"
        ;;
    *)
        # Default to Cloudflare if no flag or unknown flag is used
        set_dns "Cloudflare" "1.1.1.1" "1.0.0.1"
        ;;
esac