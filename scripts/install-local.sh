#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v node >/dev/null 2>&1; then
  echo "OpenStrudel needs Node.js 22 or newer. Install it from https://nodejs.org/ and run this again." >&2
  exit 1
fi
NODE_BIN="$(command -v node)"
# node:sqlite works without a flag from Node.js 22.13.
if ! node -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>22||a===22&&b>=13?0:1)'; then
  echo "OpenStrudel needs Node.js 22.13 or newer; found $(node --version)." >&2
  exit 1
fi

# The Mac app runs its own Home under the same launch agent; replacing it would stop that Home and hide its data.
PLIST="$HOME/Library/LaunchAgents/is.openstrudel.home.plist"
if [[ "$(uname -s)" == "Darwin" && -f "$PLIST" ]] \
  && [[ "$(/usr/bin/plutil -extract WorkingDirectory raw -o - "$PLIST" 2>/dev/null)" != "$ROOT" ]]; then
  echo "Another OpenStrudel Home already runs from $PLIST. Remove it first if this checkout should replace it." >&2
  exit 1
fi

# .npmrc keeps vendor install scripts from running: Grok Build's would install itself into ~/.grok.
npm ci
npm run build
node scripts/extract-grok.mjs .
mkdir -p .data
chmod 700 .data

if [[ "$(uname -s)" == "Darwin" ]]; then
  LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
  mkdir -p "$LAUNCH_AGENTS"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>is.openstrudel.home</string>
  <key>ProgramArguments</key><array><string>$NODE_BIN</string><string>$ROOT/dist/cli.js</string><string>start</string></array>
  <key>WorkingDirectory</key><string>$ROOT</string>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>EnvironmentVariables</key><dict><key>OPENSTRUDEL_DB</key><string>$ROOT/.data/openstrudel.sqlite</string></dict>
  <key>StandardOutPath</key><string>$ROOT/.data/home.log</string>
  <key>StandardErrorPath</key><string>$ROOT/.data/home.error.log</string>
</dict></plist>
EOF
  launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  echo "OpenStrudel Home is running at http://127.0.0.1:7788"
  echo "Native app: open native/OpenStrudel/OpenStrudel.xcodeproj"
else
  USER_UNIT="$HOME/.config/systemd/user/openstrudel.service"
  mkdir -p "$(dirname "$USER_UNIT")"
  cat > "$USER_UNIT" <<EOF
[Unit]
Description=OpenStrudel personal AI Home
After=network-online.target

[Service]
WorkingDirectory=$ROOT
ExecStart=$NODE_BIN $ROOT/dist/cli.js start
Restart=on-failure
RestartSec=3
Environment=OPENSTRUDEL_DB=$ROOT/.data/openstrudel.sqlite

[Install]
WantedBy=default.target
EOF
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload
    systemctl --user enable --now openstrudel.service
    # A user service stops at logout and does not start at boot without lingering.
    loginctl enable-linger "$USER" 2>/dev/null || echo "To keep Home running after logout and start it at boot, run: sudo loginctl enable-linger $USER" >&2
    echo "OpenStrudel Home is running at http://127.0.0.1:7788"
  else
    echo "Build complete. Start Home with: $NODE_BIN $ROOT/dist/cli.js start"
  fi
fi

echo "Connect Telegram from the OpenStrudel app's Settings screen."
