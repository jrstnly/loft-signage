#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Config (edit as needed)
# ==============================
# Kiosk bits
KIOSK_USER="kiosk"
APP_ROOT="/opt/kiosk/www"
SITE_NAME="kiosk"
APP_PORT="9000"
KIOSK_URL="http://127.0.0.1:${APP_PORT}"
NGINX_CONF_DIR="/etc/nginx"
SYSTEMD_DIR="/etc/systemd/system"
AUTO_REBOOT="yes"   # "yes" to reboot when done, "no" for testing

# Repo/build config
REPO_URL="https://github.com/jrstnly/loft-signage.git"
REPO_BRANCH="main"
REPO_BASE="/opt/kiosk/src"          # where the repo will live
REPO_SUBDIR="."                     # path inside the repo for the web app (e.g., "apps/web")
BUILD_CMD="npm ci && npm run build" # change to "pnpm i --frozen-lockfile && pnpm build" if needed
BUILD_OUTPUT_DIR="dist"             # Vite output directory (use "build" for CRA)
NODE_VERSION="22"                   # Node LTS (22). We'll try NodeSource.

# Browser flags (tuned for ARM systems with fallbacks)
CHROMIUM_FLAGS=(
  "--kiosk" "${KIOSK_URL}"
  "--no-first-run"
  "--noerrdialogs"
  "--disable-session-crashed-bubble"
  "--disable-infobars"
  "--disable-features=TranslateUI"
  "--check-for-update-interval=31536000"
  "--start-maximized"
  "--autoplay-policy=no-user-gesture-required"
  "--enable-features=OverlayScrollbar"
  "--no-sandbox"
  "--disable-gpu"
  "--disable-software-rasterizer"
  "--disable-dev-shm-usage"
  "--disable-web-security"
  "--disable-features=VizDisplayCompositor"
  "--disable-gpu-sandbox"
  "--disable-accelerated-2d-canvas"
  "--disable-accelerated-jpeg-decoding"
  "--disable-accelerated-mjpeg-decode"
  "--disable-accelerated-video-decode"
  "--disable-accelerated-video-encode"
)

# ==============================
# Helpers
# ==============================
need_cmd() { command -v "$1" >/dev/null 2>&1; }
require_root() { if [ "$(id -u)" -ne 0 ]; then echo "Please run as root (use sudo)." >&2; exit 1; fi; }
detect_browser() {
  local cpath=""
  if need_cmd chromium; then cpath="$(command -v chromium)"
  elif need_cmd chromium-browser; then cpath="$(command -v chromium-browser)"
  else cpath=""
  fi
  echo "${cpath}"
}

# ==============================
# 1) Sanity / root
# ==============================
require_root
export DEBIAN_FRONTEND=noninteractive

# ==============================
# 2) OS packages
# ==============================
echo "Installing base packages…"
apt-get update -y
apt-get install -y \
  git curl ca-certificates unzip rsync \
  nginx-light \
  dbus-user-session \
  fonts-dejavu-core \
  x11-xserver-utils xauth

# ==============================
# 2.5) Add Radxa repository key (for Rock Pi 4B compatibility)
# ==============================
echo "Adding Radxa repository key for Rock Pi 4B compatibility..."

# Check if we're on a Radxa/Rock Pi device
if [ -f "/etc/apt/sources.list.d/radxa.list" ] || \
   grep -q "radxa" /etc/apt/sources.list 2>/dev/null || \
   [ -f "/etc/os-release" ] && grep -q "radxa\|rock" /etc/os-release 2>/dev/null; then
  echo "✓ Radxa repository detected, adding GPG key..."
  
  # Install the Radxa repository key
  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 9B98116C9AA302C7 2>/dev/null || \
  curl -fsSL https://radxa.com/repo/public.key | apt-key add - 2>/dev/null || \
  echo "⚠ Failed to add Radxa repository key"
  
  # Update package lists to include Radxa packages
  apt-get update -y
  
  echo "✓ Radxa repository key added successfully"
else
  echo "ℹ Not a Radxa device, skipping repository key installation"
fi

# Install display manager and X11 tools
echo "Installing display manager and X11 tools..."

# Install multiple display managers for compatibility
echo "Installing display managers..."

# Install lightdm first (more reliable on ARM systems)
apt-get install -y lightdm lightdm-gtk-greeter || echo "⚠ lightdm installation failed"

# Install gdm3 as backup (Ubuntu default)
apt-get install -y gdm3 || echo "⚠ gdm3 installation failed"

# Check which ones are available
DISPLAY_MANAGER=""
if command -v lightdm >/dev/null 2>&1; then
  DISPLAY_MANAGER="lightdm"
  echo "✓ lightdm available (primary choice for ARM)"
elif command -v gdm3 >/dev/null 2>&1; then
  DISPLAY_MANAGER="gdm3"
  echo "✓ gdm3 available (fallback option)"
else
  echo "⚠ No display managers available"
fi

# Install X11 utilities
apt-get install -y x11-utils xrandr xauth || true

# Install Rock Pi specific utilities if available
if apt-cache search rock-pi 2>/dev/null | grep -q "rock-pi"; then
  echo "Installing Rock Pi specific utilities..."
  apt-get install -y rock-pi-tools rock-pi-config || echo "⚠ Rock Pi utilities installation failed"
fi

# Browser (package name differs by distro)
if ! need_cmd chromium && ! need_cmd chromium-browser; then
  apt-get install -y chromium || true
  apt-get install -y chromium-browser || true
fi

# Install OpenGL/Mesa libraries for ARM systems
echo "Installing OpenGL/Mesa libraries for ARM compatibility..."

# Try to install Rock Pi specific packages if available
if apt-cache search rock-pi 2>/dev/null | grep -q "rock-pi"; then
  echo "✓ Rock Pi packages available, installing..."
  apt-get install -y rock-pi-tools || echo "⚠ rock-pi-tools installation failed"
fi

# Install standard Mesa libraries
apt-get install -y \
  mesa-utils \
  mesa-utils-extra \
  libegl1-mesa \
  libgles2-mesa \
  libgl1-mesa-glx \
  libgl1-mesa-dri \
  libgl1 \
  libglx-mesa0 || true

# Try to find and install Mali libraries from available sources
echo "Searching for Mali GPU libraries..."

# Check for Rock Pi specific Mali libraries first
if apt-cache search libmali-rk 2>/dev/null | grep -q "libmali-rk"; then
  echo "✓ Rock Pi Mali libraries available, installing..."
  apt-get install -y libmali-rk-dev libmali-rk || echo "⚠ Rock Pi Mali libraries installation failed"
fi

# Check for standard Mali libraries
if apt-cache search libmali >/dev/null 2>&1; then
  echo "Found Mali packages, installing..."
  apt-get install -y $(apt-cache search libmali | grep -E "^libmali" | awk '{print $1}' | head -3) || true
else
  echo "No Mali packages found in repositories, will use Mesa fallback"
fi

# Create symlinks for Mali libraries if they exist anywhere
echo "Setting up Mali library symlinks..."
find /usr/lib -name "libmali.so*" 2>/dev/null | while read -r lib; do
  echo "Found Mali library: $lib"
  # Create symlinks in common locations
  ln -sf "$lib" /usr/lib/libmali.so.1 2>/dev/null || true
  ln -sf "$lib" /usr/lib/arm-linux-gnueabihf/libmali.so.1 2>/dev/null || true
done

# If no Mali libraries found, try to create a dummy symlink to Mesa
if [ ! -f "/usr/lib/libmali.so.1" ] && [ ! -f "/usr/lib/arm-linux-gnueabihf/libmali.so.1" ]; then
  echo "No Mali libraries found, creating Mesa fallback symlinks..."
  # Find Mesa EGL/GLES libraries
  MESA_EGL=$(find /usr/lib -name "libEGL.so*" 2>/dev/null | head -1)
  MESA_GLES=$(find /usr/lib -name "libGLESv2.so*" 2>/dev/null | head -1)
  
  if [ -n "$MESA_EGL" ]; then
    ln -sf "$MESA_EGL" /usr/lib/libmali.so.1 2>/dev/null || true
    echo "Created Mali symlink to Mesa EGL: $MESA_EGL"
  elif [ -n "$MESA_GLES" ]; then
    ln -sf "$MESA_GLES" /usr/lib/libmali.so.1 2>/dev/null || true
    echo "Created Mali symlink to Mesa GLES: $MESA_GLES"
  fi
fi

# Try to find a working browser
CHROMIUM_BIN="$(detect_browser)"
if [ -z "${CHROMIUM_BIN}" ]; then
  echo "Chromium not found, trying alternative browsers..."
  # Try to install firefox-esr as fallback
  apt-get install -y firefox-esr || true
  if command -v firefox-esr >/dev/null 2>&1; then
    CHROMIUM_BIN="$(command -v firefox-esr)"
    echo "Using Firefox ESR as fallback browser"
  else
    echo "ERROR: No suitable browser found. Check package availability." >&2
    exit 1
  fi
else
  echo "Using browser: ${CHROMIUM_BIN}"
fi

# If Chromium has library issues, try Firefox as fallback
if [ -n "${CHROMIUM_BIN}" ] && [[ "${CHROMIUM_BIN}" == *"chromium"* ]]; then
  echo "Testing Chromium compatibility..."
  if ! "${CHROMIUM_BIN}" --version >/dev/null 2>&1; then
    echo "Chromium has compatibility issues, trying Firefox ESR..."
    apt-get install -y firefox-esr || true
    if command -v firefox-esr >/dev/null 2>&1; then
      CHROMIUM_BIN="$(command -v firefox-esr)"
      echo "Switched to Firefox ESR due to Chromium compatibility issues"
    else
      echo "WARNING: Both Chromium and Firefox have issues, proceeding with Chromium and fallback flags"
    fi
  fi
fi

# Test if the browser can actually run (check for library issues)
echo "Testing browser compatibility..."
if ! "${CHROMIUM_BIN}" --version >/dev/null 2>&1; then
  echo "WARNING: Browser has library issues, trying to fix..."
  
  # Try to install additional libraries that might be missing
  apt-get install -y \
    libnss3 \
    libatk-bridge2.0-0 \
    libdrm2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libgbm1 \
    libasound2 || true
  
  # Test again
  if ! "${CHROMIUM_BIN}" --version >/dev/null 2>&1; then
    echo "Browser still has issues, will try with fallback flags"
  else
    echo "Browser compatibility fixed!"
  fi
fi

# Check for GBM library compatibility issues
echo "Checking GBM library compatibility..."
if ldd "${CHROMIUM_BIN}" | grep -q "libgbm"; then
  echo "GBM library detected, checking version compatibility..."
  
  # Try to install compatible GBM versions
  apt-get install -y \
    libgbm1 \
    libgbm-dev \
    libdrm2 \
    libdrm-common || true
  
  # Create fallback symlinks for GBM if needed
  if [ -f "/usr/lib/arm-linux-gnueabihf/libgbm.so.1" ]; then
    echo "Creating GBM fallback symlinks..."
    ln -sf /usr/lib/arm-linux-gnueabihf/libgbm.so.1 /usr/lib/libgbm.so.1 2>/dev/null || true
  fi
fi

# ==============================
# 3) Node.js (NodeSource LTS - always install latest)
# ==============================
echo "Installing Node.js ${NODE_VERSION} via NodeSource…"
# Remove old NodeSource repositories first
rm -f /etc/apt/sources.list.d/nodesource.list* 2>/dev/null || true
# NodeSource script handles ARM and Debian/Ubuntu variants nicely
curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -
apt-get update
apt-get install -y nodejs
echo "Node: $(node -v 2>/dev/null || echo 'missing')  NPM: $(npm -v 2>/dev/null || echo 'missing')"

# Optional: speedier builds
if ! need_cmd pnpm; then npm i -g pnpm >/dev/null 2>&1 || true; fi
if ! need_cmd yarn; then npm i -g yarn  >/dev/null 2>&1 || true; fi

# ==============================
# 4) Kiosk user
# ==============================
if ! id -u "${KIOSK_USER}" >/dev/null 2>&1; then
  echo "Creating user '${KIOSK_USER}'…"
  useradd -m -s /bin/bash "${KIOSK_USER}"
fi
usermod -aG video,input,render "${KIOSK_USER}" || true

# ==============================
# 5) Clone/Pull repo and build
# ==============================
echo "Setting up repository at ${REPO_BASE}…"

# Always start with a clean slate to avoid conflicts
if [ -d "${REPO_BASE}" ]; then
  echo "Removing existing repository directory to avoid conflicts…"
  rm -rf "${REPO_BASE}"
fi
mkdir -p "${REPO_BASE}"

# Check if we're running from within the repo (for local testing)
if [ -f ".git/config" ] && [ -f "package.json" ]; then
  echo "Running from local repository, copying files…"
  # We're running from the repo directory, copy everything
  if need_cmd rsync; then
    rsync -av --exclude='.git' . "${REPO_BASE}/"
  else
    # Fallback: copy without git directory
    cp -r . "${REPO_BASE}/"
    rm -rf "${REPO_BASE}/.git"
  fi
else
  # Clone from remote
  echo "Cloning ${REPO_URL} → ${REPO_BASE}…"
  if need_cmd git; then
    git clone --branch "${REPO_BRANCH}" --depth 1 "${REPO_URL}" "${REPO_BASE}"
  else
    echo "Git not available, downloading as zip instead…"
    # Fallback: download as zip if git is not available
    if need_cmd curl; then
      ZIP_URL="https://github.com/jrstnly/loft-signage/archive/refs/heads/main.zip"
      curl -fsSL -o /tmp/loft-signage.zip "${ZIP_URL}"
      apt-get install -y unzip
      unzip -q /tmp/loft-signage.zip -d /tmp/
      
      # Copy files from zip to clean directory
      cp -r /tmp/loft-signage-main/* "${REPO_BASE}/"
      
      rm -rf /tmp/loft-signage-main /tmp/loft-signage.zip
    else
      echo "ERROR: Neither git nor curl available. Cannot download repository." >&2
      exit 1
    fi
  fi
fi

APP_SRC="${REPO_BASE}/${REPO_SUBDIR}"
if [ ! -f "${APP_SRC}/package.json" ]; then
  echo "ERROR: ${APP_SRC}/package.json not found. Check REPO_SUBDIR in the script config." >&2
  echo "Current directory: $(pwd)" >&2
  echo "Repo base: ${REPO_BASE}" >&2
  echo "App src: ${APP_SRC}" >&2
  ls -la "${REPO_BASE}" >&2
  exit 1
fi

echo "Installing deps and building React app in ${APP_SRC}…"
# Try to use PNPM if lockfile exists, else npm; but honor explicit BUILD_CMD
pushd "${APP_SRC}" >/dev/null
# If you’d rather auto-detect, comment BUILD_CMD above and uncomment below:
# if [ -f "pnpm-lock.yaml" ] && need_cmd pnpm; then pnpm i --frozen-lockfile && pnpm build
# elif [ -f "yarn.lock" ] && need_cmd yarn; then yarn install --frozen-lockfile && yarn build
# else npm ci && npm run build; fi
bash -lc "${BUILD_CMD}"
popd >/dev/null

# ==============================
# 6) Publish build to Nginx docroot
# ==============================
echo "Publishing build artifacts to ${APP_ROOT}…"
mkdir -p "${APP_ROOT}"
rm -rf "${APP_ROOT:?}/"* || true
cp -a "${APP_SRC}/${BUILD_OUTPUT_DIR}/." "${APP_ROOT}/"

# If nothing was built, drop a friendly placeholder
if [ ! -f "${APP_ROOT}/index.html" ]; then
  cat > "${APP_ROOT}/index.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>Kiosk</title></head>
<body style="display:flex;align-items:center;justify-content:center;height:100vh;background:#0f172a;color:#e2e8f0;font:16px system-ui,Segoe UI,Roboto,Helvetica,Arial,sans-serif">
  <div style="text-align:center">
    <h1 style="margin:0 0 8px 0">Kiosk is live (serving static files)</h1>
    <p>Build output not found at <code>/opt/kiosk/www/index.html</code>. Check your build settings.</p>
  </div>
</body></html>
HTML
fi
chown -R www-data:www-data "$(dirname "${APP_ROOT}")"
chmod -R 0755 "$(dirname "${APP_ROOT}")"

# ==============================
# 7) Nginx site (127.0.0.1:PORT)
# ==============================
echo "Configuring Nginx site '${SITE_NAME}' on 127.0.0.1:${APP_PORT}…"

# Handle different Nginx directory structures
if [ -d "${NGINX_CONF_DIR}/sites-available" ]; then
  # Traditional Ubuntu/Debian structure
  SITES_AVAILABLE="${NGINX_CONF_DIR}/sites-available/${SITE_NAME}"
  SITES_ENABLED="${NGINX_CONF_DIR}/sites-enabled/${SITE_NAME}"
  
  cat > "${SITES_AVAILABLE}" <<NGINX
server {
  listen 127.0.0.1:${APP_PORT};
  server_name localhost;

  root ${APP_ROOT};
  index index.html;

  add_header Cache-Control "no-store";

  location = /health { return 200 "ok\n"; add_header Content-Type text/plain; }

  location / {
    try_files \$uri /index.html;
  }
}
NGINX

  [ -f "${NGINX_CONF_DIR}/sites-enabled/default" ] && rm -f "${NGINX_CONF_DIR}/sites-enabled/default"
  ln -sf "${SITES_AVAILABLE}" "${SITES_ENABLED}"
else
  # Modern Nginx structure (conf.d)
  SITE_CONF="${NGINX_CONF_DIR}/conf.d/${SITE_NAME}.conf"
  
  cat > "${SITE_CONF}" <<NGINX
server {
  listen 127.0.0.1:${APP_PORT};
  server_name localhost;

  root ${APP_ROOT};
  index index.html;

  add_header Cache-Control "no-store";

  location = /health { return 200 "ok\n"; add_header Content-Type text/plain; }

  location / {
    try_files \$uri /index.html;
  }
}
NGINX
fi

nginx -t
systemctl enable nginx
systemctl restart nginx

# Quick local test
if ! curl -sS "http://127.0.0.1:${APP_PORT}/health" | grep -q "ok"; then
  echo "WARNING: Nginx health check did not return ok. Check Nginx logs." >&2
fi

# ==============================
# 8) Display setup helper (1080x1920 portrait)
# ==============================
cat >/usr/local/bin/kiosk-display-setup <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

# Set up environment for the kiosk user
export XDG_RUNTIME_DIR="/run/user/$(id -u kiosk)"
export DISPLAY=":0"

# Create runtime directory if it doesn't exist
mkdir -p "${XDG_RUNTIME_DIR}"
chown kiosk:kiosk "${XDG_RUNTIME_DIR}"

# Use xrandr for display rotation (standard X11 tool)
if command -v xrandr >/dev/null 2>&1; then
  echo "Setting up display with xrandr..." >&2
  
  # Wait for X11 to be ready
  sleep 2
  
  # You can customize the rotation here if needed
  # Options: left, right, inverted, normal
  # For most portrait signage displays, "left" works best
  PREFERRED_ROTATION="left"
  
  # Try to detect connected output and set portrait mode
  OUT="$(xrandr 2>/dev/null | awk '/ connected/ {print $1; exit}')"
  if [ -n "${OUT}" ]; then
    echo "Setting portrait mode for output: ${OUT}" >&2
    
    # Get current resolution to determine optimal rotation
    CURRENT_MODE="$(xrandr 2>/dev/null | awk -v out="$OUT" '$1 == out {getline; print $1; exit}')"
    echo "Current mode: ${CURRENT_MODE}" >&2
    
    # For portrait displays, try preferred rotation first
    echo "Trying ${PREFERRED_ROTATION} rotation first..." >&2
    if xrandr --output "$OUT" --rotate "${PREFERRED_ROTATION}" 2>/dev/null; then
      echo "✓ ${PREFERRED_ROTATION} rotation applied successfully" >&2
    else
      echo "${PREFERRED_ROTATION} rotation failed, trying alternative..." >&2
      # Try the opposite rotation as fallback
      ALTERNATIVE_ROTATION="right"
      if [ "${PREFERRED_ROTATION}" = "right" ]; then
        ALTERNATIVE_ROTATION="left"
      fi
      
      if xrandr --output "$OUT" --rotate "${ALTERNATIVE_ROTATION}" 2>/dev/null; then
        echo "✓ ${ALTERNATIVE_ROTATION} rotation applied successfully" >&2
      else
        echo "⚠ Both rotations failed, display may be in landscape mode" >&2
      fi
    fi
    
    echo "Display rotation completed." >&2
  else
    echo "No connected output found; skipping display setup." >&2
  fi
else
  echo "xrandr not available; skipping display setup." >&2
fi

echo "Display setup completed." >&2
BASH
chmod +x /usr/local/bin/kiosk-display-setup

# ==============================
# 9) Configure display manager for auto-login and kiosk mode
# ==============================
echo "Configuring ${DISPLAY_MANAGER:-display manager} for auto-login and kiosk mode..."

# Configure display manager based on what's available
if [ "${DISPLAY_MANAGER}" = "lightdm" ]; then
  echo "Configuring lightdm (primary choice for ARM)..."
  
  # Disable gdm3 if it exists to avoid conflicts
  systemctl stop gdm3 2>/dev/null || true
  systemctl disable gdm3 2>/dev/null || true
  
  # Configure lightdm for auto-login
  cat > /etc/lightdm/lightdm.conf << 'EOF'
[SeatDefaults]
autologin-user=kiosk
autologin-user-timeout=0
autologin-session=ubuntu
user-session=ubuntu
greeter-session=lightdm-gtk-greeter

# Additional settings for better compatibility
allow-guest=false
pam-autologin-service=lightdm-autologin
EOF
  
  # Ensure the kiosk user has a valid shell and home directory
  chsh -s /bin/bash kiosk 2>/dev/null || true
  
  # Remove password from kiosk user for true auto-login
  echo "Removing password from kiosk user for auto-login..."
  passwd -d kiosk 2>/dev/null || true
  
  # Also ensure the user can log in without password
  usermod -p '' kiosk 2>/dev/null || true
  
  # Enable and start lightdm properly (it's a template unit)
  systemctl enable lightdm.service
  systemctl set-default graphical.target
  
  # Start lightdm
  systemctl start lightdm.service
  
  # Also create a fallback session configuration
  cat > /etc/lightdm/lightdm.conf.d/50-ubuntu.conf << 'EOF'
[SeatDefaults]
autologin-user=kiosk
autologin-user-timeout=0
EOF
  
  # Create additional configuration to ensure auto-login works
  cat > /etc/lightdm/lightdm.conf.d/60-kiosk.conf << 'EOF'
[SeatDefaults]
autologin-user=kiosk
autologin-user-timeout=0
autologin-session=ubuntu
EOF
  
  # If lightdm fails, try to fall back to gdm3
  if ! systemctl is-active --quiet lightdm.service; then
    echo "⚠ lightdm failed to start, trying gdm3 fallback..."
    systemctl stop lightdm.service 2>/dev/null || true
    systemctl disable lightdm.service 2>/dev/null || true
    
    # Try gdm3 instead
    apt-get install -y gdm3 || echo "⚠ gdm3 installation failed"
    if command -v gdm3 >/dev/null 2>&1; then
      DISPLAY_MANAGER="gdm3"
      echo "Switching to gdm3 fallback..."
      # This will be handled by the gdm3 configuration block below
    fi
  fi
  
elif [ "${DISPLAY_MANAGER}" = "gdm3" ]; then
  echo "Configuring gdm3 (fallback option)..."
  
  # Remove password from kiosk user for true auto-login
  echo "Removing password from kiosk user for auto-login..."
  passwd -d kiosk 2>/dev/null || true
  
  # Set the default target to graphical
  systemctl set-default graphical.target
  
  # Start gdm3 manually for immediate use
  systemctl start gdm3
  
  # Configure gdm3 for auto-login
  cat > /etc/gdm3/custom.conf << 'EOF'
[daemon]
AutomaticLogin=kiosk
AutomaticLoginEnable=true

[security]
AllowRoot=false

[xdmcp]
Enable=false

[greeter]
DisableUserList=true
EOF

else
  echo "⚠ No display manager available, will need manual configuration"
fi

# Display manager configuration is handled above

# ==============================
# 9.5) Configure timezone and locale
# ==============================
echo "Configuring timezone and locale..."

# Set timezone (change this to your desired timezone)
# Common options: America/New_York, America/Chicago, America/Denver, America/Los_Angeles
# Europe/London, Europe/Paris, Asia/Tokyo, etc.
TIMEZONE="America/Chicago"  # Change this to your timezone

echo "Setting timezone to ${TIMEZONE}..."

# Install timezone data if not present
apt-get install -y tzdata || echo "⚠ tzdata installation failed"

# Set the timezone
timedatectl set-timezone "${TIMEZONE}" 2>/dev/null || \
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime 2>/dev/null || \
echo "⚠ Failed to set timezone to ${TIMEZONE}"

# Enable and start NTP synchronization
systemctl enable systemd-timesyncd >/dev/null 2>&1 || true
systemctl start systemd-timesyncd >/dev/null 2>&1 || true

# Set locale to ensure proper time/date formatting
update-locale LANG=en_US.UTF-8 LC_TIME=en_US.UTF-8 2>/dev/null || true

echo "✓ Timezone set to ${TIMEZONE}"
echo "✓ NTP synchronization enabled"

# Create autostart directory for kiosk user
sudo -u kiosk mkdir -p /home/kiosk/.config/autostart

# Create autostart entry for kiosk mode
cat > /home/kiosk/.config/autostart/kiosk.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Kiosk
Exec=chromium --kiosk http://127.0.0.1:9000 --no-sandbox --disable-gpu --no-first-run --noerrdialogs --disable-session-crashed-bubble --disable-infobars --start-maximized --disable-features=TranslateUI --check-for-update-interval=31536000 --autoplay-policy=no-user-gesture-required --enable-features=OverlayScrollbar --disable-gpu-sandbox --disable-accelerated-2d-canvas --disable-accelerated-jpeg-decoding --disable-accelerated-mjpeg-decode --disable-accelerated-video-decode --disable-accelerated-video-encode
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

# Set proper ownership
chown kiosk:kiosk /home/kiosk/.config/autostart/kiosk.desktop

# ==============================
# 10) Final notes
# ==============================
systemctl enable systemd-timesyncd >/dev/null 2>&1 || true
systemctl start systemd-timesyncd  >/dev/null 2>&1 || true

echo
echo "=============================================="
echo "Kiosk setup complete (with React build & 1080x1920 portrait)."
echo
echo "Repo:         ${REPO_URL} (${REPO_BRANCH})"
echo "Repo path:    ${REPO_BASE}"
echo "App subdir:   ${REPO_SUBDIR}"
echo "Build cmd:    ${BUILD_CMD}"
echo "Build out:    ${BUILD_OUTPUT_DIR} → ${APP_ROOT}"
echo
echo "Server:       Nginx on http://127.0.0.1:${APP_PORT}"
echo "Browser:      ${CHROMIUM_BIN}"
echo "Display Manager: ${DISPLAY_MANAGER:-unknown} with auto-login"
echo "Display:      1920x1080 rotated 90° (effective 1080x1920)"
echo "Timezone:     ${TIMEZONE:-unknown}"
echo "Auto-start:   kiosk.desktop in kiosk user autostart"
echo
echo "Useful:"
if [ "${DISPLAY_MANAGER}" = "gdm3" ]; then
  echo "  systemctl status gdm3"
  echo "  systemctl restart gdm3"
elif [ "${DISPLAY_MANAGER}" = "lightdm" ]; then
  echo "  systemctl status lightdm"
  echo "  systemctl restart lightdm"
fi
echo "  curl 127.0.0.1:${APP_PORT}/health"
echo "  sudo -u kiosk chromium --version"
echo "  timedatectl status"
echo "  date"
echo
echo "Boot now with:  sudo reboot   (${DISPLAY_MANAGER:-display manager} will auto-start)"
echo "=============================================="
echo

if [ "${AUTO_REBOOT}" = "yes" ]; then
  echo "Rebooting now..."
  sleep 2
  reboot
fi