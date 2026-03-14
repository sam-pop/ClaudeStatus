#!/bin/sh
# Claude Status — Uninstaller
# Removes scripts and reverts settings.json changes
set -e

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
HOOK_CMD="bash ~/.claude/fetch-usage.sh > /dev/null 2>&1 &"

echo "Uninstalling Claude Status..."

# Remove scripts
rm -f "$CLAUDE_DIR/statusline-command.sh"
rm -f "$CLAUDE_DIR/fetch-usage.sh"
echo "  Removed scripts"

# Remove cache
rm -f /tmp/.claude_usage_cache
echo "  Removed cache"

# Clean settings.json
if [ -f "$SETTINGS" ] && command -v jq > /dev/null 2>&1; then
  tmp=$(mktemp)

  # Remove statusLine
  jq 'del(.statusLine)' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

  # Remove our hooks from PreToolUse
  jq --arg cmd "$HOOK_CMD" '
    if .hooks.PreToolUse then
      .hooks.PreToolUse = [.hooks.PreToolUse[] | select(.hooks | all(.command != $cmd))]
      | if .hooks.PreToolUse == [] then del(.hooks.PreToolUse) else . end
    else . end
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

  # Remove our hooks from Stop
  jq --arg cmd "$HOOK_CMD" '
    if .hooks.Stop then
      .hooks.Stop = [.hooks.Stop[] | select(.hooks | all(.command != $cmd))]
      | if .hooks.Stop == [] then del(.hooks.Stop) else . end
    else . end
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

  # Clean up empty hooks object
  jq 'if .hooks == {} then del(.hooks) else . end' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

  echo "  Cleaned settings.json"
fi

echo ""
echo "Done! Restart Claude Code to apply changes."
