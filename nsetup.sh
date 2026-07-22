#!/bin/bash

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "Error: Please run this script as root (use sudo)."
   exit 1
fi

# Redirect stdin from /dev/tty for interactive input (works with pipes too)
if [[ -t 0 ]]; then
    # Already running interactively, no change needed
    :
else
    # Being piped (like curl | bash), reconnect to terminal
    exec < /dev/tty
fi

echo "=========================================="
echo "    Persistent DNS Configuration Tool     "
echo "=========================================="
echo ""

# ----------------------------------------
# Detect system configuration
# ----------------------------------------
SYSTEMD_AVAILABLE=false
RESOLVED_AVAILABLE=false
RESOLVED_MASKED=false

if command -v systemctl &> /dev/null; then
    SYSTEMD_AVAILABLE=true
    if systemctl list-unit-files systemd-resolved.service &> /dev/null; then
        RESOLVED_AVAILABLE=true
        if systemctl is-enabled systemd-resolved.service 2>/dev/null | grep -q "masked"; then
            RESOLVED_MASKED=true
        fi
    fi
fi

# ----------------------------------------
# 1. Method Selection
# ----------------------------------------
echo "1. Which method do you want to use?"
if $SYSTEMD_AVAILABLE && $RESOLVED_AVAILABLE && ! $RESOLVED_MASKED; then
    echo "   A - Native OS (systemd-resolved) [Recommended]"
    echo "   B - Lock System (chattr immutable)"
    DEFAULT_METHOD="A"
else
    echo "   A - Native OS (systemd-resolved) [NOT AVAILABLE]"
    echo "   B - Lock System (chattr immutable) [Recommended]"
    if $RESOLVED_MASKED; then
        echo "       (systemd-resolved is masked, Method B recommended)"
    fi
    DEFAULT_METHOD="B"
fi

while true; do
    read -p "   Select an option (A/B) [${DEFAULT_METHOD}]: " METHOD_CHOICE
    # Use default if empty
    METHOD_CHOICE=${METHOD_CHOICE:-$DEFAULT_METHOD}
    # Convert input to uppercase
    METHOD_CHOICE=${METHOD_CHOICE^^}
    
    case "$METHOD_CHOICE" in
        A) 
            if $RESOLVED_MASKED; then
                echo "   Warning: systemd-resolved is masked. Method A will fail."
                read -p "   Continue anyway? (y/N): " FORCE_A
                FORCE_A=${FORCE_A:-n}
                if [[ "${FORCE_A^^}" != "Y" ]]; then
                    continue
                fi
            fi
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
        1) DNS_NAME="Google"; DNS1="8.8.8.8"; DNS2="8.8.4.4"; break ;;
        2) DNS_NAME="Cloudflare"; DNS1="1.1.1.1"; DNS2="1.0.0.1"; break ;;
        3) DNS_NAME="OpenDNS"; DNS1="208.67.222.222"; DNS2="208.67.220.220"; break ;;
        4) DNS_NAME="Quad9"; DNS1="9.9.9.9"; DNS2="149.112.112.112"; break ;;
        5) DNS_NAME="ControlD"; DNS1="76.76.2.0"; DNS2="76.76.10.0"; break ;;
        6) DNS_NAME="GCore DNS"; DNS1="95.85.95.85"; DNS2="2.56.220.2"; break ;;
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
    
    # Try to unmask if masked
    if $RESOLVED_MASKED; then
        echo "[!] systemd-resolved is masked. Attempting to unmask..."
        systemctl unmask systemd-resolved.service 2>/dev/null || {
            echo "[-] Failed to unmask. Falling back to Method B..."
            METHOD_CHOICE="B"
        }
    fi
    
    if [[ "$METHOD_CHOICE" == "A" ]]; then
        echo "[+] Enabling and starting systemd-resolved service..."
        systemctl enable systemd-resolved.service 2>/dev/null
        systemctl start systemd-resolved.service 2>/dev/null
        
        echo "[+] Creating drop-in configuration directory for systemd-resolved..."
        mkdir -p /etc/systemd/resolved.conf.d
        
        echo "[+] Writing $DNS_NAME records..."
        cat <<EOF > /etc/systemd/resolved.conf.d/custom-dns.conf
[Resolve]
DNS=$DNS1 $DNS2
FallbackDNS=1.1.1.1 8.8.8.8
EOF

        echo "[+] Restarting systemd-resolved service..."
        systemctl restart systemd-resolved.service
        
        # Wait for service to stabilize
        sleep 2
        
        # Verify success
        if systemctl is-active --quiet systemd-resolved.service; then
            echo "[+] Success! Native OS DNS has been updated to $DNS_NAME."
            echo "[+] Testing DNS resolution..."
            if nslookup google.com &>/dev/null || dig google.com &>/dev/null || host google.com &>/dev/null; then
                echo "[+] DNS resolution is working!"
            else
                echo "[!] Warning: DNS resolution test failed. Please check your network."
            fi
        else
            echo "[-] Error: systemd-resolved service failed to start."
            echo "[-] Falling back to Method B..."
            METHOD_CHOICE="B"
        fi
    fi
fi

if [[ "$METHOD_CHOICE" == "B" ]]; then
    # METHOD B: Lock System (chattr)
    
    # Check if chattr is available
    if ! command -v chattr &> /dev/null; then
        echo "[-] Error: chattr command not found. Installing e2fsprogs..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y e2fsprogs
        elif command -v yum &> /dev/null; then
            yum install -y e2fsprogs
        else
            echo "[-] Cannot install e2fsprogs automatically. Please install it manually."
            exit 1
        fi
    fi
    
    echo "[+] Checking for existing locks on /etc/resolv.conf..."
    # Suppress error if not currently locked or doesn't exist
    chattr -i /etc/resolv.conf 2>/dev/null
    
    # Backup existing file
    if [[ -f "/etc/resolv.conf" ]] || [[ -L "/etc/resolv.conf" ]]; then
        echo "[+] Backing up existing resolv.conf..."
        cp -a /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null
    fi
    
    # If it is a symlink (common in modern Linux), we must remove it to make a real file
    if [[ -L "/etc/resolv.conf" ]]; then
        echo "[+] Removing existing resolv.conf symlink..."
        rm -f /etc/resolv.conf
    fi
    
    echo "[+] Writing $DNS_NAME records..."
    cat <<EOF > /etc/resolv.conf
# DNS Configuration by Persistent DNS Tool
# Provider: $DNS_NAME
# Date: $(date)
nameserver $DNS1
nameserver $DNS2
options timeout:2
options attempts:3
EOF

    # Ensure proper permissions
    chmod 644 /etc/resolv.conf
    
    echo "[+] Locking file with chattr +i..."
    if chattr +i /etc/resolv.conf 2>/dev/null; then
        echo "[+] Success! /etc/resolv.conf is locked. $DNS_NAME is now permanent."
        echo "[!] Note: To edit this file in the future, you must first run: chattr -i /etc/resolv.conf"
        
        echo "[+] Testing DNS resolution..."
        if nslookup google.com &>/dev/null || dig google.com &>/dev/null || host google.com &>/dev/null; then
            echo "[+] DNS resolution is working!"
        else
            echo "[!] Warning: DNS resolution test failed. Please check your network."
        fi
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
echo ""
echo "Current DNS configuration:"
if [[ "$METHOD_CHOICE" == "A" ]] && systemctl is-active --quiet systemd-resolved.service; then
    resolvectl status 2>/dev/null | grep -A 5 "DNS Servers" || echo "DNS: $DNS1, $DNS2"
else
    echo "DNS: $DNS1, $DNS2"
fi