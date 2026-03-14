#!/bin/sh
# Fetches Claude Code usage stats from the Anthropic API and caches them.
#
# Cache format (/tmp/.claude_usage_cache):
#   Line 1: five_hour utilization (integer %)
#   Line 2: seven_day utilization (integer %)
#   Line 3: five_hour resets_at (ISO 8601)
#   Line 4: seven_day resets_at (ISO 8601)
#
# Designed to run in background via Claude Code hooks.

CACHE_FILE="/tmp/.claude_usage_cache"

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------
if stat -f %m /dev/null > /dev/null 2>&1; then
  file_mtime() { stat -f %m "$1"; }
else
  file_mtime() { stat -c %Y "$1"; }
fi

# ---------------------------------------------------------------------------
# Throttle: skip if cache is fresh (< 60s)
# ---------------------------------------------------------------------------
if [ -f "$CACHE_FILE" ]; then
  cache_age=$(( $(date +%s) - $(file_mtime "$CACHE_FILE") ))
  [ "$cache_age" -lt 60 ] && exit 0
fi

# ---------------------------------------------------------------------------
# Extract OAuth token
# ---------------------------------------------------------------------------
# macOS: Keychain
if command -v security > /dev/null 2>&1; then
  raw_creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
fi

# Linux fallback: check common credential file locations
if [ -z "$raw_creds" ]; then
  for f in \
    "$HOME/.config/claude-code/credentials.json" \
    "$HOME/.claude/credentials.json"; do
    [ -f "$f" ] && raw_creds=$(cat "$f" 2>/dev/null) && break
  done
fi

if [ -z "$raw_creds" ]; then
  exit 0
fi

token=$(printf '%s' "$raw_creds" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
if [ -z "$token" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Fetch usage from API
# ---------------------------------------------------------------------------
usage_json=$(curl -s -m 10 \
  -H "accept: application/json" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "authorization: Bearer $token" \
  -H "user-agent: claude-code" \
  "https://api.anthropic.com/oauth/usage" 2>/dev/null)

if [ -z "$usage_json" ]; then
  exit 0
fi

five_h_raw=$(printf '%s' "$usage_json" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
seven_d_raw=$(printf '%s' "$usage_json" | jq -r '.seven_day.utilization // empty' 2>/dev/null)
five_h_reset=$(printf '%s' "$usage_json" | jq -r '.five_hour.resets_at // ""' 2>/dev/null)
seven_d_reset=$(printf '%s' "$usage_json" | jq -r '.seven_day.resets_at // ""' 2>/dev/null)

if [ -n "$five_h_raw" ] && [ -n "$seven_d_raw" ]; then
  five_h=$(printf "%.0f" "$five_h_raw")
  seven_d=$(printf "%.0f" "$seven_d_raw")
  printf '%s\n%s\n%s\n%s\n' "$five_h" "$seven_d" "$five_h_reset" "$seven_d_reset" > "$CACHE_FILE"
fi
