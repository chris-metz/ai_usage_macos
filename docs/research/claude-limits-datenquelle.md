# Woher bekommt die App die Claude-Limits?

Recherche zu [#2](https://github.com/chris-metz/ai_usage_macos/issues/2) (Map [#1](https://github.com/chris-metz/ai_usage_macos/issues/1)).
Stand: 3. Oktober 2026. Untersucht wurde Claude Code **2.1.288** (Build vom 2026-10-02) auf macOS 27.

Dieses Dokument enthält nur Fakten und keine Entscheidung. Welche Datenquelle v1 nutzt, wird im Folgeticket entschieden.
Begriffe wie Session-Limit, Wochenlimit, Fable-Limit, Fenster, Auslastung, Reset-Zeitpunkt und Pace sind in `GLOSSARY.md` im Repo-Root definiert.

**Was für diese Recherche gemacht wurde und was nicht**

- Es wurde **kein Endpunkt mit den Credentials des Users aufgerufen** und **kein Geheimnis aus der Keychain gelesen**.
- Gelesen wurden nur lokale Dinge: das Claude-Code-Binary (per `strings`), die *Struktur* der Datei `~/.claude.json` (Feldnamen, Typen, Zeitstempel, keine Werte von Tokens) und die *Attribute* des Keychain-Eintrags (ohne `-w`/`-g`, also ohne Geheimnis).
- Quellen stehen in eckigen Klammern hinter jeder Aussage und sind am Ende aufgelöst. `[CC]` steht für das Claude-Code-Binary. Dort ist jeweils ein Code-Ausschnitt angegeben, nach dem man mit `strings -n 6 "$(which claude)" | grep -F '…'` suchen kann.

---

## Überblick

| Kandidat | Session-Limit | Wochenlimit | Fable-Limit | Reset-Zeitpunkt | Status | Braucht Token/Keychain? | Hauptrisiko |
|---|---|---|---|---|---|---|---|
| **A. OAuth-Usage-Endpunkt** `GET api.anthropic.com/api/oauth/usage` | ja (`five_hour`) | ja (`seven_day`) | **ja** (`limits[]`, `kind: weekly_scoped`, `scope.model.display_name: "Fable"`) | ja, ISO 8601 | inoffiziell, intern | ja, OAuth-Token aus `Claude Code-credentials` | Token-Refresh kollidiert mit Claude Code; Keychain-Freigabe kann verloren gehen; Nutzungsbedingungen |
| **B. claude.ai-Web-API** `GET claude.ai/api/organizations/{org}/usage` | ja | ja | ja (gleiches `limits[]`) | ja | inoffiziell, intern | Session-Cookie aus dem Browser | Cookie-Zugriff (Full Disk Access bzw. Keychain „Safe Storage“), Cloudflare-Sperren, Nutzungsbedingungen |
| **C1. Cache in `~/.claude.json`** (`cachedUsageUtilization`) | ja | ja | ja | ja | intern, undokumentiert | nein | nur so aktuell wie der letzte Abruf durch Claude Code (lokal beobachtet: fast 24 h alt) |
| **C2. Transkripte** `~/.claude/projects/**/*.jsonl` (ccusage-Weg) | nur geschätzt | nein | nein | nur geschätzt | Dateiformat intern | nein | keine Auslastung in %, nur Tokens |
| **D1. Statusline-JSON** `rate_limits` | ja | ja | **nein** | ja, Epoch-Sekunden | **dokumentiert** | nein (Claude Code liefert) | nur während einer laufenden Claude-Code-Session, kein Fable |
| **D2. `claude -p "/usage"`** (Text plus `usage_report`) | ja | ja | ja | ja | Ausgabe als Weg dokumentiert, Strukturfeld experimentell | nein (Claude Code holt selbst) | Prozessstart pro Abfrage, Textformat, experimentelles Feld |
| **D3. Agent SDK `usage_EXPERIMENTAL_…()`** / Control-Request `get_usage` | ja | ja | ja (`model_scoped[]`) | ja, ISO 8601 | ausdrücklich experimentell | nein (Claude Code holt selbst) | „may change or be removed in any release without notice“ |

---

## A. OAuth-Usage-Endpunkt (`/api/oauth/usage`)

### Aufruf

- Claude Code ruft für `/usage` den Pfad `/api/oauth/usage` auf. Es gibt zwei Varianten mit Query-Flags: `?at_wall=1&skip_spend=1` und `?cedar_ember=1&skip_spend=1` [CC: `var Hie={plain:"/api/oauth/usage",at_wall:"/api/oauth/usage?at_wall=1&skip_spend=1",cedar_ember:"/api/oauth/usage?cedar_ember=1&skip_spend=1"}`].
- Die Basis-URL ist `https://api.anthropic.com` [CC: `BASE_API_URL:"https://api.anthropic.com"`]; [CB-fetcher Z. 61–64].
- Header: `Authorization: Bearer <access_token>` und `anthropic-beta: oauth-2025-04-20` [CC: ``b={Authorization:`Bearer ${Q}`,"anthropic-beta":fp}`` mit `fp="oauth-2025-04-20"`]; [CB-claude Z. 153–159]. CodexBar setzt zusätzlich `User-Agent: claude-code/<version>`, gibt sich also als Claude Code aus [CB-fetcher Z. 81–93, 189–192].
- Claude Code fragt mit 5 s Timeout an und erneuert vorher bei Bedarf das Token (`refreshOAuth:!0`) [CC: `qt.get(r,{timeout:5000,headers:{"Content-Type":"application/json"},refreshOAuth:!0,credentials:e,validateStatus:Lie})`].
- Der Endpunkt verlangt den Scope **`user:profile`**. Ohne diesen Scope liefert Claude Code keine Limits [CC: `function Qp(){let e=mn()?.scopes;return Array.isArray(e)&&e.includes(C4)}` mit `C4="user:profile"`; SDK-Typ: „False when plan rate limits do not apply (API key, Bedrock, Vertex, or missing profile scope)“, SDK Z. 4268]; [CB-claude Z. 151–152].

### Felder

Claude Code validiert die Antwort mit diesem Schema [CC: `Twn=f(()=>{let e=gt({utilization:un().nullable(),resets_at:pe().nullable()}).passthrough(),n=gt({five_hour:e.nullish(),seven_day:e.nullish(),…limits:tr(gt({kind:pe(),group:pe(),percent:un(),resets_at:pe().nullable(),severity:pe(),is_active:Ao(),scope:gt({model:gt({display_name:pe()})…`]:

- `five_hour`, `seven_day`, `seven_day_oauth_apps`, `seven_day_opus`, `seven_day_sonnet`, `cinder_cove`: jeweils `{ utilization: number|null, resets_at: string|null }`
- `extra_usage`: `{ is_enabled, monthly_limit, used_credits, utilization, currency, disabled_reason }`
- `limits[]`: `{ kind, group, percent, resets_at, severity, is_active, scope: { model: { display_name }, surface: { display_name } } }`

Was die Felder bedeuten, beschreibt Claude Code im Schema seines `/usage`-Berichts [CC: `eYr=f(()=>u({session:…,rate_limits:u({limits:k(u({kind:o().max(Ge).describe("The server's meter kind, e.g. 'session', 'weekly_all' or 'weekly_scoped'. Classify a row on this, never on a label.")…`]:

- `kind`: zum Beispiel `session`, `weekly_all` oder `weekly_scoped`. Zeilen soll man nach `kind` einordnen, nie nach dem Anzeigenamen.
- `group`: zum Beispiel `session` oder `weekly`.
- `percent`: Anteil am Fenster, 0–100.
- `resets_at`: ISO 8601.
- `severity`: zum Beispiel `normal`, `warning` oder `critical`.
- `is_active`: die Zeile, die eine Anzeige mit nur einem Wert zeigen soll.
- Zum Gesamtbild gehört dieser Satz aus dem Schema: „which meters apply, their scope, labels, severity and order are the server's, so a client renders them verbatim and a new meter needs no client release.“

**Lokal beobachtete Antwort:** Claude Code legt die letzte Antwort in `~/.claude.json` ab (siehe C1). Ihre Struktur zeigt mehr Felder, als das Schema prüft [LOKAL]:

- `five_hour` und `seven_day` haben zusätzlich `limit_dollars`, `used_dollars`, `remaining_dollars` und `locked_reason`. `utilization` ist dort eine ganze Zahl.
- Es gibt weitere Fenster unter Codenamen, die alle `null` waren, zum Beispiel `seven_day_cowork`, `seven_day_omelette`, `tangelo`, `cedar_ember` und `juniper_tide`.
- `limits[]` enthielt drei Zeilen: `session`/`session`, `weekly_all`/`weekly` (`is_active: true`) und `weekly_scoped`/`weekly` mit `scope: {"model": {"id": null, "display_name": "Fable"}, "surface": null}`.
- Dazu kommen `spend`, `member_dashboard_available` und `seven_day_breakdown: { as_of, window_started_at, rows[{key, display_name, percent}] }`.
- Format der Zeitstempel: `2026-10-07T01:00:00.123319+00:00`, also mit Mikrosekunden. Die Fable-Zeile hatte aber `2026-10-07T01:00:00+00:00`, ohne Nachkommastellen. Ein Parser muss also beide Formen lesen können.

### Fable-Limit

- **Ja, das Fable-Limit ist enthalten**, als `limits[]`-Eintrag mit `kind: "weekly_scoped"`, `group: "weekly"` und `scope.model.display_name: "Fable"` [LOKAL]; [CB-claude Z. 164]; [CB-mapper Z. 21–22].
- Claude Code zeigt solche Zeilen nur an, wenn der Modellname auf einer Allowlist steht. Standardmäßig enthält sie `["Fable","Fable 5","Fable 5.1"]`, der Server kann sie über das Feature-Flag `tengu_usage_overage_included_models` ändern [CC: `var Eie=Object.freeze(["Fable","Fable 5","Fable 5.1"])`, `var OF="tengu_usage_overage_included_models"`, `function Oft(e,n){…filter((s)=>r.includes(s.scope.model.display_name.toLowerCase()))…title:\`Current week (${s.scope.model.display_name})\`…}`].
- Fachlich gilt: Auf **Max** darf man „up to 50% of your weekly usage limits on Fable models“ nutzen. Auf **Pro** und Standard-Team-Seats sind Fable 5 und 5.1 „aren't included in your plan's usage limits“ und laufen nur über Usage-Credits [S-fable, Stand 2. Sept. 2026]. **Auf Pro gibt es also vermutlich gar keine Fable-Zeile.** Das ist eine Folgerung aus dem Support-Artikel, nicht gemessen.
- Ein CodexBar-Kommentar nennt Fable ein Beispiel „during a promotional access window“ und empfiehlt, nicht fest auf „Fable“ zu prüfen, sondern auf `weekly_scoped` [CB-fetcher Z. 271–274]; [CB-mapper Z. 75–78].

### Fensterbeginn und Reset-Zeitpunkt

- Der **Reset-Zeitpunkt** steht direkt in der Antwort, in `resets_at` beziehungsweise `limits[].resets_at` (siehe oben).
- Einen **Fensterbeginn** gibt es für `five_hour`/`seven_day` nicht als eigenes Feld. Claude Code rechnet ihn selbst aus: Beginn = `resets_at` minus Fensterlänge, mit 18000 s für das Session-Limit und 604800 s für das Wochenlimit [CC: `mwn=[{rateLimitType:"five_hour",windowSeconds:18000,…},{rateLimitType:"seven_day",windowSeconds:604800,…}]` und `function gwn(e,n){let r=Date.now()/1000,s=e-n,g=r-s;return Math.max(0,Math.min(1,g/n))}`]. Das ist genau die Pace aus dem Glossar.
- Für das Wochenlimit liefert die lokal beobachtete Antwort zusätzlich `seven_day_breakdown.window_started_at`. Der Wert lag exakt 7 Tage vor `seven_day.resets_at` (`2026-09-30T01:00…` gegenüber `2026-10-07T01:00…`) [LOKAL]. Das Feld prüft Claude Code nicht.
- Der Reset der Fable-Zeile fiel mit dem Reset des Wochenlimits zusammen (`2026-10-07T01:00`) [LOKAL]. Das passt zur Aussage, dass Fable aus dem Wochenlimit schöpft [S-fable].
- Laut Support setzt sich das Session-Limit „every five hours“ zurück, und das Wochenlimit „resets at a fixed time each week that is assigned to your account“ [S-max].

### Dokumentiert? Stabil?

- **Nicht dokumentiert.** In der gesamten Claude-Code-Doku (`code.claude.com/docs/llms-full.txt`, 8,7 MB) kommt weder `oauth/usage` noch `organizations/…/usage` vor [D-full, Suche am 2026-10-03].
- Es gibt Hinweise auf Bewegung: Claude Code führt Fallback-Pfade für ältere Server („a server that predates them“) und erlaubt unbekannte Felder (`.passthrough()`) [CC: Schema `eYr`, `Twn`]. Zuletzt kamen laut Changelog neue Formen hinzu: „Fixed the weekly Fable limit not appearing in `/usage` … when telemetry is disabled“ (2.1.283) und „Fixed `/usage` … dropping a model-specific weekly limit row …“ (2.1.261) [D-cl]. CodexBar beschreibt `limits[]` als „Newer shape (superseding the flat `seven_day_*` fields …)“ [CB-fetcher Z. 271–274].

### Token-Ablauf und Refresh

- Wie lange ein Token gilt, legt der Server fest (`expires_in`). Claude Code speichert `expiresAt = now + expires_in` [CC: `let{access_token:B,refresh_token:K=e,expires_in:V}=D,G=Date.now()+V*1000`]. Wie lang die Laufzeit konkret ist, wurde nicht ermittelt, weil dafür das Geheimnis gelesen werden müsste (siehe offene Punkte).
- Für den Refresh schickt Claude Code `POST https://platform.claude.com/v1/oauth/token` mit `grant_type: "refresh_token"`, `refresh_token`, `client_id` und `scope` [CC: `TOKEN_URL:"https://platform.claude.com/v1/oauth/token"`, `x={grant_type:"refresh_token",refresh_token:e,client_id:s??pn().CLIENT_ID,scope:A.join(" ")}`]; [CB-creds Z. 28].
- **Refresh-Tokens rotieren.** Claude Code übernimmt einen neuen `refresh_token` aus der Antwort, sonst behält es den alten (`refresh_token:K=e`) [CC]. CodexBar schreibt dazu ausdrücklich: „Claude Code rotates refresh tokens“ [CB-creds Z. 745–747].
- Wie Claude Code sich mit sich selbst abstimmt:
  - Mehrere Claude-Code-Prozesse sperren sich gegenseitig über die Datei `~/.claude/.oauth_refresh.lock` (mit `.owner`) [CC: `.oauth_refresh.lock`, `FC=".oauth_refresh.lock.owner"`].
  - Gespeichert wird per Compare-and-Swap: Hat sich der gespeicherte Refresh-Token inzwischen geändert, übernimmt Claude Code den neueren Stand („adopted_sibling“) [CC: `if(!(B.claudeAiOauth!==void 0&&…(K===""||K===n)))return v=!0,B` … `"tengu_oauth_refresh_save_adopted_newer_write"`].
  - Bei `invalid_grant` gilt der Refresh-Token als tot. Claude Code leert dann gespeichertes Access- und Refresh-Token, aber nur, wenn noch genau dieser Token gespeichert ist [CC: `tengu_oauth_refresh_token_marked_dead_invalid_grant`, `{...h,refreshToken:"",accessToken:"",expiresAt:0}`]. Danach meldet Claude Code „Login expired · Please run /login“ [D-auth].
- **Was das für eine fremde App bedeutet** (Folgerung aus den Punkten oben):
  - Erneuert die App das Token selbst und **schreibt es nicht zurück**, wird der Refresh-Token von Claude Code durch die Rotation ungültig. Claude Code löscht dann beim nächsten Refresh seine Anmeldung, und der User muss `/login` ausführen.
  - **Schreibt die App zurück**, verändert sie den Keychain-Eintrag von Claude Code, ohne an dessen Lock teilzunehmen. Dafür braucht sie außerdem Schreibrechte auf einen fremden Eintrag.
  - CodexBar macht deshalb Folgendes: Es schreibt die Credentials von Claude Code nie um („CLI credentials are never rewritten“ [CB-claude Z. 144]). Eine Token-Kette, die nachweislich Claude Code gehört, erneuert es nicht selbst („never rotate a chain we cannot prove we own“ [CB-creds Z. 771–774]). Stattdessen lässt es `claude` den Refresh erledigen („delegated OAuth refresh through `claude`“, im Hintergrund per `claude /status` [CB-claude Z. 110–111, 150]).
- Ein langlebiges Token aus `claude setup-token` (ein Jahr gültig) taugt **nicht** für den Endpunkt. Laut Doku „can only make model requests“ [D-auth]. Claude Code gibt `CLAUDE_CODE_OAUTH_TOKEN` standardmäßig nur den Scope `user:inference` [CC: `function ck(e=["user:inference"])`]. CodexBar sagt dasselbe [CB-claude Z. 151–152].

### Keychain-Zugriff

Siehe Abschnitt [E](#e-keychain-zugriff-aus-einer-fremden-app). Kurz: Die App würde einen fremden Eintrag lesen, also erscheint ein Abfrage-Dialog. „Immer erlauben“ hält nicht zuverlässig, weil Claude Code den Eintrag laufend neu schreibt.

### Rate-Limits

- Anthropic veröffentlicht keine Zahlen. Der Endpunkt antwortet aber nachweislich mit 429 und 403:
  - Claude Code merkt sich solche Antworten pro Bearer-Token und fragt dann `Retry-After` lang nicht mehr. Ohne `Retry-After` wartet es 5 min, höchstens 1 h. Nach einer abgelehnten Anmeldung wartet es 1 h [CC: `var Cie=300000,IF=3600000,Mie=3600000` … `w=Math.min(A>0?A:Cie,IF)` … `"remembered for this bearer; not asking again for"`].
  - Eine Antwort, die jünger als 60 s ist, verwendet Claude Code wieder, ohne neu zu fragen [CC: `V8e=60000`, `"Usage read answered from a snapshot … old; endpoint not asked"`].
  - Changelog 2.1.284: „Fixed repeated calls to the plan-usage endpoint after it rate-limits or rejects your login … now back off instead of re-asking“ [D-cl]. Changelog 2.1.208: bei Rate-Limit „last-known usage bars with an ‚as of‘ note“ [D-cl].
  - CodexBar wartet nach einer 429 standardmäßig 5 min [CB-gate Z. 6, 29–43].

### Nutzungsbedingungen

- Zitat aus der Claude-Code-Rechtsseite: „OAuth authentication … is designed to support ordinary use of Claude Code and other native Anthropic applications.“ Und weiter: „developers may not collect, store, or intermediate Claude.ai credentials or session tokens“. Außerdem: „Anthropic reserves the right to take measures to enforce these restrictions … without prior notice.“ [D-legal]
- In den Consumer Terms §3 steht: kein Zugriff „through automated or non-human means, whether through a bot, script, or otherwise“, ausgenommen über einen API-Key oder „where we otherwise explicitly permit it“ [T-consumer].
- Ob eine lokale App, die das Token des Users nur liest, unter „collect … credentials“ fällt, beantworten die Quellen nicht ausdrücklich (siehe offene Punkte).

---

## B. claude.ai-Web-API (Session-Cookie)

- **Aufruf.** Alle Anfragen tragen `Cookie: sessionKey=<value>`, der Cookie-Wert beginnt mit `sk-ant-…` [CB-claude Z. 219–220, 226–234]; [CB-web Z. 111, 653–655]:
  - `GET https://claude.ai/api/organizations` liefert die Org-UUID.
  - `GET https://claude.ai/api/organizations/{orgId}/usage?cedar_ember=1` liefert die Limits.
- **Felder.** Die Antwort hat dieselbe Form wie A: `five_hour`, `seven_day`, `seven_day_sonnet`/`seven_day_opus`, `extra_usage`, `limits[]` mit `weekly_scoped`. CodexBar nutzt für beide APIs denselben Mapper („Shared mapping for the model-scoped weekly limits returned by both Claude usage APIs“) [CB-web Z. 697–721]; [CB-webextra Z. 44–57]; [CB-mapper Z. 3]. **Das Fable-Limit ist also enthalten**, Reset-Zeitpunkte als ISO 8601.
- **Status.** Intern und undokumentiert [D-full]. Cloudflare-Prüfungen können Anfragen blockieren, „often caused by VPN or datacenter networks“ [CB-web Z. 173]; [CB-claude Z. 243–246].
- **Woher das Cookie kommt.** CodexBar liest es aus Browser-Dateien [CB-claude Z. 214–218, 78–84] [CB-README Z. 216–218]:
  - Safari: `~/Library/Cookies/Cookies.binarycookies`, dafür braucht man Full Disk Access.
  - Chrome und Chromium-Forks: `…/Cookies`, dafür muss die App den Keychain-Eintrag „Chrome Safe Storage“ lesen. Das ist ein weiterer fremder Eintrag mit eigenem Dialog.
  - Firefox: `cookies.sqlite`.
  - Alternativ kann der User einen `Cookie:`-Header von Hand einfügen.
- **Ablauf.** Das Cookie kann sich unabhängig vom Anmeldestatus ändern („The claude.ai session cookie can rotate independently of the user's signed-in state“) [CB-web Z. 1463].
- **Nutzungsbedingungen.** Die Rechtsseite verbietet ausdrücklich das Sammeln oder Speichern von „session tokens“ [D-legal]. Die Consumer Terms §3 verbieten außerdem „crawl, scrape, or otherwise harvest data … from our Services“ [T-consumer].

---

## C. Lokale Claude-Code-Daten

### C1. `~/.claude.json` → `cachedUsageUtilization`

- Claude Code schreibt nach jedem erfolgreichen Abruf von A die ganze Antwort nach `~/.claude.json`, unter dem Schlüssel `cachedUsageUtilization: { fetchedAtMs, accountUuid, utilization }`. Es schreibt höchstens einmal pro 60 s [CC: `if(u)Lxo(i,o,e)` und `function Lxo(e,n,r){…if(h>=0&&h<V8e)return;Ae((b)=>({...b,cachedUsageUtilization:{fetchedAtMs:Date.now(),…utilization:e}}))…}`].
- Claude Code liest diesen Cache selbst nur, wenn er höchstens 1 h alt ist und zum aktuellen Account gehört [CC: `Ewn=3600000`, `if(r.data.accountUuid!==Hn()?.accountUuid)…`, `if(s<0||s>Ewn)return null`].
- Die Datei existiert lokal und enthält Session-Limit, Wochenlimit und **Fable-Zeile** (Struktur siehe A) [LOKAL]. **Sie war beim Lesen aber 1413 min alt, also fast 24 h** [LOKAL]. Claude Code ruft A nämlich nur bei Bedarf ab, etwa für `/usage`, die IDE-Usage-Ansichten oder die Prüfung von Usage-Credits [CC: Aufrufer von `x0(`].
- Die Doku nennt `~/.claude.json` eine Datei, „that it writes for itself; you don't need to edit it“ [D-settings]. Der Schlüssel `cachedUsageUtilization` ist nicht dokumentiert [D-full].
- Man braucht weder Token noch Keychain. Wie aktuell die Werte sind, hängt aber ganz davon ab, ob gerade jemand in Claude Code `/usage` öffnet.

### C2. Transkripte `~/.claude/projects/**/*.jsonl` (ccusage)

- In den Transkripten stehen Token-Zahlen pro Antwort (`message.usage`) [CB-claude Z. 434–437]. Grenzwerte und Auslastung in % stehen nicht darin. Eine Stichprobe von 5 aktuellen Transkripten enthielt kein `utilization`, `resets_at` oder `rate_limit` [LOKAL].
- ccusage baut „5-Hour Blocks“ nur heuristisch aus Zeitstempeln nach: Ein neuer Block beginnt, wenn seit Blockbeginn oder seit dem letzten Eintrag mehr als die Session-Dauer vergangen ist [CCU Z. 53–102]. Es gibt **keine Auslastung in %, kein Wochenlimit vom Server und kein Fable-Limit**.

### C3. `~/.claude/.credentials.json`

- Unter macOS ist diese Datei nur der Ausweichort, falls die Keychain das Schreiben ablehnt, zum Beispiel weil sie per SSH gesperrt ist. Dann speichert Claude Code die Anmeldung dort mit Modus `0600` [D-auth]. Auf diesem Rechner gibt es die Datei nicht [LOKAL].

---

## D. Was Claude Code selbst bereitstellt

### D1. Statusline-JSON `rate_limits` (dokumentiert)

- Felder: `rate_limits.five_hour.used_percentage` und `rate_limits.seven_day.used_percentage` mit Werten von 0 bis 100, dazu `…resets_at` in **Unix-Epoch-Sekunden** [D-status, „Available data“]. Hinter einem Claude-apps-Gateway kommt noch `spend_limit` dazu [D-status].
- **Kein Fable-Limit.** Claude Code baut `rate_limits` nur aus `five_hour`, `seven_day` und (beim Gateway) `spend_limit` [CC: `…Ze.five_hour&&{five_hour:{used_percentage:OEt(Ze.five_hour.utilization),resets_at:Ze.five_hour.resets_at}},…Ze.seven_day&&{seven_day:…}`]. Die Werte stammen aus den Response-Headern der Modellaufrufe. Dort gäbe es mit `anthropic-ratelimit-unified-7d_oi-*` zwar ein Fenster, das Claude Code als „Fable limit“ bezeichnet, an die Statusline gibt es dieses Fenster aber nicht weiter [CC: `xw=[["five_hour","5h"],["seven_day","7d"],["seven_day_overage_included","7d_oi"],["overage","overage"]]`, `seven_day_overage_included:"Fable limit"`].
- Wann die Daten da sind: `rate_limits` „appears only for claude.ai Pro and Max subscribers … and only after the first API response in the session. Each window … may be independently absent, and Claude Code drops a window once its `resets_at` time passes.“ [D-status] Die Daten gibt es also nur, solange eine Claude-Code-Session läuft und schon ein Modellaufruf stattgefunden hat.
- Seit 2.1.80 vorhanden [D-cl]. Das Statusline-Skript läuft bei Ereignissen, optional per `refreshInterval` alle N Sekunden, und zusätzlich, sobald ein `resets_at` erreicht ist [D-status].

### D2. `claude -p "/usage"` (Text plus `usage_report`)

- Dokumentiert ist: „When you send a command such as `/context` or `/usage` as a prompt, its output arrives as an `SDKAssistantMessage`.“ [D-sdk]
- Den Text baut Claude Code aus `five_hour`, `seven_day`, bei Max/Team auch `seven_day_sonnet`, und **`model_scoped`**. Eine Zeile sieht so aus: `Current week (Fable): N% used · resets …` [CC: `{title:"Current session",limit:e.five_hour},{title:"Current week (all models)",limit:e.seven_day},…(e.model_scoped??[]).map((r)=>({title:\`Current week (${r.display_name})\`…`]. Dass `/usage` „Current week (Fable)“ zeigt, belegt auch ein öffentliches Issue [GH-79412].
- Bei `--output-format stream-json` hängt an derselben Nachricht `usage_report`. Das ist die strukturierte Fassung von `limits[]` vom Server, also mit `kind`, `percent`, `resets_at` und `scope.model.display_name`. Im SDK-Typ steht dazu: „Present only on /usage results from CLIs new enough to attach it and from claude.ai-subscriber sessions; the text in message.content remains the canonical fallback.“ Im Schema steht außerdem „Experimental — the shape may change.“ [SDK Z. 3668–3671, 6150–6152].
- **Token und Refresh erledigt Claude Code selbst**, inklusive Lock und CAS (siehe A). Die App bekommt keine Credentials zu sehen.
- CodexBar nutzt diesen Weg als Fallback [CB-claude Z. 373–394]; [CB-usagefetcher Z. 1310–1318]:
  - Aufruf: `claude --strict-mcp-config --settings '{"remoteControlAtStartup":false}' /usage`
  - Es arbeitet in einem eigenen Probe-Verzeichnis und räumt danach die `.jsonl`-Dateien weg, die dabei entstehen.
- Die Rechtsseite erlaubt ausdrücklich, „an end user [to sign in] to the unmodified Claude Code binary with their own Claude subscription“ [D-legal].

### D3. Agent SDK `usage_EXPERIMENTAL_MAY_CHANGE_DO_NOT_RELY_ON_THIS_API_YET()` / Control-Request `get_usage`

- Das SDK 0.3.288 hat die Methode `Query.usage_EXPERIMENTAL_MAY_CHANGE_DO_NOT_RELY_ON_THIS_API_YET({ skipBehaviors })` [SDK Z. 3040–3058]:
  - Sie liefert `rate_limits.five_hour` und `seven_day` (je `{utilization 0–100, resets_at ISO 8601}`), außerdem `seven_day_opus`/`seven_day_sonnet`/`seven_day_oauth_apps` und **`model_scoped[]: {display_name (z. B. 'Fable'), utilization, resets_at}`** [SDK Z. 4251–4343].
  - Ein Hinweis aus dem SDK: „EXPERIMENTAL: this API is unstable and may change or be removed in any release without notice — do not rely on it yet. The method name will change when the API is stabilized.“ [SDK Z. 3050–3052]
  - In der SDK-Referenz auf code.claude.com steht die Methode nicht [D-sdk]; [D-full].
- Auf der Leitung ist das der Control-Request `{subtype:"get_usage", skip_behaviors}` im stream-json-Protokoll der CLI. Laut CLI ist `skip_behaviors` für Aufrufer gedacht, „that need only the plan rate limits, such as a usage meter“ [CC: `Po=f(()=>u({subtype:R("get_usage"),skip_behaviors:H().optional().describe("…such as a usage meter…")`].
- Auch hier holt Claude Code die Werte selbst. Das SDK ist aber ein TypeScript-Paket. Eine Swift-App müsste `claude` starten und das stream-json-Control-Protokoll selbst sprechen, und dieses Protokoll ist nicht als Schnittstelle dokumentiert. Oder sie müsste Node mitbringen. (Folgerung.)
- Die Rechtsseite verlangt für Entwickler, „including those using the Agent SDK“, eine Authentifizierung per API-Key [D-legal].

### D4. Weitere Wege, die nicht passen

- `SDKRateLimitEvent` (dokumentiert) enthält nur `status`, `resetsAt` und `utilization` des gerade maßgeblichen Limits, kommt nur bei Modellaufrufen und hat kein Fable-Feld [D-sdk].
- OpenTelemetry-Metriken und Hooks enthalten keine Auslastung der Limits, nur Fehlertypen wie `rate_limit` [D-monitoring]; [D-hooks].
- Für `claude setup-token` fehlt der Scope `user:profile` (siehe A).

---

## E. Keychain-Zugriff aus einer fremden App

**Wo der Eintrag liegt und wer ihn angelegt hat**

- Der Eintrag `Claude Code-credentials` liegt in der dateibasierten Login-Keychain (`~/Library/Keychains/login.keychain-db`, Klasse `genp`). Er wurde am 2026-08-26 angelegt und zuletzt am 2026-10-03 geändert [LOKAL: `security find-generic-password -s "Claude Code-credentials"` ohne `-w`/`-g`]. Claude Code aktualisiert ihn also an Ort und Stelle und legt ihn nicht bei jedem Refresh neu an.
- Ist `CLAUDE_CONFIG_DIR` gesetzt, verwendet Claude Code einen anderen Keychain-Eintrag [D-auth].
- Claude Code liest und schreibt den Eintrag nicht über Security.framework, sondern über das Tool `/usr/bin/security` [CC]:
  - Lesen: ``security find-generic-password -a "${a}" -w -s "${s}"``
  - Schreiben: ``add-generic-password -U -a "${s}" -s "${n}" -X "${o}"`` über `security -i` via stdin
- „By default, the application which creates an item is trusted to access its data without warning.“ [man-security, `add-generic-password`] Folgerung: Vertraut wird dem Werkzeug `/usr/bin/security`, nicht dem Claude-Code-Binary.

**Was eine fremde App erlebt**

- Dateibasierte Keychain-Einträge schützt eine ACL (`SecAccess`). Mit `SecItem` landet man standardmäßig in der dateibasierten Keychain. Programme, die *vorhandene* Einträge dort lesen, „must target the file-based keychain“ [A-tn3137].
- Steht die aufrufende App nicht auf der Liste der vertrauten Apps, „the system prompts the user for confirmation. The user may choose to Deny, Allow, or Always Allow … In the latter case, the system adds the app to the list of trusted apps“ [A-acl]. Apple-Support zu „Always Allow“: „Let the app … retrieve the password from your keychain without any further authorization or notice from you.“ [A-support]
- Im Hintergrund kann die App mit `kSecUseAuthenticationUIFail` verlangen, dass kein Dialog erscheint. Die Abfrage scheitert dann mit `errSecInteractionNotAllowed` [A-uifail]. CodexBar hat allerdings beobachtet: „A Security.framework query configured as ‚no UI‘ can still display a legacy Keychain ACL dialog.“ [CB-seccli Z. 369–370]

**Einfluss der Code-Signatur**

- Ein Trusted-App-Eintrag „identifies an app and provides data that can be used to ensure that the app hasn't been altered“ [A-trusted].
- In der Praxis prüft macOS laut CodexBar „the requesting executable's code signature and designated requirement, not just its filename or install path. A stable, properly signed … bundle makes grants more durable, while ad-hoc development builds … may need authorization again.“ [CB-kc Z. 58–64]

**„Immer erlauben“ hält nicht zuverlässig**

- CodexBar: „Claude Code can recreate `Claude Code-credentials` and reset that grant.“ In einer Messung blieb der Eintrag der App in der Decrypt-ACL zwar erhalten, aber Claude Code entfernte „CodexBar's Team ID from the separate partition ACL … repeated manual grants therefore need not survive the next Claude Code refresh“ [CB-claude Z. 112–118, 192–195]; [CB-models Z. 279–281].

**Ein Weg ohne Dialog**

- Es ist technisch möglich, als Kindprozess `/usr/bin/security find-generic-password -w` aufzurufen, also genau so, wie Claude Code den Eintrag selbst liest. CodexBar bietet das als *experimentellen* Leser an und warnt, „`security` can prompt“ [CB-seccli Z. 44–45, 95–96].
- Ob dabei auf diesem Rechner ein Dialog erscheint, wurde nicht geprüft. Das gehört zu Ticket #5.
- Falls kein Dialog erscheint, umgeht dieser Weg die sichtbare Zustimmung des Users. (Folgerung.)

**Wie CodexBar damit umgeht**

- Den fremden Eintrag liest CodexBar nur mit ausdrücklicher Zustimmung, standardmäßig ist das aus. Die voreingestellte Richtlinie ist „Only on user action“ [CB-kc Z. 15–17]; [CB-claude Z. 102–111].

---

## Offene Unsicherheiten

1. **Wie lange ein Access-Token gilt** (`expires_in`) und ob ein alter Refresh-Token nach der Rotation sofort ungültig wird. Beides sieht man nur, wenn man das Geheimnis liest oder einen echten Refresh beobachtet. Die Rotation selbst belegen Code und CodexBar. Ob der Server den alten Token sofort sperrt, ist nicht belegt.
2. **Ob über `/usr/bin/security` ein Dialog erscheint** und wie sich „Immer erlauben“ für eine Developer-ID-signierte App über die Refreshes von Claude Code hinweg verhält. Das soll Ticket #5 klären.
3. **Wie sich `limits[]` auf Pro verhält.** Laut Support ist Fable auf Pro nicht im Plan, also gibt es dort vermutlich keine `weekly_scoped`-Zeile. Das ist nicht gemessen, weil nur ein Account vorhanden ist.
4. **Wie `five_hour` aussieht, wenn keine Session läuft.** Gibt es dann `utilization: 0` mit `resets_at: null`, `null` für das ganze Objekt, oder ein Fenster in der Zukunft? Das Schema erlaubt `null` [CC]. CodexBar beobachtet `five_hour: null` bei Enterprise- und Credit-Accounts [CB-web Z. 200–201, 707].
5. **Rate-Limit des Endpunkts.** Es gibt keine veröffentlichten Werte, belegt sind nur 429/403 mit `Retry-After`. Wie oft man abfragen darf, ohne gedrosselt zu werden, ist offen.
6. **Nutzungsbedingungen.** Ob eine lokale App, die das OAuth-Token von Claude Code liest (A) oder das Browser-Cookie (B), gegen „may not collect, store, or intermediate Claude.ai credentials or session tokens“ verstößt, sagen die Quellen nicht ausdrücklich. Ausdrücklich erlaubt ist nur, das unveränderte Claude-Code-Binary mit dem eigenen Abo zu nutzen (D2/D3).
7. **Ob `claude -p "/usage"` Modellaufrufe auslöst** und damit selbst etwas verbraucht. Im Code gibt es einen 1-Token-„quota“-Aufruf (`source:"quota_check"`), der aber nur in Reset-Abläufen aufgerufen wird. Für `/usage` ist das nicht belegt, ebenso wenig die Laufzeit pro Aufruf. Getestet wurde es nicht, weil das den Endpunkt mit den Credentials des Users aufgerufen hätte.
8. **Welcher Ort aktuell gilt.** Laut CodexBar kann `Claude Code-credentials` unter 2.1.x auch nur `mcpOAuth` ohne `claudeAiOauth` enthalten [CB-claude Z. 150]. Ob das auf diesem Rechner so ist, wurde nicht geprüft, weil dafür das Geheimnis gelesen werden müsste.
9. **Die Fable-Allowlist kommt vom Server.** Claude Code zeigt nur Modellnamen auf einer Allowlist, die per Feature-Flag geändert werden kann. Die Rohantwort kann also auch andere `weekly_scoped`-Zeilen enthalten, etwa wenn ein späteres Modell auf Fable folgt.

---

## Quellen

**Claude Code (lokal, nur gelesen)**

- **[CC]** Claude Code 2.1.288, natives Binary `~/.local/share/mise/installs/claude/latest/claude` (`BUILD_TIME:"2026-10-02T16:42:03Z"`, `GIT_SHA:"17fe1eb736e5b1433d6ca86a1db334cec8520450"`). Die Code-Ausschnitte sind wörtlich aus `strings -n 6` übernommen.
- **[LOKAL]** Beobachtungen auf diesem Rechner am 2026-10-03:
  - Struktur von `~/.claude.json` → `cachedUsageUtilization` (Feldnamen, Typen, Zeitstempel)
  - Attribute von `security find-generic-password -s "Claude Code-credentials"` (ohne Geheimnis)
  - Existenz von `~/.claude/.credentials.json`
  - Stichprobe aus `~/.claude/projects/*.jsonl`

**Anthropic-Dokumentation und Support**

- **[SDK]** `@anthropic-ai/claude-agent-sdk` 0.3.288, `sdk.d.ts`: <https://registry.npmjs.org/@anthropic-ai/claude-agent-sdk/-/claude-agent-sdk-0.3.288.tgz>
- **[D-status]** <https://code.claude.com/docs/en/statusline> (Abschnitte „Available data“, „Rate limit usage“)
- **[D-auth]** <https://code.claude.com/docs/en/authentication> (Credential-Speicher, `setup-token`, abgelaufene Anmeldung)
- **[D-legal]** <https://code.claude.com/docs/en/legal-and-compliance> („Authentication and credential use“)
- **[D-sdk]** <https://code.claude.com/docs/en/agent-sdk/typescript> (`SDKRateLimitEvent`, `SDKLocalCommandOutputMessage`, Query-Objekt)
- **[D-settings]** <https://code.claude.com/docs/en/settings> (`~/.claude.json`)
- **[D-cl]** <https://code.claude.com/docs/en/changelog> (2.1.80, 2.1.208, 2.1.261, 2.1.283, 2.1.284)
- **[D-full]** <https://code.claude.com/docs/llms-full.txt> (Volltextsuche am 2026-10-03)
- **[D-monitoring]** <https://code.claude.com/docs/en/monitoring-usage>
- **[D-hooks]** <https://code.claude.com/docs/en/hooks>
- **[S-fable]** <https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan> (aktualisiert am 2. Sept. 2026)
- **[S-max]** <https://support.claude.com/en/articles/11049741-what-is-the-max-plan>
- **[S-best]** <https://support.claude.com/en/articles/9797557-usage-limit-best-practices> („Settings > Usage“, „Current session“)
- **[T-consumer]** <https://www.anthropic.com/legal/consumer-terms> (§2, §3, gültig ab 8. Okt. 2025)
- **[GH-79412]** <https://github.com/anthropics/claude-code/issues/79412> (`/usage`-Ausgabe mit „Current week (Fable)“)

**Apple**

- **[A-acl]** <https://developer.apple.com/documentation/security/access-control-lists>
- **[A-tn3137]** <https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains>
- **[A-uifail]** <https://developer.apple.com/documentation/security/ksecuseauthenticationuifail>
- **[A-trusted]** <https://developer.apple.com/documentation/security/sectrustedapplicationcreatefrompath(_:_:)>
- **[A-support]** <https://support.apple.com/guide/keychain-access/kyca1243/mac>
- **[man-security]** `man security`, Abschnitt `add-generic-password` (macOS 27)

**CodexBar** (Commit `917ae1465d984710817f8010a824612f74b1a6f9`)

- **[CB-claude]** [docs/claude.md](https://github.com/steipete/CodexBar/blob/917ae1465d984710817f8010a824612f74b1a6f9/docs/claude.md)
- **[CB-kc]** [docs/keychain-prompts.md](https://github.com/steipete/CodexBar/blob/917ae1465d984710817f8010a824612f74b1a6f9/docs/keychain-prompts.md)
- **[CB-README]** [README.md](https://github.com/steipete/CodexBar/blob/917ae1465d984710817f8010a824612f74b1a6f9/README.md)
- **[CB-fetcher]** [ClaudeOAuthUsageFetcher.swift](https://github.com/steipete/CodexBar/blob/917ae1465d984710817f8010a824612f74b1a6f9/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift)
- **[CB-gate]** [ClaudeOAuthUsageRateLimitGate.swift](https://github.com/steipete/CodexBar/blob/917ae1465d984710817f8010a824612f74b1a6f9/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageRateLimitGate.swift)
- **[CB-creds]** [ClaudeOAuthCredentials.swift](https://github.com/steipete/CodexBar/blob/917ae1465d984710817f8010a824612f74b1a6f9/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthCredentials.swift)
- **[CB-models]** [ClaudeOAuthCredentialModels.swift](https://github.com/steipete/CodexBar/blob/917ae1465d984710817f8010a824612f74b1a6f9/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthCredentialModels.swift)
- **[CB-seccli]** [ClaudeOAuthCredentials+SecurityCLIReader.swift](https://github.com/steipete/CodexBar/blob/917ae1465d984710817f8010a824612f74b1a6f9/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthCredentials%2BSecurityCLIReader.swift)
- **[CB-web]** [ClaudeWebAPIFetcher.swift](https://github.com/steipete/CodexBar/blob/917ae1465d984710817f8010a824612f74b1a6f9/Sources/CodexBarCore/Providers/Claude/ClaudeWeb/ClaudeWebAPIFetcher.swift)
- **[CB-webextra]** [ClaudeWebExtraRateWindowParser.swift](https://github.com/steipete/CodexBar/blob/917ae1465d984710817f8010a824612f74b1a6f9/Sources/CodexBarCore/Providers/Claude/ClaudeWeb/ClaudeWebExtraRateWindowParser.swift)
- **[CB-mapper]** [ClaudeScopedWeeklyLimitMapper.swift](https://github.com/steipete/CodexBar/blob/917ae1465d984710817f8010a824612f74b1a6f9/Sources/CodexBarCore/Providers/Claude/ClaudeScopedWeeklyLimitMapper.swift)
- **[CB-usagefetcher]** [ClaudeUsageFetcher.swift](https://github.com/steipete/CodexBar/blob/917ae1465d984710817f8010a824612f74b1a6f9/Sources/CodexBarCore/Providers/Claude/ClaudeUsageFetcher.swift)

**ccusage** (Commit `48503000b064772dfd0d4494699c8f203e770152`)

- **[CCU]** [rust/crates/ccusage/src/blocks.rs](https://github.com/ryoppippi/ccusage/blob/48503000b064772dfd0d4494699c8f203e770152/rust/crates/ccusage/src/blocks.rs#L53-L102)
