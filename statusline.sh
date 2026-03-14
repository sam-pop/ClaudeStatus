#!/bin/sh
input=$(cat)

# ---------------------------------------------------------------------------
# Single jq pass — extract all fields at once (#8)
# ---------------------------------------------------------------------------
eval "$(printf '%s' "$input" | jq -r '
  "model=" + ((.model.display_name // "") | @sh) +
  " dir=" + ((.workspace.current_dir // .cwd // "") | @sh) +
  " ctx_pct_raw=" + ((if .context_window.used_percentage == null then "" else (.context_window.used_percentage | tostring) end) | @sh) +
  " cache_read=" + ((.context_window.current_usage.cache_read_input_tokens // 0) | tostring | @sh) +
  " cache_create=" + ((.context_window.current_usage.cache_creation_input_tokens // 0) | tostring | @sh) +
  " input_tok=" + ((.context_window.current_usage.input_tokens // 0) | tostring | @sh) +
  " output_tok=" + ((.context_window.current_usage.output_tokens // 0) | tostring | @sh) +
  " ctx_total=" + ((.context_window.context_window_size // 0) | tostring | @sh)
' 2>/dev/null)"

# Defaults if jq failed
cache_read=${cache_read:-0}
cache_create=${cache_create:-0}
input_tok=${input_tok:-0}
output_tok=${output_tok:-0}
ctx_total=${ctx_total:-0}

# Short dir: parent/current
dir_prefix=""
dir_tail=""
eval "$(echo "$dir" | awk -v home="$HOME" '{
  sub(home, "~")
  n = split($0, parts, "/")
  if (n <= 3) {
    printf "dir_prefix='\'''\'' dir_tail='\''%s'\''", $0
  } else {
    printf "dir_prefix='\''%s/…/%s/'\'' dir_tail='\''%s'\''", parts[1], parts[n-1], parts[n]
  }
}')"

# ---------------------------------------------------------------------------
# Git branch + dirty indicator (#2)
# ---------------------------------------------------------------------------
branch=""
dirty=""
if git -C "$dir" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$dir" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null \
        || git -C "$dir" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  if [ -n "$(git -C "$dir" --no-optional-locks status --porcelain 2>/dev/null | head -1)" ]; then
    dirty="*"
  fi
fi

# ---------------------------------------------------------------------------
# Usage cache with staleness check (#6)
# ---------------------------------------------------------------------------
CACHE_FILE="/tmp/.claude_usage_cache"
CACHE_MAX_AGE=300
cache_stale=0
five_h=""
seven_d=""
five_h_reset=""
seven_d_reset=""

if [ -f "$CACHE_FILE" ]; then
  cache_mtime=$(stat -f %m "$CACHE_FILE")
  now=$(date +%s)
  cache_age=$(( now - cache_mtime ))
  [ "$cache_age" -gt "$CACHE_MAX_AGE" ] && cache_stale=1
  five_h=$(sed -n '1p' "$CACHE_FILE")
  seven_d=$(sed -n '2p' "$CACHE_FILE")
  five_h_reset=$(sed -n '3p' "$CACHE_FILE")
  seven_d_reset=$(sed -n '4p' "$CACHE_FILE")
else
  bash /Users/sam/.claude/fetch-usage.sh > /dev/null 2>&1 &
fi

# ---------------------------------------------------------------------------
# Context window
# ---------------------------------------------------------------------------
ctx_pct=""
ctx_tokens_str=""
if [ -n "$ctx_pct_raw" ]; then
  ctx_pct=$(printf "%.0f" "$ctx_pct_raw")
  if [ "$ctx_total" -gt 0 ] 2>/dev/null; then
    ctx_used=$(( cache_read + cache_create + input_tok + output_tok ))
    ctx_used_k=$(( ctx_used / 1000 ))
    ctx_total_k=$(( ctx_total / 1000 ))
    ctx_tokens_str="${ctx_used_k}k/${ctx_total_k}k"
  fi
fi

# ---------------------------------------------------------------------------
# Session cost estimate (cumulative per-turn tracking)
# ---------------------------------------------------------------------------
cost_str=""
COST_FILE="/tmp/.claude_cost_session"

if [ "$output_tok" -gt 0 ] 2>/dev/null; then
  case "$model" in
    *[Oo]pus*)  pricing="opus" ;;
    *[Hh]aiku*) pricing="haiku" ;;
    *)          pricing="sonnet" ;;
  esac

  prev_output=0
  prev_cost="0"
  if [ -f "$COST_FILE" ]; then
    prev_output=$(awk '{print $1}' "$COST_FILE")
    prev_cost=$(awk '{print $2}' "$COST_FILE")
  fi

  cost_data=$(awk -v cr="$cache_read" -v cc="$cache_create" \
                  -v it="$input_tok" -v ot="$output_tok" \
                  -v prev_ot="$prev_output" -v prev_cost="$prev_cost" \
                  -v p="$pricing" 'BEGIN {
    if      (p == "opus")  { ir=15;  outr=75; crr=1.5;  ccr=18.75 }
    else if (p == "haiku") { ir=0.8; outr=4;  crr=0.08; ccr=1     }
    else                   { ir=3;   outr=15; crr=0.3;  ccr=3.75  }

    cost = prev_cost + 0

    if (ot < prev_ot && prev_ot > 0) {
      # Session reset: output dropped → new session
      turn_cost = (it*ir + cr*crr + cc*ccr + ot*outr) / 1000000
      cost = turn_cost
    } else if (ot > prev_ot) {
      # New turn: output increased
      delta_out = ot - prev_ot
      turn_cost = (it*ir + cr*crr + cc*ccr + delta_out*outr) / 1000000
      cost = cost + turn_cost
    }

    if      (cost < 0.005) printf "<1¢\n"
    else if (cost < 1.00)  printf "%d¢\n", cost * 100
    else                   printf "$%.2f\n", cost

    printf "%d %.10f\n", ot, cost
  }')

  cost_str=$(echo "$cost_data" | sed -n '1p')
  echo "$cost_data" | sed -n '2p' > "$COST_FILE"
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

make_bar() {
  pct="$1"; width="$2"
  filled=$(( pct * width / 100 ))
  [ "$filled" -gt "$width" ] && filled="$width"
  bar=""; i=0
  while [ "$i" -lt "$filled" ]; do bar="${bar}▰"; i=$(( i + 1 )); done
  while [ "$i" -lt "$width" ];  do bar="${bar}▱"; i=$(( i + 1 )); done
  printf '%s' "$bar"
}

bar_color() {
  pct="$1"
  if   [ "$pct" -ge 85 ]; then printf '\033[38;2;255;100;100m'
  elif [ "$pct" -ge 60 ]; then printf '\033[38;2;255;190;80m'
  else                         printf '\033[38;2;100;220;160m'
  fi
}

compute_delta() {
  clean=$(echo "$1" | sed 's/\.[0-9]*//' | sed 's/[+-][0-9][0-9]:[0-9][0-9]$//' | sed 's/Z$//')
  reset_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$clean" "+%s" 2>/dev/null)
  [ -z "$reset_epoch" ] && return
  now_epoch=$(date -u "+%s")
  diff=$(( reset_epoch - now_epoch ))
  [ "$diff" -le 0 ] && echo "now" && return
  hours=$(( diff / 3600 ))
  minutes=$(( (diff % 3600) / 60 ))
  if [ "$hours" -ge 24 ]; then
    days=$(( hours / 24 ))
    rh=$(( hours % 24 ))
    echo "${days}d${rh}h"
  elif [ "$hours" -gt 0 ]; then echo "${hours}h${minutes}m"
  else echo "${minutes}m"
  fi
}

# ---------------------------------------------------------------------------
# Colors / glyphs
# ---------------------------------------------------------------------------
R='\033[0m'
DIM='\033[2m'
BOLD='\033[1m'

C_MODEL='\033[38;2;255;165;80m'
C_DIR='\033[38;2;80;210;200m'
C_BRANCH='\033[38;2;190;110;230m'
C_DIRTY='\033[38;2;255;190;80m'
C_LABEL='\033[38;2;120;130;150m'
C_GHOST='\033[38;2;70;80;95m'
C_COST='\033[38;2;160;180;120m'
C_STALE='\033[38;2;255;190;80m'

# ---------------------------------------------------------------------------
# Line 1 — identity
# ---------------------------------------------------------------------------
printf "${C_GHOST}⬡${R} ${BOLD}${C_MODEL}%s${R}" "$model"
printf "   ${C_GHOST}⌂${R} "
[ -n "$dir_prefix" ] && printf "${C_GHOST}%s${R}" "$dir_prefix"
printf "${BOLD}${C_DIR}%s${R}" "$dir_tail"
if [ -n "$branch" ]; then
  printf "  ${C_GHOST}⎇${R} ${C_BRANCH}%s${R}" "$branch"
  [ -n "$dirty" ] && printf "${C_DIRTY}%s${R}" "$dirty"
fi

# ---------------------------------------------------------------------------
# Line 2 — meters
# ---------------------------------------------------------------------------
printf '\n'
BAR_W=8
stale=""
[ "$cache_stale" -eq 1 ] 2>/dev/null && stale="?"
sep=""

# Context bar
if [ -n "$ctx_pct" ]; then
  bar=$(make_bar "$ctx_pct" "$BAR_W")
  bclr=$(bar_color "$ctx_pct")
  printf "${C_LABEL}ctx ${bclr}%s${R} ${BOLD}${C_LABEL}%s%%${R}" "$bar" "$ctx_pct"
  [ -n "$ctx_tokens_str" ] && printf " ${DIM}${C_LABEL}%s${R}" "$ctx_tokens_str"
  sep=1
fi

# 5h bar
if [ -n "$five_h" ]; then
  [ -n "$sep" ] && printf " ${C_GHOST}·${R} "
  bar=$(make_bar "$five_h" "$BAR_W")
  bclr=$(bar_color "$five_h")
  printf "${C_LABEL}5h ${bclr}%s${R} ${BOLD}${C_LABEL}%s%%${R}" "$bar" "$five_h"
  [ -n "$stale" ] && printf "${C_STALE}?${R}"
  if [ -n "$five_h_reset" ]; then
    delta=$(compute_delta "$five_h_reset")
    [ -n "$delta" ] && printf " ${DIM}${C_LABEL}↻ %s${R}" "$delta"
  fi
  sep=1
fi

# 7d bar
if [ -n "$seven_d" ]; then
  [ -n "$sep" ] && printf " ${C_GHOST}·${R} "
  bar=$(make_bar "$seven_d" "$BAR_W")
  bclr=$(bar_color "$seven_d")
  printf "${C_LABEL}7d ${bclr}%s${R} ${BOLD}${C_LABEL}%s%%${R}" "$bar" "$seven_d"
  [ -n "$stale" ] && printf "${C_STALE}?${R}"
  if [ -n "$seven_d_reset" ]; then
    delta=$(compute_delta "$seven_d_reset")
    [ -n "$delta" ] && printf " ${DIM}${C_LABEL}↻ %s${R}" "$delta"
  fi
  sep=1
fi

# Cost estimate (#9)
if [ -n "$cost_str" ]; then
  [ -n "$sep" ] && printf " ${C_GHOST}·${R} "
  printf "${DIM}${C_COST}~%s${R}" "$cost_str"
fi
