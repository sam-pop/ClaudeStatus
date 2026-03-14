#!/bin/sh
# Claude Status — Installer
# Copies scripts to ~/.claude/ and configures settings.json
set -e

CLAUDE_DIR="$HOME/.claude"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$CLAUDE_DIR/settings.json"
HOOK_CMD="bash ~/.claude/fetch-usage.sh > /dev/null 2>&1 &"

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
if ! command -v jq > /dev/null 2>&1; then
  echo "Error: jq is required. Install it with:"
  echo "  brew install jq       # macOS"
  echo "  apt install jq        # Debian/Ubuntu"
  exit 1
fi

if [ ! -d "$CLAUDE_DIR" ]; then
  echo "Error: $CLAUDE_DIR not found. Is Claude Code installed?"
  exit 1
fi

echo "Installing Claude Status..."

# ---------------------------------------------------------------------------
# Copy scripts
# ---------------------------------------------------------------------------
cp "$SCRIPT_DIR/statusline.sh" "$CLAUDE_DIR/statusline-command.sh"
cp "$SCRIPT_DIR/fetch-usage.sh" "$CLAUDE_DIR/fetch-usage.sh"
chmod +x "$CLAUDE_DIR/statusline-command.sh"
chmod +x "$CLAUDE_DIR/fetch-usage.sh"
echo "  Copied scripts to $CLAUDE_DIR/"

# ---------------------------------------------------------------------------
# Configure settings.json
# ---------------------------------------------------------------------------
if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

# Backup existing settings
cp "$SETTINGS" "$SETTINGS.bak"
echo "  Backed up settings to $SETTINGS.bak"

tmp=$(mktemp)

# Set statusLine
jq '.statusLine = {
  "type": "command",
  "command": "bash ~/.claude/statusline-command.sh"
}' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

# Add PreToolUse hook (if not already present)
has_pre=$(jq --arg cmd "$HOOK_CMD" '
  [(.hooks.PreToolUse // [])[].hooks[]? | select(.command == $cmd)] | length
' "$SETTINGS")
if [ "$has_pre" = "0" ]; then
  jq --arg cmd "$HOOK_CMD" '
    .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [
      {"matcher": "", "hooks": [{"type": "command", "command": $cmd}]}
    ])
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
fi

# Add Stop hook (if not already present)
has_stop=$(jq --arg cmd "$HOOK_CMD" '
  [(.hooks.Stop // [])[].hooks[]? | select(.command == $cmd)] | length
' "$SETTINGS")
if [ "$has_stop" = "0" ]; then
  jq --arg cmd "$HOOK_CMD" '
    .hooks.Stop = ((.hooks.Stop // []) + [
      {"matcher": "", "hooks": [{"type": "command", "command": $cmd}]}
    ])
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
fi

echo "  Updated $SETTINGS"

# ---------------------------------------------------------------------------
# Prime the cache
# ---------------------------------------------------------------------------
echo "  Fetching initial usage data..."
bash "$CLAUDE_DIR/fetch-usage.sh" 2>/dev/null && echo "  Cache primed." || echo "  Skipped (no credentials found yet)."

echo ""
echo "Done! Restart Claude Code to see your new status line."
