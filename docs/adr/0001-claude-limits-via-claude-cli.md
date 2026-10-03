# Claude limits via `claude -p "/usage"` instead of the OAuth endpoint

The app reads the Claude limits by launching the installed Claude Code binary as a child process (`claude -p "/usage"` with `--output-format stream-json`) and evaluating only the `usage_report` field. It never touches credentials itself: no Keychain access, no token, no call to `api.anthropic.com`. There are two reasons. First, the OAuth token expires after 8 h, and the app must never refresh it itself, because refresh rotation can log Claude Code out. So the app would depend on Claude Code anyway. Second, the unmodified binary with your own subscription is the only route Anthropic explicitly permits. Reading the token, by contrast, could fall under "collect, store, or intermediate … session tokens".

## Considered Options

- **OAuth endpoint with the token from the Keychain** (via `/usr/bin/security`): fast (0.3 s). But the app would silently access someone else's credentials, the legal situation is unclear, and anyone who doesn't use Claude Code for 8 h sees no data.
- **A combination of both** (endpoint, falling back to the CLI once the token has expired): two code paths and two failure modes, against the guiding principle "simple".
- **claude.ai web API with the browser cookie:** prohibited by the terms of use, needs Full Disk Access.
- **The text of `/usage` as a fallback to `usage_report`:** localized, only accurate to the minute, and just as fragile as the field.

## Consequences

- Claude Code 2.1.283 or later must be installed and logged in. The app locates the binary itself: first in known locations, then via the login shell.
- The call runs isolated (`--safe-mode --setting-sources "" --strict-mcp-config`, empty cwd, clean environment), so user hooks or MCP servers don't run on every query. In exchange, anyone who reaches Claude Code only through a proxy configured in the settings gets no data.
- `usage_report` is marked experimental. If the field changes, the app shows the "unexpected response" state until a new release ships. There is deliberately no fallback and no live check.
