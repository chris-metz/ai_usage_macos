# Claude-Limits über `claude -p "/usage"` statt über den OAuth-Endpunkt

Die App liest die Claude-Limits, indem sie das installierte Claude-Code-Binary als Kindprozess startet (`claude -p "/usage"` mit `--output-format stream-json`) und nur das Feld `usage_report` auswertet. Sie fasst nie selbst Credentials an: kein Keychain-Zugriff, kein Token, kein Aufruf von `api.anthropic.com`. Das hat zwei Gründe. Erstens läuft das OAuth-Token nach 8 h ab, und die App darf es nie selbst erneuern, weil die Refresh-Rotation Claude Code ausloggen kann. Auf Claude Code wäre die App also ohnehin angewiesen. Zweitens ist das unveränderte Binary mit dem eigenen Abo der einzige Weg, den Anthropic ausdrücklich erlaubt. Das Auslesen des Tokens könnte dagegen unter „collect, store, or intermediate … session tokens“ fallen.

## Considered Options

- **OAuth-Endpunkt mit Token aus dem Keychain** (über `/usr/bin/security`): schnell (0,3 s). Die App griffe aber lautlos auf fremde Credentials zu, die Rechtslage ist unklar, und wer Claude Code 8 h nicht nutzt, sieht keine Daten.
- **Kombination aus beidem** (Endpunkt, bei abgelaufenem Token das CLI): zwei Codepfade und zwei Fehlerbilder, gegen das Leitprinzip „einfach“.
- **claude.ai-Web-API mit Browser-Cookie:** von den Nutzungsbedingungen verboten, braucht Full Disk Access.
- **Text von `/usage` als Fallback zu `usage_report`:** lokalisiert, nur minutengenau und genauso fragil wie das Feld.

## Consequences

- Claude Code ab Version 2.1.283 muss installiert und angemeldet sein. Die App sucht das Binary selbst: erst an bekannten Orten, dann über die Login-Shell.
- Der Aufruf läuft abgeschottet (`--safe-mode --setting-sources "" --strict-mcp-config`, leeres cwd, saubere Umgebung), damit nicht bei jeder Abfrage User-Hooks oder MCP-Server laufen. Dafür bekommt keine Daten, wer Claude Code nur über einen Proxy erreicht, der in den Settings eingetragen ist.
- `usage_report` ist als experimentell markiert. Ändert sich das Feld, zeigt die App „Unerwartete Antwort“, bis ein neues Release kommt. Es gibt bewusst keinen Fallback und keinen Live-Check.
