#!/bin/bash
DEFAULTS=/usr/local/share/claude-defaults

# Copy default Claude config if not already present
mkdir -p "$HOME/.claude"
cp -n "$DEFAULTS/CLAUDE.md" "$HOME/.claude/CLAUDE.md" 2>/dev/null || true
cp -n "$DEFAULTS/settings.json" "$HOME/.claude/settings.json" 2>/dev/null || true

# Trust bind-mounted workspace
git config --global --add safe.directory /workspace

# Fix ownership/mode on bind-mounted .credentials.json (Docker on WSL2/Windows
# exposes host files as root:root 0777, which Claude Code rejects as insecure).
CREDS="$HOME/.claude/.credentials.json"
if [ -f "$CREDS" ] && [ "$(stat -c %u "$CREDS")" != "$(id -u)" ]; then
  sudo chown "$(id -un):$(id -gn)" "$CREDS" && sudo chmod 600 "$CREDS"
fi

# Skip Claude Code's first-run onboarding wizard (theme picker, ToS, permission
# mode acceptance) when credentials are present. Without these flags the wizard
# runs on every container start, since Enter-confirmations don't always stick.
CC_JSON="$HOME/.claude/.claude.json"
if [ -f "$CREDS" ]; then
  if [ ! -f "$CC_JSON" ]; then
    echo '{}' > "$CC_JSON"
  fi
  jq '. + {hasCompletedOnboarding: true, theme: (.theme // "dark"), bypassPermissionsModeAccepted: true, dangerouslySkipPermissionsAccepted: true}' \
    "$CC_JSON" > "$CC_JSON.tmp" && mv "$CC_JSON.tmp" "$CC_JSON" || true
  chmod 600 "$CC_JSON"
fi

# Symlink claude binary to expected native install path
mkdir -p "$HOME/.local/bin"
ln -sf /usr/local/bin/claude "$HOME/.local/bin/claude"

# Copy pre-installed plugins if not already present
if [ ! -d "$HOME/.claude/plugins/cache" ]; then
  cp -r "$DEFAULTS/plugins" "$HOME/.claude/plugins"
fi

exec "$@"
