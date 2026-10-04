# Usage response with no active session window

Task for [Capture the response when no session window is active](https://github.com/chris-metz/pacemark/issues/12) (map [Map: v1 spec for the menu bar app for Claude limits](https://github.com/chris-metz/pacemark/issues/1)). It closes open point 1 of [`claude-usage-antwort-echt.md`](claude-usage-antwort-echt.md).
Captured by Chris on 4 October 2026 at 08:23 (Europe/Berlin), before the first use of Claude that day. Claude Code **2.1.288** (2.1.289 arrived at 08:26, after both runs), Max 20x, macOS 27.

Terms such as session limit, window, utilization and reset time are defined in `GLOSSARY.md`. This document records measurements only, no decisions.

## What was run

```sh
claude -p --no-session-persistence --strict-mcp-config --output-format stream-json --verbose "/usage" < /dev/null \
  | jq 'select(.type=="assistant") | {limits: .usage_report.rate_limits.limits, text: .message.content[0].text}'
jq '.cachedUsageUtilization.utilization | {five_hour, limits}' ~/.claude.json
```

The first command filtered the output, so only `usage_report.rate_limits.limits` and the text were captured. The second shows the OAuth endpoint's response as Claude Code just cached it.

## Fixtures

- [`fixtures/claude-p-usage-no-session-window.stream.jsonl`](fixtures/claude-p-usage-no-session-window.stream.jsonl): the `assistant` and `result` messages. **Assembled, not raw:** it takes the envelope of [`claude-p-usage.stream.jsonl`](fixtures/claude-p-usage.stream.jsonl) and swaps in the captured `limits[]` and text. The `timestamp` comes from the shell history. `extra_usage`, `usage_report.session`, durations and token counters were not captured and are carried over from 3 October.
- [`fixtures/claude-p-usage-no-session-window.txt`](fixtures/claude-p-usage-no-session-window.txt): the text of `/usage`, without the statistics section "What's contributing to your limits usage?".

## Findings

**The `session` row is present.** It has `percent: 0` and `resets_at: null`:

```json
{ "kind": "session", "group": "session", "percent": 0, "resets_at": null,
  "scope": null, "severity": "normal", "is_active": false }
```

The OAuth response (via the cache) has the same shape: the same `session` row, plus a `five_hour` object with `utilization: 0` (not `null`) and `resets_at: null`:

```json
{ "utilization": 0, "resets_at": null, "limit_dollars": null, "used_dollars": null,
  "remaining_dollars": null, "locked_reason": null }
```

**The text drops the reset part:** `Current session: 0% used`, without "· resets …". The two weekly lines keep it.

What this means for parsing:

- Of the three shapes Claude Code's code expects (object missing, utilization `null`, reset time `null`), the real one is the third. Only `resets_at` shows that no window is running. `percent` is a plain `0`, so a parser that looks only at `percent` would read it as an active window at 0 %.
- **`is_active` doesn't say whether a window is running.** On 3 October the `session` row had `is_active: false` while a window ran at 14 %. Today it is `false` again, with no window. `weekly_all` was `true` both times. Don't derive the window from `is_active`.
- **Reset times jitter on both sides of the full minute.** The same weekly window reset at `2026-10-07T00:59:59.88…` on 3 October and at `2026-10-07T01:00:00.157284+00:00` today. That's about 0.3 s apart and now on the far side of the minute. So the earlier note that session and weekly limits "end shortly before the full minute" doesn't always hold. The Fable row stays at a whole second (`01:00:00+00:00`).
