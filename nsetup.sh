#!/bin/bash

# ─────────────────────────────────────────────────────────────────────────
# Fix for:  curl -sSL URL | sudo bash
#
# Problem:  When piped, stdin = pipe (script content). Bash reads the
#           script from stdin, so interactive `read` commands cannot
#           access the terminal. Additionally, stdout is block-buffered
#           so prompts are invisible → script appears to hang.
#
# Strategy (two-tier):
#   1. Download script to temp file and re-exec (cleanest — stdin=terminal)
#   2. Fallback: redirect stdout→/dev/tty so output is unbuffered, and
#      use  read VAR < /dev/tty  for interactive input
# ─────────────────────────────────────────────────────────────────────────
_PIPED_MODE=false

if [ ! -t 0 ]; then
    _PIPED_MODE=true

    # ── Tier 1: download & re-exec ──────────────────────────────────────
    _SCRIPT_URL="https://raw.githubusercontent.com/Luveedu/Public-Resolver-Change/refs/heads/main/nsetup.sh"
    _TMPF=$(mktemp /tmp/nsetup.XXXXXX.sh 2>/dev/null)
    _DOWNLOADED=false

    if [ -n "$_TMPF" ]; then
        if command -v curl &>/dev/null; then
            curl -sSL "$_SCRIPT_URL" -o "$_TMPF" 2>/dev/null && [ -s "$_TMPF" ] && _DOWNLOADED=true
        fi
        if ! $_DOWNLOADED && command -v wget &>/dev/null; then
            wget -q "$_SCRIPT_URL" -O "$_TMPF" 2>/dev/null && [ -s "$_TMPF" ] && _DOWNLOADED=true
        fi
    fi

    if $_DOWNLOADED; then
        # Cleanup the temp copy when the re-exec'd script exits
        trap 'rm -f "$_TMPF" 2>/dev/null' EXIT
        chmod +x "$_TMPF"
        exec bash "$_TMPF" "$@"
        # exec replaces this process — from here stdin IS the terminal
    fi

    rm -f "$_TMPF" 2>/dev/null

    # ── Tier 2: fallback when download fails (e.g. broken DNS) ──────────
    # Redirect stdout & stderr straight to /dev/tty so output is never
    # stuck in a buffer. stdin (fd 0) stays as the pipe — bash continues
    # reading the script from its internal buffer. Every 'read' command
    # will explicitly read from /dev/tty.
    if [ -e /dev/tty ]; then
        exec 1>/dev/tty 2>&1
    else
        printf "\nError: Cannot run interactively when piped and no TTY is available.\n"
        printf "Please download and run the script manually:\n"
        printf "  curl -sSL %s -o nsetup.sh\n" "$_SCRIPT_URL"
        printf "  sudo bash nsetup.sh\n\n"
        exit 1
    fi
fi

# Cleanup temp file on exit
trap 'rm -f /tmp/nsetup.*.sh 2>/dev/null' EXIT

# ─────────────────────────────────────────────────────────────────────────
# Helper: read user input.  Always reads from /dev/tty so it works both
# when stdin is the terminal (direct run) and when stdin is a pipe.
# ─────────────────────────────────────────────────────────────────────────
_tty_read() {
    read "$@" < /dev/tty
}

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
    printf "Error: Please run this script as root (use sudo).\n"
    exit 1
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
else
    echo "   A - Native OS (systemd-resolved) [NOT AVAILABLE]"
    echo "   B - Lock System (chattr immutable) [Recommended]"
    if $RESOLVED_MASKED; then
        echo "       (systemd-resolved is masked, Method B recommended)"
    fi
fi

while true; do
    echo -n "   Select an option (A/B): "
    read METHOD_CHOICE
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
    echo -n "   Select a DNS provider (1-6): "
    read DNS_CHOICE
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
    echo -n "   (Y/N): "
    read CONFIRM
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

# Restore original stdin
exec <&3 2>/dev/null

# ----------------------------------------
# Execution
# ----------------------------------------
echo "Applying configurations..."

if [[ "$METHOD_CHOICE" == "A" ]]; then
    # METHOD A: Native OS (systemd-resolved)
    
    # Try to unmask if masked
    if $RESOLVED_MASKED; then
        echo "[!] systemd-resolved is masked. Attempting to unmask..."
        systemctl unmask systemd-resolved.service 2>/dev/null
    fi
    
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
    
    # Verify success
    if systemctl is-active --quiet systemd-resolved.service; then
        echo "[+] Success! Native OS DNS has been updated to $DNS_NAME."
        echo "[+] Testing DNS resolution..."
        if ping -c 1 google.com &>/dev/null; then
            echo "[+] DNS resolution is working!"
        else
            echo "[!] Warning: DNS resolution test failed. Please check your network."
        fi
    else
        echo "[-] Error: systemd-resolved service failed to start."
        echo "[-] Trying Method B instead..."
        METHOD_CHOICE="B"
    fi
fi

if [[ "$METHOD_CHOICE" == "B" ]]; then
    # METHOD B: Lock System (chattr)
    
    # Check if chattr is available
    if ! command -v chattr &> /dev/null; then
        echo "[-] chattr not found. Installing e2fsprogs..."
        apt-get update -qq && apt-get install -y -qq e2fsprogs 2>/dev/null || \
        yum install -y -q e2fsprogs 2>/dev/null || {
            echo "[-] Cannot install e2fsprogs. Please install manually."
            exit 1
        }
    fi
    
    echo "[+] Removing locks on /etc/resolv.conf..."
    chattr -i /etc/resolv.conf 2>/dev/null
    
    # Backup existing file
    if [[ -f "/etc/resolv.conf" ]] || [[ -L "/etc/resolv.conf" ]]; then
        echo "[+] Backing up existing resolv.conf..."
        cp -a /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null
    fi
    
    # Remove symlink if present
    if [[ -L "/etc/resolv.conf" ]]; then
        echo "[+] Removing resolv.conf symlink..."
        rm -f /etc/resolv.conf
    fi
    
    echo "[+] Writing $DNS_NAME records..."
    cat <<EOF > /etc/resolv.conf
# DNS Configuration
# Provider: $DNS_NAME
# Date: $(date)
nameserver $DNS1
nameserver $DNS2
options timeout:2
options attempts:3
EOF

    chmod 644 /etc/resolv.conf
    
    echo "[+] Locking /etc/resolv.conf..."
    if chattr +i /etc/resolv.conf 2>/dev/null; then
        echo "[+] Success! DNS set to $DNS_NAME and locked."
        echo "[+] Testing DNS resolution..."
        if ping -c 1 google.com &>/dev/null; then
            echo "[+] DNS resolution is working!"
        else
            echo "[!] Warning: DNS test failed. Check network settings."
        fi
    else
        echo "[-] Failed to lock file. DNS set but not immutable."
    fi
fi

echo ""
echo "=========================================="
echo "           DNS setup complete!            "
echo "=========================================="
