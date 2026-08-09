#!/bin/bash
# Fix Chromium/Chrome Cross-GPU EGL Render Node Wayland Crash on Nouveau
set -e

USER_DESKTOP_DIR="$HOME/.local/share/applications"
CHROME_DESKTOP="$USER_DESKTOP_DIR/google-chrome.desktop"

mkdir -p "$USER_DESKTOP_DIR"

echo "[+] Updating Google Chrome desktop launcher configuration..."
cat << 'EOF' > "$CHROME_DESKTOP"
[Desktop Entry]
Version=1.0
Name=Google Chrome
GenericName=Web Browser
Comment=Access the Internet
Exec=/usr/bin/google-chrome-stable --enable-gpu-rasterization --ignore-gpu-blocklist %U
Terminal=false
Icon=google-chrome
Type=Application
Categories=Network;WebBrowser;
StartupWMClass=google-chrome
MimeType=x-scheme-handler/unknown;x-scheme-handler/about;text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=New Window
Exec=/usr/bin/google-chrome-stable --enable-gpu-rasterization --ignore-gpu-blocklist

[Desktop Action new-private-window]
Name=New Incognito Window
Exec=/usr/bin/google-chrome-stable --enable-gpu-rasterization --ignore-gpu-blocklist --incognito
EOF

chmod +x "$CHROME_DESKTOP"
update-desktop-database "$USER_DESKTOP_DIR" 2>/dev/null || true

echo "[SUCCESS] Google Chrome launcher updated without cross-render-node EGL override to prevent Nouveau PTE page faults during window creation."
