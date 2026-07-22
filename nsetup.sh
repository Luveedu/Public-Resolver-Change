#!/bin/bash

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "Error: Please run this script as root (use sudo)."
   exit 1
fi

echo "=========================================="
echo "    Persistent DNS Configuration Tool     "
echo "=========================================="
echo ""

# ----------------------------------------
# 1. Method Selection
# ----------------------------------------
echo "1. Which method do you want to use?"
echo "   A - Native OS (systemd-resolved) [Recommended]"
echo "   B - Lock System (chattr immutable)"
while true; do
    read -p "   Select an option (A/B): " METHOD_CHOICE
    # Convert input to uppercase
    METHOD_CHOICE=${METHOD_CHOICE^^}
    
    case "$METHOD_CHOICE" in
        A) 
            METHOD_NAME="Native OS"
            break 
            ;;
        B) 
            METHOD_NAME="Lock System"
            break 
            ;;
        *) 
            echo "   Invalid input. Please enter A or B." 
            ;;
    esac
done
echo ""

# ----------------------------------------
# 2. DNS Selection
# ----------------------------------------
echo "2. Which Public DNS?"
echo "   1 - Google (8.8.8.8, 8.8.4.4)"
echo "   2 - Cloudflare (1.1.1.1, 1.0.0.1)"
echo "   3 - OpenDNS (208.67.222.222, 208.67.220.220)"
echo "   4 - Quad9 (9.9.9.9, 149.112.112.112)"
echo "   5 - ControlD (76.76.2.0, 76.76.10.0)"
echo "   6 - GCore DNS (95.85.95.85, 2.56.220.2)"
while true; do
    read -p "   Select a DNS provider (1-6): " DNS_CHOICE
    case "$DNS_CHOICE" in
        1) DNS_NAME="Google"; DNS1="8.8.8.8"; DNS2="8.8.4.4"; DNS_IPV6="2001:4860:4860::8888 2001:4860:4860::8844"; break ;;
        2) DNS_NAME="Cloudflare"; DNS1="1.1.1.1"; DNS2="1.0.0.1"; DNS_IPV6="2606:4700:4700::1111 2606:4700:4700::1001"; break ;;
        3) DNS_NAME="OpenDNS"; DNS1="208.67.222.222"; DNS2="208.67.220.220"; DNS_IPV6="2620:119:35::35 2620:119:53::53"; break ;;
        4) DNS_NAME="Quad9"; DNS1="9.9.9.9"; DNS2="149.112.112.112"; DNS_IPV6="2620:fe::fe 2620:fe::9"; break ;;
        5) DNS_NAME="ControlD"; DNS1="76.76.2.0"; DNS2="76.76.10.0"; DNS_IPV6="2606:1a40::2 2606:1a40::10"; break ;;
        6) DNS_NAME="GCore DNS"; DNS1="95.85.95.85"; DNS2="2.56.220.2"; DNS_IPV6="2a03:90c0:56::1 2a03:90c0:220::1"; break ;;
        *) echo "   Invalid input. Please enter a number from 1 to 6." ;;
    esac
done
echo ""

# ----------------------------------------
# 3. Confirmation
# ----------------------------------------
echo "3. Are you ready to continue with $METHOD_NAME & $DNS_NAME?"
while true; do
    read -p "   (Y/N): " CONFIRM
    CONFIRM=${CONFIRM^^}
    
    case "$CONFIRM" in
        Y|YES) 
            break 
            ;;
        N|NO) 
            echo "Operation cancelled by user. Exiting..."
            exit 0 
            ;;
        *) 
            echo "   Please enter Y or N." 
            ;;
    esac
done
echo ""

# ----------------------------------------
# Execution
# ----------------------------------------
echo "Applying configurations..."

if [[ "$METHOD_CHOICE" == "A" ]]; then
    # METHOD A: Native OS (systemd-resolved)
    
    # Check if systemd-resolved is available
    if ! command -v systemctl &> /dev/null || ! systemctl list-unit-files | grep -q systemd-resolved; then
        echo "[-] Error: systemd-resolved is not available on this system."
        echo "[-] Please use Method B instead or install systemd-resolved."
        exit 1
    fi
    
    echo "[+] Backing up current systemd-resolved configuration..."
    if [[ -f /etc/systemd/resolved.conf ]]; then
        cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    echo "[+] Creating drop-in configuration directory for systemd-resolved..."
    mkdir -p /etc/systemd/resolved.conf.d
    
    echo "[+] Writing $DNS_NAME DNS records..."
    # Include both IPv4 and IPv6 DNS servers
    cat <<EOF > /etc/systemd/resolved.conf.d/custom-dns.conf
[Resolve]
DNS=$DNS1 $DNS2 $DNS_IPV6
FallbackDNS=1.1.1.1 8.8.8.8
# Uncomment the following line to enable DNSSEC validation
#DNSSEC=yes
# Uncomment for DNS over TLS
#DNSOverTLS=yes
EOF

    echo "[+] Restarting systemd-resolved service..."
    systemctl restart systemd-resolved
    
    # Wait a moment for the service to start
    sleep 2
    
    # Verify success
    if systemctl is-active --quiet systemd-resolved; then
        echo "[+] Success! Native OS DNS has been updated to $DNS_NAME."
        echo "[+] Current DNS servers:"
        resolvectl status | grep "DNS Servers" || systemd-resolve --status | grep "DNS Servers"
    else
        echo "[-] Error: systemd-resolved service failed to start."
        echo "[-] Restoring backup if available..."
        if [[ -f /etc/systemd/resolved.conf.backup.* ]]; then
            cp /etc/systemd/resolved.conf.backup.* /etc/systemd/resolved.conf 2>/dev/null
        fi
        echo "[-] Please check your system logs with: journalctl -xe"
        exit 1
    fi

elif [[ "$METHOD_CHOICE" == "B" ]]; then
    # METHOD B: Lock System (chattr)
    
    # Check if chattr is available
    if ! command -v chattr &> /dev/null; then
        echo "[-] Error: chattr command not found. Please install e2fsprogs package."
        exit 1
    fi
    
    echo "[+] Checking for existing locks on /etc/resolv.conf..."
    # Suppress error if not currently locked or doesn't exist
    chattr -i /etc/resolv.conf 2>/dev/null
    
    # Create backup if file exists
    if [[ -f "/etc/resolv.conf" ]]; then
        echo "[+] Backing up existing /etc/resolv.conf..."
        cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # If it is a symlink (common in modern Linux), we must remove it to make a real file
    if [[ -L "/etc/resolv.conf" ]]; then
        echo "[+] Removing existing resolv.conf symlink..."
        rm -f /etc/resolv.conf
    fi
    
    echo "[+] Writing $DNS_NAME DNS records..."
    cat <<EOF > /etc/resolv.conf
# DNS configuration set by Persistent DNS Configuration Tool
# Provider: $DNS_NAME
# Date: $(date)
nameserver $DNS1
nameserver $DNS2
# IPv6 DNS servers (optional, uncomment if needed):
#nameserver ${DNS_IPV6%% *}
#nameserver ${DNS_IPV6##* }
options timeout:2 attempts:3
EOF

    # Ensure proper permissions
    chmod 644 /etc/resolv.conf
    
    echo "[+] Locking file with chattr +i..."
    if chattr +i /etc/resolv.conf; then
        echo "[+] Success! /etc/resolv.conf is locked. $DNS_NAME DNS is now permanent."
        echo "[!] Note: To edit this file in the future, you must first run: sudo chattr -i /etc/resolv.conf"
    else
        echo "[-] Error: Failed to lock /etc/resolv.conf with chattr."
        echo "[-] The file may be on a filesystem that doesn't support immutable attribute."
        exit 1
    fi
fi

echo ""
echo "=========================================="
echo "           DNS setup complete!            "
echo "=========================================="