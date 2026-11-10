#!/bin/sh
# ==============================================================================
# ZyXEL NSA210 - Modern BitTorrent & TLS 1.3 Tracker Proxy Installer
# Repository: https://github.com/thaidelphi/nsa210
# ==============================================================================

set -e

echo "=========================================================="
echo " ZyXEL NSA210 System Modernization & Tracker Proxy Setup"
echo "=========================================================="

if [ "$(id -u)" != "0" ]; then
    echo "[-] Error: Please run this script as root." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. Install Static curl 8.14 (ARMv5te with TLS 1.3 + OpenSSL 3.5.0)
echo "[+] Installing static curl with TLS 1.3 support..."
if [ -f "$SCRIPT_DIR/bin/curl-8.14" ]; then
    cp -f "$SCRIPT_DIR/bin/curl-8.14" /usr/local/zy-pkgs/bin/curl-8.14
    chmod 755 /usr/local/zy-pkgs/bin/curl-8.14
    echo "    Installed /usr/local/zy-pkgs/bin/curl-8.14"
fi

# 2. Install TLS 1.3 Tracker Proxy Daemon
echo "[+] Installing TLS 1.3 Tracker Proxy Daemon..."
if [ -f "$SCRIPT_DIR/bin/tracker_proxy.pl" ]; then
    cp -f "$SCRIPT_DIR/bin/tracker_proxy.pl" /usr/local/zy-pkgs/bin/tracker_proxy.pl
    chmod 755 /usr/local/zy-pkgs/bin/tracker_proxy.pl
    echo "    Installed /usr/local/zy-pkgs/bin/tracker_proxy.pl"
fi

# 3. Install Transmission Web UI Mods (BitComet Tracker Editor)
echo "[+] Installing Transmission Web UI enhancements..."
TR_WEB="/usr/local/zy-pkgs/gui/Transmission/transmission/web"
if [ -d "$TR_WEB" ]; then
    cp -f "$SCRIPT_DIR/transmission/web/index.html" "$TR_WEB/index.html"
    cp -f "$SCRIPT_DIR/transmission/web/javascript/transmission.js" "$TR_WEB/javascript/transmission.js"
    chmod 644 "$TR_WEB/index.html" "$TR_WEB/javascript/transmission.js"
    echo "    Updated $TR_WEB with BitComet Tracker Editor"
else
    echo "    [!] Warning: Transmission web directory not found at $TR_WEB"
fi

# 4. Install ZyXEL Web Admin Integration
echo "[+] Installing ZyXEL Web Admin portal integration..."
ZY_PKG_TR="/usr/local/apache/htdocs/zyxel/pkg/Transmission"
mkdir -p "$ZY_PKG_TR"
if [ -f "$SCRIPT_DIR/zyxel-web/pkg/Transmission/index.html" ]; then
    cp -f "$SCRIPT_DIR/zyxel-web/pkg/Transmission/index.html" "$ZY_PKG_TR/index.html"
    chmod 644 "$ZY_PKG_TR/index.html"
    echo "    Installed $ZY_PKG_TR/index.html"
fi

# 5. Install Left Navigation Menu Patch
echo "[+] Setting up ZyXEL Admin Left Menu patch..."
FFP_VOL=$(find /i-data -maxdepth 2 -name "ffp" -type d 2>/dev/null | head -n 1)
if [ -z "$FFP_VOL" ]; then
    MOD_DIR="/ffp/web_mod"
else
    MOD_DIR="$FFP_VOL/web_mod"
fi
mkdir -p "$MOD_DIR"

if [ -f "$SCRIPT_DIR/zyxel-web/admin/frame_left_menu.html" ]; then
    cp -f "$SCRIPT_DIR/zyxel-web/admin/frame_left_menu.html" "$MOD_DIR/frame_left_menu.html"
    chmod 644 "$MOD_DIR/frame_left_menu.html"
    umount /usr/local/apache/htdocs/zyxel/admin/frame_left_menu.html 2>/dev/null || true
    mount --bind "$MOD_DIR/frame_left_menu.html" /usr/local/apache/htdocs/zyxel/admin/frame_left_menu.html
    echo "    Bound $MOD_DIR/frame_left_menu.html to Apache Web GUI"
fi

# 6. Configure Samba Shares for Windows 10/11 Network Access
echo "[+] Checking Samba configuration..."
if ! grep -q "\[download\]" /etc/samba/smb.conf 2>/dev/null; then
    cat >> /etc/samba/smb.conf << 'EOF'

[download]
	comment = Transmission Downloads
	path = /i-data/md0/admin/download
	public = yes
	guest ok = yes
	browseable = yes
	writable = yes
	write ok = yes
	force user = root
	create mask = 0777
	directory mask = 0777

[Transmission]
	comment = Transmission Finished Torrents
	path = /i-data/md0/admin/download/Transmission
	public = yes
	guest ok = yes
	browseable = yes
	writable = yes
	write ok = yes
	force user = root
	create mask = 0777
	directory mask = 0777
EOF
    echo "    Added [download] and [Transmission] shares to /etc/samba/smb.conf"
    killall -HUP smbd 2>/dev/null || true
else
    echo "    Samba shares already present."
fi

# 7. Configure System Boot Hook in sshd
echo "[+] Installing persistent boot startup hooks..."
if [ -f "$SCRIPT_DIR/init.d/sshd" ]; then
    cp -f "$SCRIPT_DIR/init.d/sshd" /usr/local/zy-pkgs/etc/init.d/sshd
    chmod 755 /usr/local/zy-pkgs/etc/init.d/sshd
    echo "    Updated /usr/local/zy-pkgs/etc/init.d/sshd"
fi

# 8. Start / Restart Tracker Proxy Daemon
echo "[+] Starting Tracker Proxy Daemon..."
killall perl 2>/dev/null || true
if [ -x /ffp/bin/perl ] && [ -x /usr/local/zy-pkgs/bin/tracker_proxy.pl ]; then
    /ffp/bin/perl /usr/local/zy-pkgs/bin/tracker_proxy.pl </dev/null >/tmp/tracker_proxy.log 2>&1 &
    echo "    Tracker proxy listening on 127.0.0.1:8888 (log: /tmp/tracker_proxy.log)"
else
    echo "    [!] Warning: Perl not found at /ffp/bin/perl. Please ensure FFP is installed."
fi

# 9. Ensure Apache Auth Skip for Transmission Web
if grep -q "AuthZyxelSkipPattern" /etc/service_conf/httpd.conf 2>/dev/null; then
    if ! grep -q "/zyxel/pkg/" /etc/service_conf/httpd.conf; then
        sed -i 's|AuthZyxelSkipPattern |AuthZyxelSkipPattern /zyxel/pkg/ |' /etc/service_conf/httpd.conf
        killall -HUP httpd 2>/dev/null || true
        echo "    Configured Apache bypass for /zyxel/pkg/"
    fi
fi

echo ""
echo "=========================================================="
echo " Installation Complete!"
echo " Transmission URL: http://<nas-ip>:9091/transmission/web/"
echo " ZyXEL Admin URL:  http://<nas-ip>/ (Applications -> Transmission)"
echo " Windows Share:    \\\\<nas-ip>\\download"
echo "=========================================================="
