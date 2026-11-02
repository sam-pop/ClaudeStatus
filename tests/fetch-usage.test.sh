#!/bin/sh
# Offline tests for fetch-usage.sh. Run: sh tests/fetch-usage.test.sh
# Uses CLAUDE_USAGE_JSON to inject an API response and CLAUDE_USAGE_CACHE to
# redirect the cache, so no credentials or network are touched.

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FETCH="$ROOT/fetch-usage.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fails=0

check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "ok   - $1"
  else echo "FAIL - $1"; echo "       expected: [$2]"; echo "       actual:   [$3]"; fails=$((fails + 1)); fi
}

run_fetch() { # json cache
  CLAUDE_USAGE_JSON="$1" CLAUDE_USAGE_CACHE="$2" sh "$FETCH"
}

line() { sed -n "${1}p" "$2"; }

# --- 1. Plan with no 5-hour window (five_hour: null) still caches 7d + scoped
cache="$TMP/c1"
run_fetch '{
  "five_hour": null,
  "seven_day": {"utilization": 9.0, "resets_at": "2026-11-08T03:00:00.836084+00:00"},
  "limits": [
    {"kind": "weekly_all", "percent": 9, "resets_at": "2026-11-08T03:00:00.836084+00:00", "scope": null},
    {"kind": "weekly_scoped", "percent": 6, "resets_at": "2026-11-08T02:59:59.836285+00:00",
     "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}}
  ]
}' "$cache"
check "no-5h: cache written"       "yes" "$([ -f "$cache" ] && echo yes || echo no)"
check "no-5h: five_hour empty"     ""    "$(line 1 "$cache")"
check "no-5h: seven_day"           "9"   "$(line 2 "$cache")"
check "no-5h: five_hour reset empty" ""  "$(line 3 "$cache")"
check "no-5h: seven_day reset"     "2026-11-08T03:00:00.836084+00:00" "$(line 4 "$cache")"
check "no-5h: scoped pct"          "6"   "$(line 5 "$cache")"
check "no-5h: scoped label"        "fable" "$(line 7 "$cache")"
check "no-5h: 7 lines"             "7"   "$(wc -l < "$cache" | tr -d ' ')"

# --- 2. Plan with both windows (regression guard for the original shape)
cache="$TMP/c2"
run_fetch '{
  "five_hour": {"utilization": 41.6, "resets_at": "2026-11-02T05:00:00+00:00"},
  "seven_day": {"utilization": 58.0, "resets_at": "2026-11-08T03:00:00+00:00"},
  "limits": []
}' "$cache"
check "both: five_hour"   "42" "$(line 1 "$cache")"
check "both: seven_day"   "58" "$(line 2 "$cache")"
check "both: 5h reset"    "2026-11-02T05:00:00+00:00" "$(line 3 "$cache")"
check "both: no scoped"   ""   "$(line 5 "$cache")"

# --- 3. Error / empty response must not clobber the last good cache
cache="$TMP/c3"
printf '1\n2\n\n\n\n\n\n' > "$cache"
touch -t 202001010000 "$cache"   # make it old enough to bypass the 60s throttle
run_fetch '{"type":"error","error":{"type":"authentication_error"}}' "$cache"
check "error: cache preserved" "1" "$(line 1 "$cache")"

echo
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
