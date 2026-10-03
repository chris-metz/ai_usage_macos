# Echte Usage-Antwort vom eigenen Claude-Account

Task zu [Echte Usage-Antwort vom eigenen Claude-Account abrufen](https://github.com/chris-metz/ai_usage_macos/issues/5) (Map [v1-Spec der Menüleisten-App für Claude-Limits](https://github.com/chris-metz/ai_usage_macos/issues/1)).
Stand: 3. Oktober 2026, gegen 11:50 Uhr (Europe/Berlin). Claude Code **2.1.288** auf macOS 27.

Baut auf der Recherche [Woher bekommt die App die Claude-Limits?](https://github.com/chris-metz/ai_usage_macos/blob/research/claude-limits-datenquelle/docs/research/claude-limits-datenquelle.md) auf. Kürzel wie A, D2 oder „offener Punkt 7“ beziehen sich auf dieses Dokument.
Begriffe wie Session-Limit, Wochenlimit, Fable-Limit, Fenster, Auslastung und Reset-Zeitpunkt sind in `GLOSSARY.md` definiert.

Dieses Dokument enthält nur Messungen und keine Entscheidung.

**Was gemacht wurde**

- **`claude -p "/usage"`** (D2) dreimal ausgeführt, als Text und als `stream-json`, aus einem leeren Probe-Verzeichnis und ohne die `CLAUDE*`-Umgebungsvariablen der aufrufenden Session.
- **`GET https://api.anthropic.com/api/oauth/usage`** (A) **genau einmal** aufgerufen, mit dem aktuellen Access-Token aus dem Keychain-Eintrag `Claude Code-credentials`. Der User-Agent war `ai-usage-probe/0`. Das Token blieb im Speicher eines Python-Prozesses, ein Refresh fand **nicht** statt.
- Den Cache in `~/.claude.json` (C1) vor und nach jedem Aufruf angeschaut.
- **Nicht gemacht:** die claude.ai-Web-API (B). Laut Recherche hat sie dieselbe Antwortform, braucht aber das Browser-Cookie.

**Geschwärzt:** Session-, Nachrichten- und Request-IDs, UUIDs, Org- und Workspace-ID. **Gekürzt:** In der Textausgabe von `/usage` der Abschnitt „What's contributing to your limits usage?“, eine lokale Statistik zu Requests, Skills und Subagents, die für die App keine Rolle spielt.

**Fixtures** (Rohdaten, so geschwärzt wie oben beschrieben):

- [`fixtures/oauth-usage.json`](fixtures/oauth-usage.json): Antwort von A, unverändert (sie enthält keine IDs)
- [`fixtures/claude-p-usage.stream.jsonl`](fixtures/claude-p-usage.stream.jsonl): `assistant`- und `result`-Nachricht von D2 mit `--output-format stream-json`
- [`fixtures/claude-p-usage.txt`](fixtures/claude-p-usage.txt): Textausgabe von D2

---

## Antworten auf die Fragen des Tickets

### Welches Abo hat der Account?

**Max 20x.**

- Keychain-Eintrag: `subscriptionType: "max"`, `rateLimitTier: "default_claude_max_20x"`.
- `~/.claude.json` → `oauthAccount`: `organizationType: "claude_max"`, `organizationRateLimitTier: "default_claude_max_20x"`, `billingType: "stripe_subscription"`.
- Usage-Credits sind eingerichtet, aber leer (`extra_usage.disabled_reason: "out_of_credits"`). Für die drei Limits spielt das keine Rolle.

### Ist das Fable-Limit enthalten?

**Ja, auf allen gemessenen Wegen.** Gemessen wurde aber nur dieser Max-Account (siehe [Offen](#offen)).

- **A:** als Zeile in `limits[]` mit `kind: "weekly_scoped"`, `group: "weekly"`, `scope.model.display_name: "Fable"` (dazu `scope.model.id: null`).
- **D2 (`usage_report`):** dieselbe Zeile, aber ohne `scope.model.id`.
- **D2 (Text):** `Current week (Fable): 0% used · resets Oct 7 at 3am (Europe/Berlin)`.
- **Nur in `limits[]`:** Die flachen Felder (`five_hour`, `seven_day`, `seven_day_*`) enthalten **kein** Fable-Fenster. Wer das Fable-Limit braucht, muss `limits[]` lesen.

### In welchen Feldern stehen Fenster und Reset-Zeitpunkt?

| Limit | A, flache Felder | A und D2, `limits[]` | D2, Text |
|---|---|---|---|
| Session-Limit | `five_hour.utilization` (Float, `14.0`), `five_hour.resets_at` | `kind: "session"`, `percent` (Int, `14`), `resets_at` | `Current session: 14% used · resets Oct 3 at 1:09pm (Europe/Berlin)` |
| Wochenlimit | `seven_day.utilization`, `seven_day.resets_at` | `kind: "weekly_all"` | `Current week (all models): 36% used · resets Oct 7 at 2:59am (Europe/Berlin)` |
| Fable-Limit | — | `kind: "weekly_scoped"`, `scope.model.display_name: "Fable"` | `Current week (Fable): 0% used · resets Oct 7 at 3am (Europe/Berlin)` |

- **Fensterbeginn:** Er steht nicht in der Antwort. Für das Session-Limit gilt `resets_at` minus 5 h. Für das Wochenlimit gibt es zusätzlich `seven_day_breakdown.window_started_at`, und der Wert lag auf die Mikrosekunde genau 7 Tage vor `seven_day.resets_at` (`2026-09-30T00:59:59.884973+00:00`). Das bestätigt die Recherche.
- **Zeitformat:** ISO 8601 mit `+00:00`. Session- und Wochenlimit haben Mikrosekunden (`2026-10-03T11:09:59.884952+00:00`), die Fable-Zeile hat keine Nachkommastellen (`2026-10-07T01:00:00+00:00`). Auch das bestätigt die Recherche.
- **Neu: Ein Reset-Zeitpunkt springt im Bruchteil einer Sekunde.** Drei Abrufe innerhalb von 2 min lieferten für das Session-Limit `…11:09:59.816850`, `…11:09:59.884952` und `…11:09:59.823825`, beim Wochenlimit ebenso. Ob ein neues Fenster begonnen hat, lässt sich also nicht durch Vergleich auf exakte Gleichheit erkennen.
- **Neu: Session- und Wochenlimit enden kurz vor der vollen Minute** (`11:09:59.88`, `00:59:59.88`), die Fable-Zeile endet glatt (`01:00:00`). Darum zeigt der Text für das Wochenlimit „2:59am“ und für Fable „3am“, obwohl beide fachlich zum selben Wochenreset gehören.
- **Neu: `utilization` ist in den flachen Feldern ein Float** (`14.0`). Im Cache hatte die Recherche eine ganze Zahl gesehen. `limits[].percent` ist eine ganze Zahl. Ein Parser muss beides annehmen.
- `severity` war in allen drei Zeilen `"normal"`. `is_active` war nur beim Wochenlimit `true`.

### Wie sieht die Antwort aus, wenn gerade kein Session-Fenster aktiv ist?

**Nicht beobachtet.** Während der Messung lief ein Session-Fenster (14 %, Reset um 13:09 Uhr).

Aus dem Code von Claude Code geht hervor, dass es mit allen drei Formen rechnet. Beim Aufbau des Texts überspringt es ein Limit, wenn das Objekt fehlt oder `utilization` `null` ist, und lässt den Reset-Teil weg, wenn `resets_at` `null` ist [CC: `for(let{title:r,limit:l}of s){if(!l||l.utilization===null)continue;let u=l.resets_at?\` \xB7 resets ${…}\`:"";…}`]. Welche Form der Server tatsächlich schickt, ist damit offen.

Nachmessen lässt sich das morgens vor der ersten Nutzung von Claude, weil `/usage` selbst kein Fenster öffnet (siehe unten):

```sh
claude -p --no-session-persistence --strict-mcp-config --output-format stream-json --verbose "/usage" < /dev/null \
  | jq 'select(.type=="assistant") | .usage_report.rate_limits.limits'
```

---

## Weitere Befunde

### Keychain: Lesen über `/usr/bin/security` zeigt keinen Dialog

- `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w` lieferte das Geheimnis nach 0,02 s, **ohne Dialog**. Das war bei beiden Lesevorgängen so.
- Eine Erklärung (Folgerung aus Recherche E): Claude Code legt den Eintrag selbst über `/usr/bin/security` an, also gilt `security` als vertraute App des Eintrags. Damit kann **jeder Prozess des Users** das Token über `security` lesen, ohne dass der User es merkt.
- **Nicht getestet:** ob eine signierte App, die über Security.framework (`SecItemCopyMatching`) liest, einen Dialog bekommt. Nach Recherche E ist das zu erwarten.
- Der Eintrag enthält `claudeAiOauth` und `mcpOAuth`. Damit ist offener Punkt 8 für diesen Rechner beantwortet: `claudeAiOauth` ist da. Seine Schlüssel sind `accessToken`, `refreshToken`, `expiresAt`, `refreshTokenExpiresAt`, `scopes`, `subscriptionType` und `rateLimitTier`.
- `scopes`: `user:file_upload`, `user:inference`, `user:mcp_servers`, `user:plugins`, **`user:profile`**, `user:sessions:claude_code`.
- **Ein Access-Token gilt 8 h.** Zuletzt geändert wurde der Eintrag um 06:32:46Z, `expiresAt` war 14:32:46Z. Das beantwortet einen Teil von offenem Punkt 1.
- **Das Refresh-Token hat ein eigenes Ablaufdatum:** `refreshTokenExpiresAt` steht auf 2026-10-21T10:21Z, also in rund 18 Tagen. Ob es bei einem Refresh verlängert wird, ist offen. Läuft es ab, muss der User in Claude Code `/login` ausführen, und dann liefern A und D2 keine Daten mehr.

### A: OAuth-Endpunkt

- **Status 200** nach 0,3 s, 2549 Bytes. Der Endpunkt nahm einen eigenen User-Agent an. Man muss sich also nicht als Claude Code ausgeben.
- Schon der Pfad ohne Query-Flags (`/api/oauth/usage`) liefert `limits[]`, `spend` und `seven_day_breakdown`.
- **Die Antwort hat keine Rate-Limit-Header**, nur `request-id`, `anthropic-organization-id`, `anthropic-workspace-id` und Cloudflare-Header.
- **Neu: ein weiteres Fenster unter einem Codenamen mit Werten:** `iguana_necktie: { utilization: 0.0, resets_at: "2026-11-05T07:59:00+00:00", limit_dollars: 250, used_dollars: 0.0, remaining_dollars: 250.0 }`. Was es bedeutet, ist unbekannt. Alle anderen Codenamen waren `null`. Die flachen Felder ändern sich also laufend, maßgeblich für die Limits ist `limits[]`.

### D2: `claude -p "/usage"`

- **Es fallen keine Modellaufrufe an.** Die Nachricht hat `message.model: "<synthetic>"`, und alle Token-Zähler, `total_cost_usd`, `num_turns` und `duration_api_ms` stehen auf 0. Damit ist offener Punkt 7 beantwortet.
- **Laufzeit: etwa 2,1–2,2 s Wandzeit**, davon 0,8–1,3 s laut `duration_ms` in Claude Code selbst. Ohne `< /dev/null` wartet `claude` zusätzlich 3 s auf stdin und schreibt eine Warnung nach stderr.
- **`usage_report`** hängt direkt an der `assistant`-Nachricht (nicht unter `message`). Es enthält `rate_limits.limits[]` mit denselben drei Zeilen wie A und `rate_limits.extra_usage`, aber **keine flachen Felder**. Dazu kommt `session` mit Kosten und Dauer des Aufrufs (alles 0).
- **Claude Code holt die Werte selbst vom Endpunkt** und schreibt sie dabei in den Cache, wenn der letzte Abruf über 60 s her ist. Bei einem zweiten Aufruf nach rund 10 s blieb der Cache unverändert, die Antwort stammte also vermutlich aus dem 60-s-Snapshot (Recherche A, „Rate-Limits“).
- **Ohne Flag schreibt jeder Aufruf ein Transkript** von etwa 4,8 KB nach `~/.claude/projects/<Verzeichnis>/`. Mit `--no-session-persistence` entsteht keins.
- Dieser Aufruf hat funktioniert:

  ```sh
  claude -p --no-session-persistence --strict-mcp-config --settings '{"remoteControlAtStartup":false}' \
    --output-format stream-json --verbose "/usage" < /dev/null
  ```

- **Der Text ist zum Parsen ungünstig:** Die Zeiten sind lokalisiert und nur minutengenau („Oct 3 at 1:09pm (Europe/Berlin)“), und es folgt ein langer Statistikteil. `usage_report` ist die strukturierte Fassung derselben Daten.

### Wo liegt `claude`?

- Im Shell-PATH findet sich nur die Version, die mise installiert hat: `~/.local/share/mise/installs/claude/latest/claude` (2.1.288), dazu der mise-Shim.
- `~/.local/bin/claude`, der Ort des offiziellen nativen Installers, ist ein **toter Symlink** auf `~/.local/share/claude/versions/2.1.270`, das es nicht mehr gibt.
- **GUI-Apps erben den PATH der Shell nicht.** `launchctl getenv PATH` ist leer, eine App bekommt also nur `/usr/bin:/bin:/usr/sbin:/sbin`. Eine App, die `claude` startet, findet es auf diesem Rechner nicht von selbst. Die Login-Shell ist fish.

### C1: Cache in `~/.claude.json`

- Vor den Aufrufen war er 1508 min alt (rund 25 h), ähnlich wie bei der Recherche.
- `claude -p "/usage"` hat ihn aktualisiert. Wer D2 aufruft, frischt also auch C1 auf.

---

## Offen

1. **Form der Antwort bei inaktivem Session-Fenster.** Nachmessen mit dem Befehl oben, morgens vor der ersten Nutzung von Claude.
2. **Ob eine signierte App über Security.framework einen Dialog bekommt.** Getestet wurde nur das Werkzeug `security`.
3. **Ob es auf Pro eine Fable-Zeile gibt.** Es steht nur ein Max-Account zur Verfügung.
4. **Ob `refreshTokenExpiresAt` bei einem Refresh verlängert wird**, oder ob nach rund 18 Tagen ohnehin ein neuer `/login` nötig ist.
