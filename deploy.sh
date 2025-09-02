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

# Chromium flags (tuned for ARM/Wayland kiosk)
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
  "--use-gl=egl"
  "--ozone-platform=wayland"
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
  x11-utils xrandr xauth

# Install Wayland compositor and display tools (with fallbacks)
echo "Installing display and compositor tools..."

# Try to install cage (non-blocking - continue even if it fails)
if apt-cache search cage >/dev/null 2>&1; then
  echo "Attempting to install cage..."
  apt-get install -y cage || echo "⚠ cage installation failed, will use X11 fallback"
else
  echo "⚠ cage not available on this distribution, will use X11 fallback"
fi

# Try different display tools (non-blocking - continue even if they fail)
if apt-cache search wlr-randr >/dev/null 2>&1; then
  echo "Attempting to install wlr-randr..."
  apt-get install -y wlr-randr || echo "⚠ wlr-randr installation failed"
elif apt-cache search wlroots-utils >/dev/null 2>&1; then
  echo "Attempting to install wlroots-utils..."
  apt-get install -y wlroots-utils || echo "⚠ wlroots-utils installation failed"
else
  echo "⚠ wlr-randr/wlroots-utils not available, display setup will be limited"
fi

# Browser (package name differs by distro)
if ! need_cmd chromium && ! need_cmd chromium-browser; then
  apt-get install -y chromium || true
  apt-get install -y chromium-browser || true
fi
CHROMIUM_BIN="$(detect_browser)"
if [ -z "${CHROMIUM_BIN}" ]; then
  echo "ERROR: chromium not found after install. Check package names for your OS image." >&2
  exit 1
fi
echo "Using browser: ${CHROMIUM_BIN}"

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

# Try different display tools
DISPLAY_TOOL=""
if command -v wlr-randr >/dev/null 2>&1; then
  DISPLAY_TOOL="wlr-randr"
elif command -v wlroots-utils >/dev/null 2>&1; then
  DISPLAY_TOOL="wlroots-utils"
elif command -v xrandr >/dev/null 2>&1; then
  DISPLAY_TOOL="xrandr"
fi

if [ -z "${DISPLAY_TOOL}" ]; then
  echo "No display tools found; trying basic X11 setup..." >&2
  
  # Try to start X11 server if not running
  if ! pgrep X >/dev/null 2>&1; then
    echo "Starting X11 server..." >&2
    startx -- -nocursor -s 0 -dpms 0 -s off -x 0 &
    sleep 3
  fi
  
  # Try xrandr for display rotation
  if command -v xrandr >/dev/null 2>&1; then
    DISPLAY_TOOL="xrandr"
  fi
fi

if [ -z "${DISPLAY_TOOL}" ]; then
  echo "No display tools available; skipping display setup." >&2
  exit 0
fi

# Try to detect connected output and set portrait mode
if [ "${DISPLAY_TOOL}" = "wlr-randr" ]; then
  OUT="$(wlr-randr | awk '/ connected/ {print $1; exit}')"
  if [ -n "${OUT}" ]; then
    echo "Setting portrait mode with wlr-randr..." >&2
    wlr-randr --output "$OUT" --mode 1920x1080 --transform 90 || \
    wlr-randr --output "$OUT" --mode 1920x1080 --transform 270 || true
  fi
elif [ "${DISPLAY_TOOL}" = "xrandr" ]; then
  OUT="$(xrandr 2>/dev/null | awk '/ connected/ {print $1; exit}')"
  if [ -n "${OUT}" ]; then
    echo "Setting portrait mode with xrandr..." >&2
    xrandr --output "$OUT" --rotate right || \
    xrandr --output "$OUT" --rotate left || true
  fi
else
  echo "Display tool ${DISPLAY_TOOL} found but transform not implemented; skipping." >&2
fi

echo "Display setup completed." >&2
BASH
chmod +x /usr/local/bin/kiosk-display-setup

# ==============================
# 9) systemd unit for kiosk (cage + chromium or fallback)
# ==============================
echo "Creating systemd unit 'kiosk.service'…"
KIOSK_UID="$(id -u "${KIOSK_USER}")"
KIOSK_GID="$(id -g "${KIOSK_USER}")"

CHR_FLAGS_LINE=""
for f in "${CHROMIUM_FLAGS[@]}"; do CHR_FLAGS_LINE="${CHR_FLAGS_LINE} \"$f\""; done

# Determine the compositor to use
COMPOSITOR_CMD=""
if command -v cage >/dev/null 2>&1; then
  COMPOSITOR_CMD="/usr/bin/cage -s --"
  echo "Using cage as Wayland compositor"
else
  # Fallback: try to use X11 or direct display
  COMPOSITOR_CMD=""
  echo "cage not available, using direct display (may need X11)"
fi

cat > "${SYSTEMD_DIR}/kiosk.service" <<EOF
[Unit]
Description=Kiosk display (chromium)
Wants=network-online.target
After=network-online.target nginx.service

[Service]
User=${KIOSK_USER}
Group=${KIOSK_USER}

Environment=XDG_RUNTIME_DIR=/run/user/${KIOSK_UID}
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/${KIOSK_USER}/.Xauthority

# Create runtime directory and set permissions
ExecStartPre=/bin/mkdir -p /run/user/${KIOSK_UID}
ExecStartPre=/bin/chown ${KIOSK_UID}:${KIOSK_GID} /run/user/${KIOSK_UID}
ExecStartPre=/bin/chmod 700 /run/user/${KIOSK_UID}

# Force portrait before launch (with proper environment)
ExecStartPre=/bin/bash -c 'XDG_RUNTIME_DIR=/run/user/${KIOSK_UID} DISPLAY=:0 /usr/local/bin/kiosk-display-setup'

TTYPath=/dev/tty7
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
StandardInput=tty

# Start chromium with proper environment
ExecStart=/bin/bash -c 'XDG_RUNTIME_DIR=/run/user/${KIOSK_UID} DISPLAY=:0 ${CHROMIUM_BIN} ${CHR_FLAGS_LINE}'

Restart=always
RestartSec=5
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kiosk.service

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
if command -v cage >/dev/null 2>&1; then
  echo "Compositor:   cage (Wayland)"
else
  echo "Compositor:   direct display (X11 fallback)"
fi
echo "Display:      1920x1080 rotated 90° (effective 1080x1920)"
echo "Service:      kiosk.service (enabled)"
echo
echo "Useful:"
echo "  journalctl -u kiosk.service -f"
echo "  systemctl restart kiosk.service"
echo "  curl 127.0.0.1:${APP_PORT}/health"
echo
echo "Boot now with:  systemctl start kiosk.service   (or reboot)"
echo "=============================================="
echo

if [ "${AUTO_REBOOT}" = "yes" ]; then
  echo "Rebooting now..."
  sleep 2
  reboot
fi