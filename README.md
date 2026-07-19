# Claude Status

A custom status line for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows everything you need at a glance.

```
⬡ Fable 5   ⌂ ~/…/2026/ClaudeStatus  ⎇ main*
ctx |||····· 48% 192k/400k · 5h ▰▱▱▱▱▱▱▱ 8% ↻ 4h 12m · 7d ▰▰▰▰▰▰▰▱ 87% ↻ 1d 8h · fable ▰▰▰▰▰▰▱▱ 74% ↻ 6d 12h
```

## What it shows

| Element | Description |
|---------|-------------|
| **Model** | Current Claude model (Opus, Sonnet, Haiku) |
| **Directory** | `~/…/parent/folder` — tilde-relative with smart truncation |
| **Git branch** | Current branch + `*` dirty indicator for uncommitted changes |
| **Context** | Pipe-style progress bar + percentage + token count (e.g. `192k/400k`) |
| **5h usage** | Rate-limit utilization with reset countdown |
| **7d usage** | Weekly rate-limit utilization with reset countdown |
| **Model usage** | Model-scoped weekly limit (e.g. Fable) with reset countdown — shown only when your plan has one |

### Visual indicators

- Progress bars change color: **green** (< 60%) -> **amber** (60-84%) -> **red** (85%+)
- Context bar uses pipes (`|||····`), usage bars use blocks (`▰▰▰▱▱▱`), so they read apart at a glance
- Stale cache data (> 5 min) marked with amber `?`
- Git dirty state shown as `*` next to branch name
- Directory prefix (`~/…/`) shown in muted color, current folder in bold

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- `jq` — JSON processor
- `curl` — for API usage fetching
- `git` — for branch/dirty detection

## Install

```sh
git clone https://github.com/sam-pop/ClaudeStatus.git
cd ClaudeStatus
bash install.sh
```

Then restart Claude Code.

### What the installer does

1. Copies `statusline.sh` and `fetch-usage.sh` to `~/.claude/`
2. Sets `statusLine` in `~/.claude/settings.json`
3. Adds hooks to fetch usage data in the background
4. Backs up your existing settings to `settings.json.bak`
5. Primes the usage cache

## Uninstall

```sh
bash uninstall.sh
```

Removes scripts, cleans settings, and deletes the cache. Your other Claude Code settings are preserved.

## How it works

**Status line** (`statusline.sh`): Receives JSON from Claude Code via stdin on every prompt. Extracts model, directory, context window data in a single `jq` pass. Renders two lines with ANSI color codes.

**Usage fetcher** (`fetch-usage.sh`): Runs in the background via Claude Code hooks (on every tool use and on stop). Calls the Anthropic API to get 5-hour and 7-day rate-limit utilization, plus any model-scoped weekly limit (e.g. Fable) reported in the account's `limits` array. Results are cached to `/tmp/.claude_usage_cache` with a 60-second throttle to avoid excessive API calls.

### Architecture

```
Claude Code
    |
    ├── stdin JSON ──> statusline.sh ──> rendered status bar
    |
    └── hooks ──> fetch-usage.sh ──> /tmp/.claude_usage_cache
                       |
                       └── Anthropic API (OAuth usage endpoint)
```

## Configuration

Edit `~/.claude/statusline-command.sh` directly to customize:

| Variable | Default | Description |
|----------|---------|-------------|
| `BAR_W` | `8` | Progress bar width (characters) |
| `CACHE_MAX_AGE` | `300` | Seconds before cache is marked stale |
| `C_MODEL` | warm orange | Model name color (RGB) |
| `C_DIR` | teal | Directory color (RGB) |
| `C_BRANCH` | violet | Git branch color (RGB) |

## Platform support

| Platform | Status line | Usage fetching |
|----------|-------------|----------------|
| macOS | Full support | Full support (Keychain) |
| Linux | Full support | Partial (needs credential file) |

On Linux, the usage fetcher looks for credentials in `~/.config/claude-code/credentials.json` or `~/.claude/credentials.json`.

## License

MIT
