# Tech-Stack-Optionen für die Menüleisten-App

Recherche zu Issue [#3](https://github.com/chris-metz/ai_usage_macos/issues/3) (Map [#1](https://github.com/chris-metz/ai_usage_macos/issues/1)).
Stand: 3. Oktober 2026. Das Dokument vergleicht, es entscheidet nicht. Die Entscheidung fällt im Ticket „Welchen Tech-Stack nutzt v1?“.

Begriffe wie Provider, Limit, Auslastung, Reset-Zeitpunkt und Pace-Marker stehen in `GLOSSARY.md`.

**Lokale Umgebung, auf der alle Mini-Tests liefen:** macOS 27.0.1, Xcode 27.0 (27A266a), Swift 6.4 (swiftlang-6.4.0.34.1), notarytool 1.1.3, Node 24, Claude Code 2.1.288. Nicht installiert sind Rust/Cargo, XcodeGen und Tuist. Tauri, XcodeGen und Tuist wurden deshalb nicht lokal gebaut, die Aussagen dazu stützen sich auf ihre Dokumentation.

Kennzeichnung: Aussagen mit Link stammen aus der verlinkten Quelle. „(lokal geprüft)“ verweist auf den Abschnitt [Mini-Tests](#mini-tests-lokal). „**Einschätzung:**“ markiert eine eigene Bewertung ohne Primärquelle.

---

## Kurzfassung

| Kriterium | **A. SwiftUI `MenuBarExtra` (`.window`)** | **B. AppKit `NSStatusItem` + `NSPopover` (bzw. hybrid)** | **C. Tauri 2** | **D. Electron** |
|---|---|---|---|---|
| Sprachen | Swift | Swift | Rust (Core) + HTML/TS (UI) | JS/TS |
| Bauen, testen und starten per CLI | `swift build`, `swift test`, `xcodebuild test` laufen ohne `.xcodeproj` (lokal geprüft). Das `.app`-Bundle baut ein Skript oder XcodeGen/Tuist. | wie A | `tauri build` signiert und notarisiert, wenn Env-Variablen gesetzt sind ([Doku](https://v2.tauri.app/distribute/sign/macos/)) | Forge/Packager mit `osx-sign` und `notarize` ([Doku](https://www.electronjs.org/docs/latest/tutorial/code-signing)) |
| UI selbst prüfen (Agent) | PNG-Snapshot per `swift test` über `NSHostingView` (lokal geprüft). Xcode-MCP `RenderPreview` braucht Xcode. | wie A. Live-Tests von Status Items gelten als fragil ([CodexBar](https://github.com/steipete/CodexBar/blob/main/AGENTS.md)). | Frontend im Browser testbar. WebDriver unter macOS nur über den eingebetteten Server von `@wdio/tauri-service` ([Doku](https://v2.tauri.app/develop/tests/webdriver/)). | Playwright (experimentell) oder WebdriverIO ([Doku](https://www.electronjs.org/docs/latest/tutorial/automated-testing)) |
| RAM im Leerlauf (lokal gemessen) | **16 MB**, 1 Prozess | nicht separat gemessen, **Einschätzung:** ähnlich wie A | ca. **46–48 MB**, 4 Prozesse (Näherung über WKWebView) | ca. **79–83 MB**, 4 Prozesse |
| CPU im Leerlauf (lokal gemessen) | ≈ 0 % | – | ≈ 0 % | ≈ 0 % |
| App-Größe | 172 KB (lokal) | ähnlich | „less than 600KB“ minimal ([Doku](https://v2.tauri.app/start/)) | Runtime allein 297 MB entpackt (lokal) |
| Keychain-Eintrag `Claude Code-credentials` | gleich für alle Stacks: Mit Security.framework erscheint ein Dialog. Über `/usr/bin/security` gelingt der Zugriff ohne Dialog (lokal geprüft, Details [unten](#keychain-zugriff-auf-claude-code-credentials)). | wie A | wie A (Subprozess oder Rust-Crate) | wie A (`keytar` ist [archiviert](https://github.com/atom/node-keytar)) |
| Kein Dock-Icon | `LSUIElement` ([Apple](https://developer.apple.com/documentation/swiftui/menubarextra)) | `LSUIElement` | Info.plist-Merge oder `ActivationPolicy::Accessory` | `app.dock.hide()` (lokal geprüft) oder `extendInfo` |
| Autostart | `SMAppService.mainApp` ([Apple](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)) | wie A | Plugin nutzt LaunchAgent oder AppleScript, **kein** SMAppService ([Quelle](https://github.com/tauri-apps/plugins-workspace/blob/v2/plugins/autostart/src/lib.rs)) | `setLoginItemSettings`, intern SMAppService ([Doku](https://www.electronjs.org/docs/latest/api/app)) |
| Status-Item-Änderungen in macOS 27 | SwiftUI übernimmt die neue „Expanded Interface Session“ selbst ([MenuBarExtraAccess PR #26](https://github.com/orchetect/MenuBarExtraAccess/pull/26)) | muss `expandedInterfaceDelegate` selbst umsetzen ([WWDC26-289](https://developer.apple.com/videos/play/wwdc2026/289/)) | hängt an `tray-icon`, Klick-Bug erst im Sept. 2026 behoben ([PR #365](https://github.com/tauri-apps/tray-icon/pull/365)) | hängt an Electron, offene macOS-27-Issues ([#53889](https://github.com/electron/electron/issues/53889)) |
| Dropdown per Code öffnen | keine öffentliche API ([README](https://github.com/orchetect/MenuBarExtraAccess)) | eigenes Fenster lässt sich zeigen. Für Session und Highlight gibt es auf macOS 27 keine öffentliche API ([Forum](https://developer.apple.com/forums/thread/836113)). | Fenster frei steuerbar | Fenster frei steuerbar |
| Weitere Provider-Tabs | trivial (SwiftUI-View je Provider) | trivial | trivial (Web-Komponente) | trivial |

**Wichtigste Trade-offs in einem Satz je Option:**

- **A. SwiftUI `MenuBarExtra`:** Am schlanksten. Apple pflegt die Integration in die Menüleiste, auch die Umbauten in macOS 27. Dafür gibt es wenig Kontrolle (kein Öffnen per Code, Eigenheiten bei der Fenstergröße), und Swift 6 meldet Concurrency-Fehler streng.
- **B. AppKit/hybrid:** Volle Kontrolle über Status Item und Fenster. Dafür muss man das neue Interaktionsmodell von macOS 27 selbst richtig umsetzen, und dort berichten Entwickler derzeit viele Brüche.
- **C. Tauri:** Die UI ist eine Web-UI, die Agents leicht im Browser prüfen. Die App ist klein, im Leerlauf aber etwa dreimal so speicherhungrig wie A. Es braucht zwei Toolchains (Rust und Node). Die macOS-Spezialitäten (Popover-Position, Autostart per SMAppService) kommen aus Community-Plugins oder fehlen.
- **D. Electron:** Hat das größte JS/TS-Ökosystem und die einfachste Web-UI-Prüfung. Dafür ist es das schwerste Paket (etwa 300 MB, etwa 80 MB RAM, 4 Prozesse), und alle 8 Wochen erscheint eine Major-Version, die man nachziehen muss.

---

## Mini-Tests (lokal)

Alles lief im Scratch-Verzeichnis. Im Repo liegt kein App-Code.

### 1. Menüleisten-App nur mit SwiftPM, ohne `.xcodeproj`

Aufbau: ein `Package.swift` mit `swift-tools-version: 6.0`, also Swift-6-Sprachmodus mit voller Data-Race-Prüfung ([Swift Migration Guide](https://github.com/swiftlang/swift-migration-guide/blob/main/Guide.docc/EnableDataRaceSafety.md)). Dazu kommen drei Targets:

- eine Library `MiniBarUI` mit dem Panel: segmentierter Picker „Claude/Codex“, drei Balken mit Pace-Marker und Reset-Zeitpunkt, Buttons „Aktualisieren“ und „Beenden“,
- ein Executable mit `MenuBarExtra(...).menuBarExtraStyle(.window)`,
- ein Test-Target mit Swift Testing.

Ergebnisse:

| Schritt | Ergebnis |
|---|---|
| `swift build -c release` (clean) | erster Versuch ohne Compilerfehler, 19,7 s; inkrementell 1,9 s |
| `.app`-Bundle | ein Shell-Skript mit ca. 25 Zeilen: Binary kopieren, `Info.plist` mit `LSUIElement` schreiben, `codesign --options runtime --sign -`. `codesign --verify --strict` meldet „valid on disk“. Größe 172 KB. |
| `open -n MiniBar.app` | `lsappinfo` meldet `type="UIElement"`, also kein Dock-Icon |
| `swift test` → PNG | **`NSHostingView` in einem Offscreen-`NSWindow`** rendert das komplette Panel einschließlich des segmentierten Pickers. **`ImageRenderer`** rendert Text, Balken und Buttons, ersetzt den segmentierten Picker aber durch einen Platzhalter. Das deckt sich mit Apples Hinweis, dass „most types of UIKit and AppKit views“ als Platzhalter erscheinen ([Apple](https://developer.apple.com/documentation/swiftui/imagerenderer)). |
| Dark-Mode-Snapshot | Der Text kam weiß auf transparentem Hintergrund heraus und war im PNG unsichtbar. Snapshots brauchen also einen expliziten Hintergrund. Gefunden hat das der Agent beim Anschauen des PNG, was den Wert dieser Selbstprüfung zeigt. |
| `MiniBar --snapshot out.png` | Ein CLI-Modus im App-Binary schreibt das Panel als PNG und beendet sich. Das braucht keine Freigabe für Bildschirmaufnahme. |
| `xcodebuild test -scheme MiniBar -destination platform=macOS -resultBundlePath …` direkt auf dem Package | funktioniert ohne `.xcodeproj`. `xcrun xcresulttool get test-results summary` liefert JSON (`"result": "Passed"`). |

Nicht geprüft: Das Dropdown per Klick öffnen und live per `screencapture` aufnehmen. Dafür bräuchte der Terminal-Prozess die Freigaben für Bedienungshilfen bzw. Bildschirmaufnahme ([Apple: Bedienungshilfen](https://support.apple.com/guide/mac-help/mh43185/mac), [Apple: Bildschirmaufnahme](https://support.apple.com/guide/mac-help/mchld6aa7d23/mac)). Diese Systemdialoge wollte ich nicht auslösen.

### 2. Speicher und CPU im Leerlauf

Gemessen wurde mit `footprint` (phys_footprint) nach etwa 3 und etwa 7 Minuten Laufzeit, das Dropdown blieb geschlossen. Die CPU-Zeit stammt aus `ps`, gemessen über 4,5 Minuten.

| Variante | Prozesse | Footprint gesamt | CPU-Zeit in 4,5 min |
|---|---|---|---|
| SwiftUI `MenuBarExtra` (Test 1) | 1 | **16 MB** | +0,05 s |
| Näherung für Tauri: AppKit-Status-Item mit verstecktem `NSPanel` und `WKWebView`, das gleiche HTML-Panel | 4 (App 19–20 MB, WebContent 11–13, GPU 9–11, Networking 6–7) | **≈ 46–48 MB** | +0,06 s |
| Electron 44.5.1, unpaketiert: `Tray` mit verstecktem `BrowserWindow` (das Muster von `menubar`) | 4 (Main 36–39 MB, GPU 17–18, Utility 7, Renderer 19) | **≈ 79–83 MB** | +0,17 s |

Grenzen der Messung: ein Rechner, nur Leerlauf, Dropdown nie geöffnet. Die Tauri-Zeile ist **keine** echte Tauri-App. Tauris Core ist Rust und rendert die UI über WKWebView ([Tauri: Webview Versions](https://v2.tauri.app/reference/webview-versions/), [Tauri: Process Model](https://v2.tauri.app/concept/process-model/)). Die Näherung bildet nur den WebKit-Anteil realistisch ab. **Einschätzung:** Für eine App, die alle paar Minuten eine HTTPS-Anfrage stellt, ist die CPU-Last bei allen Stacks vernachlässigbar. Beim Speicher unterscheiden sich die Stacks deutlich, etwa um Faktor 3 bzw. 5.

### 3. Keychain

Siehe [Keychain-Zugriff](#keychain-zugriff-auf-claude-code-credentials). Geprüft wurden die Attribute und die ACL des Eintrags sowie ein stiller Lesezugriff über `/usr/bin/security`. Das Token selbst wurde nicht ausgegeben.

---

## Optionen im Detail

### A. Swift/SwiftUI mit `MenuBarExtra` (`.window`-Style)

**Was Apple anbietet**

- `MenuBarExtra` ist eine Scene, „that renders itself as a persistent control in the system menu bar“. Es gibt sie ab macOS 13 ([Apple](https://developer.apple.com/documentation/swiftui/menubarextra)).
- Der `.window`-Style zeigt „a popover-like window“ mit den Controls eines normalen Fensters, im Gegensatz zum Menü-Layout von `.menu` ([Apple](https://developer.apple.com/documentation/swiftui/menubarextrastyle/window)).
- Eine reine Menüleisten-App ist eine Scene mit `MenuBarExtra`. Mit `LSUIElement = true` hat sie kein Dock-Icon und taucht nicht im App-Umschalter auf ([Apple](https://developer.apple.com/documentation/swiftui/menubarextra), [LSUIElement](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement)).
- In der WWDC26 zeigt Apple `MenuBarExtra` mit `.window` sogar für eine bestehende AppKit-App, eingehängt über `NSHostingSceneRepresentation`, verfügbar ab macOS 26 ([WWDC26-272](https://developer.apple.com/videos/play/wwdc2026/272/), [Apple](https://developer.apple.com/documentation/swiftui/nshostingscenerepresentation)).

**Stärken**

- Am wenigsten Code und am wenigsten Speicher (lokal: 16 MB).
- Die Menüleisten-Mechanik von macOS 27 übernimmt SwiftUI. Seit macOS 27 läuft die Präsentation über eine AppKit-„Expanded Interface Session“, und SwiftUIs `WindowMenuBarExtraBehavior` ist selbst der `expandedInterfaceDelegate` ([MenuBarExtraAccess PR #26](https://github.com/orchetect/MenuBarExtraAccess/pull/26)). Bei eigenen Status Items muss man diesen Lebenszyklus selbst implementieren, damit Tastaturfokus und Navigation stimmen ([WWDC26-289](https://developer.apple.com/videos/play/wwdc2026/289/)).
- Autostart (`SMAppService.mainApp`) und `LSUIElement` sind direkte Apple-APIs ([Apple](https://developer.apple.com/documentation/servicemanagement/smappservice)).

**Schwächen und bekannte Eigenheiten:** siehe [MenuBarExtra-Eigenheiten](#bekannte-eigenheiten-von-menubarextra).

### B. Swift mit AppKit `NSStatusItem` + `NSPopover` (oder hybrid)

**Was Apple anbietet**

- Man erzeugt `NSStatusItem` über `NSStatusBar.statusItem(withLength:)` und passt es über `button` an ([Apple](https://developer.apple.com/documentation/appkit/nsstatusitem)).
- Neu in macOS 27: `expandedInterfaceDelegate` und `expandedInterfaceSession`. Der Delegate zeigt eigene UI, etwa ein `NSWindow` unter dem Status Item, in `statusItem(_:didBegin:)` und blendet sie in `statusItemDidEndExpandedInterfaceSession(_:animated:)` wieder aus ([Apple](https://developer.apple.com/documentation/appkit/nsstatusitem/expandedinterfacedelegate), [Apple](https://developer.apple.com/documentation/appkit/nsstatusitem/expandedinterfacesession)). In der WWDC heißt es dazu: „When a status item shows its window, AppKit needs to know when that UI is active, so that keyboard focus can behave correctly“ ([WWDC26-289](https://developer.apple.com/videos/play/wwdc2026/289/)).

**Stand in macOS 27 laut Entwicklerforum**

- `button?.highlight(true)` funktioniert nicht mehr. Apple verweist auf `expandedInterfaceDelegate`, was laut Entwicklern aber „does not solve the issue of programmatically … showing the menubar app window“ ([Forum 836113](https://developer.apple.com/forums/thread/836113)).
- Rechtsklick, Drag & Drop und das Schließen per erneutem Linksklick funktionieren nicht mehr wie früher. Bei Popovers fehlen mit Expanded Session die Animationen. Ein Frameworks Engineer schreibt: „Local event monitors are no longer the recommended way of scanning for events on status items“ ([Forum 832823](https://developer.apple.com/forums/thread/832823)).
- Hover-Events in Status-Item-Buttons waren kaputt und sind seit Beta 5 behoben ([Forum 836113](https://developer.apple.com/forums/thread/836113)).

**Erfahrungen aus echten Apps**

- CodexBar (Swift, MIT, etwa 22k Sterne) nutzt eigene `NSStatusItem`-Controller statt `MenuBarExtra` und baut nur mit SwiftPM. Die `AGENTS.md` warnt: „macOS CI is brittle around headless AppKit status/menu tests. Prefer covering menu behavior through stable state/model seams“ ([CodexBar AGENTS.md](https://github.com/steipete/CodexBar/blob/main/AGENTS.md)).
- Die native Swift-Variante von CCSeva nutzt „`NSStatusItem` + `NSPopover(NSHostingController)`“, ist ein SwiftPM-Executable ohne `.xcodeproj` und hat einen headless `--diagnose`-Modus ([CCSeva swift/README](https://github.com/Iamshankhadeep/ccseva/blob/main/swift/README.md)).

**Hybrid-Varianten**

- Eine SwiftUI-App mit `MenuBarExtra`, die bei Bedarf AppKit nutzt, z. B. über `NSApplicationDelegateAdaptor`. Oder eine AppKit-App, die eine SwiftUI-`MenuBarExtra`-Scene über `NSHostingSceneRepresentation` einhängt ([WWDC26-272](https://developer.apple.com/videos/play/wwdc2026/272/)). In beiden Fällen bleibt das Status Item SwiftUI-verwaltet.
- **Einschätzung:** Mit B gewinnt man Kontrolle über Öffnen, Schließen und Position. Auf macOS 27 bezahlt man dafür mit einem neuen, laut Forum noch lückenhaft dokumentierten Interaktionsmodell. Für ein Dropdown, das sich nur per Klick öffnet, braucht v1 diese Kontrolle kaum.

### C. Tauri 2

**Menüleiste**

- Das Tray kommt über das Feature `tray-icon` und `TrayIconBuilder`. Die Doku zeigt nur „show and focus the main window when the tray is clicked“. Ein Fenster unter dem Icon zu positionieren ist nicht eingebaut ([Tauri: System Tray](https://v2.tauri.app/learn/system-tray/)).
- Die Position liefert das Plugin `positioner`, ein „port of electron-positioner“ ([Tauri: Positioner](https://v2.tauri.app/plugin/positioner/)). Ein echtes macOS-Panel gibt es über das Community-Plugin `tauri-nspanel` ([GitHub](https://github.com/ahkohd/tauri-nspanel)). Dazu existiert eine Beispiel-App mit Popover-Branch ([GitHub](https://github.com/ahkohd/tauri-macos-menubar-app-example)).
- macOS 27: Linksklick öffnete das Menü statt die Klick-Aktion auszulösen ([tauri#16035](https://github.com/tauri-apps/tauri/issues/16035), [tray-icon#355](https://github.com/tauri-apps/tray-icon/issues/355)). Behoben ist das in `tray-icon` PR #365, gemergt am 16.09.2026 ([PR #365](https://github.com/tauri-apps/tray-icon/pull/365)).

**Kein Dock-Icon und Autostart**

- `set_activation_policy(tauri::ActivationPolicy::Accessory)` ([Quelle](https://github.com/tauri-apps/tauri/blob/dev/crates/tauri/src/app.rs)). Alternativ eine eigene `src-tauri/Info.plist`, die „merged with the values generated by the Tauri CLI“ wird ([Tauri: macOS Application Bundle](https://v2.tauri.app/distribute/macos-application-bundle/)).
- Das Autostart-Plugin kennt auf macOS nur `LaunchAgent` (eine Plist in `~/Library/LaunchAgents`) und `AppleScript` (ein Login Item über „System Events“), aber kein SMAppService ([Quelle](https://github.com/tauri-apps/plugins-workspace/blob/v2/plugins/autostart/src/lib.rs)).

**Signieren und Notarisieren:** über die Env-Variablen `APPLE_SIGNING_IDENTITY` bzw. `APPLE_CERTIFICATE` und `APPLE_API_ISSUER`/`APPLE_API_KEY`/`APPLE_API_KEY_PATH`. Danach „rerun your Tauri build“ ([Tauri: macOS Code Signing](https://v2.tauri.app/distribute/sign/macos/)).

**Testen:** `tauri-driver` unterstützt macOS nicht, weil es „no WKWebView driver tool“ gibt. Es geht nur über den eingebetteten WebDriver-Server von `@wdio/tauri-service` oder den kostenpflichtigen Fork von CrabNebula ([Tauri: WebDriver](https://v2.tauri.app/develop/tests/webdriver/)).

**Weitere Punkte**

- Ein Capabilities- und Permissions-System regelt, welche Core-APIs das Frontend nutzen darf ([Tauri: Capabilities](https://v2.tauri.app/security/capabilities/)). Das ist zusätzliche Konfiguration, die Agents korrekt pflegen müssen.
- Die WebKit-Version hängt an der macOS-Version ([Tauri: Webview Versions](https://v2.tauri.app/reference/webview-versions/)).

### D. Electron

**Menüleiste**

- `Tray` mit `getBounds()` (macOS/Windows), um ein `BrowserWindow` unter dem Icon zu platzieren ([Electron: Tray](https://www.electronjs.org/docs/latest/api/tray)).
- Die Bibliothek `menubar` bündelt dieses Muster. Sie wird gepflegt, zuletzt in Version 9.5.3, aktualisiert im Juli 2026 ([GitHub](https://github.com/max-mapper/menubar), npm).

**Kein Dock-Icon**

- `dock.hide()` hat einen „Known issue: Calling `dock.hide()` within one second of a previous call will have no effect“ ([Electron: Dock](https://www.electronjs.org/docs/latest/api/dock)). Alternativ `app.setActivationPolicy('accessory')` ([Electron: app](https://www.electronjs.org/docs/latest/api/app)) oder `LSUIElement` über `extendInfo` von `@electron/packager` ([Quelle](https://github.com/electron/packager/blob/main/src/types.ts)).
- Lokal geprüft: Mit `app.dock.hide()` beim Start meldet `lsappinfo` auf macOS 27.0.1 `type="UIElement"`.

**Autostart:** `app.setLoginItemSettings({ openAtLogin, type: 'mainAppService' })`, gestützt auf SMAppService. Die Funktion „may silently fail“, wenn die App nicht signiert und notarisiert ist ([Electron: app](https://www.electronjs.org/docs/latest/api/app)).

**Signieren und Notarisieren:** Forge oder `@electron/packager` mit `@electron/osx-sign` und `@electron/notarize` ([Electron: Code Signing](https://www.electronjs.org/docs/latest/tutorial/code-signing)). Die Standard-Entitlements enthalten u. a. `com.apple.security.cs.allow-jit` ([osx-sign](https://github.com/electron/osx-sign/blob/main/entitlements/default.darwin.plist)).

**Testen:** WebdriverIO, Selenium oder Playwright. Laut Doku hat Playwright „experimental Electron support“ ([Electron: Automated Testing](https://www.electronjs.org/docs/latest/tutorial/automated-testing)).

**Laufzeit und Pflege**

- Mehrere Prozesse nach Chromium-Vorbild ([Electron: Process Model](https://www.electronjs.org/docs/latest/tutorial/process-model)). Lokal: 4 Prozesse, etwa 80 MB.
- Electron bringt alle 8 Wochen eine Major-Version und unterstützt nur die letzten drei ([Electron: Timelines](https://www.electronjs.org/docs/latest/tutorial/electron-timelines)).
- Unter macOS 27 ist offen, dass ein Klick auf Panel-Fenster die App aktiviert ([electron#53889](https://github.com/electron/electron/issues/53889)).

**Praxisbeispiel:** CCSeva gibt es als Electron-App (`electron`, `electron-builder`) und daneben als native Swift-Variante, ausdrücklich „a Swift/AppKit/SwiftUI replacement for the Electron CCSeva app … one ~2 MB binary“ ([package.json](https://github.com/Iamshankhadeep/ccseva/blob/main/package.json), [swift/README](https://github.com/Iamshankhadeep/ccseva/blob/main/swift/README.md)).

### E. Weitere Optionen (kurz)

| Option | Was es ist | Warum eher nicht |
|---|---|---|
| SwiftBar-Plugin | Ein Plugin „is an executable script in the language of your choice“, dessen Ausgabe SwiftBar als Menü rendert. Optional geht auch ein Webview ([SwiftBar](https://github.com/swiftbar/SwiftBar)). | Das ist keine eigenständige App: Nutzer müssen SwiftBar installieren, und es gibt keine eigene Signatur oder Notarisierung. Als Wegwerf-Prototyp für die Datenquelle taugt es trotzdem. |
| Wails (Go + WebView) | Ein Tauri-ähnliches Modell mit Go. v3 hat den Status „Beta“ ([Wails](https://github.com/wailsapp/wails)). | Gleiche WebView-Trade-offs wie Tauri, kleineres Ökosystem, v3 noch nicht stabil. |
| Übersicht-Widget | Ein Desktop-Widget, z. B. claude-code-meter ([GitHub](https://github.com/gxjansen/claude-code-meter)) | Kein Menüleisten-Dropdown, braucht eine Host-App. |

---

## Querschnittsthemen

### Agent-Tauglichkeit: bauen, testen, UI prüfen ohne Xcode-GUI

**Swift, Projektformate**

| Weg | Wie | Trade-off |
|---|---|---|
| **Nur SwiftPM** | `swift build` und `swift test`. Das `.app`-Bundle baut ein Skript: Binary kopieren, Info.plist schreiben, `codesign` (lokal geprüft). | Es gibt keine Projektdatei, die man pflegen müsste, und keine Abhängigkeiten. Das Bundle-Skript (Icon, Info.plist, Signatur) pflegen die Agents aber selbst. Echte Apps arbeiten so: CodexBar mit `Scripts/package_app.sh`, `compile_and_run.sh` und `sign-and-notarize.sh` ([CodexBar AGENTS.md](https://github.com/steipete/CodexBar/blob/main/AGENTS.md)), CCSeva-Swift mit „SwiftPM executable package (no .xcodeproj)“ ([README](https://github.com/Iamshankhadeep/ccseva/blob/main/swift/README.md)). |
| **XcodeGen** | Ein YAML- oder JSON-Spec erzeugt das `.xcodeproj`, „remove your `.xcodeproj` from git … no more merge conflicts“, „Generate from anywhere including on CI“ ([XcodeGen](https://github.com/yonaskolb/XcodeGen)). Aktuelle Version 2.46.0 vom Juli 2026. | Danach greifen die Standard-Xcode-Mechanismen (Asset-Catalogs, Entitlements, `xcodebuild archive`/`-exportArchive`). Dafür braucht es ein zusätzliches Tool (Homebrew o. ä.). |
| **Tuist** | „Generated projects“ aus Swift-Manifesten ([Tuist](https://github.com/tuist/tuist)) | Mächtiger, aber auch schwerer als XcodeGen. Für eine Ein-Target-App ist das **Einschätzung:** überdimensioniert. |
| **Xcode-Projekt mit Buildable Folders** | Seit Xcode 16 speichern „buildable folders“ nur den Ordnerpfad, nicht jede Datei ([Xcode 16 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-16-release-notes)) | Agents müssen beim Anlegen von Dateien `project.pbxproj` kaum noch anfassen. Das erste Anlegen des Projekts geht aber nicht per CLI (**Einschätzung**). |
| **`xcodebuild` auf `Package.swift`** | `xcodebuild test -scheme … -destination platform=macOS -resultBundlePath`, dazu `xcresulttool` für JSON (lokal geprüft) | Testergebnisse sind maschinenlesbar, ein Bundle entsteht so aber nicht. |

**Swift, Toolchain-Feedback**

- Swift 6 prüft Data Races vollständig ([Swift Migration Guide](https://github.com/swiftlang/swift-migration-guide/blob/main/Guide.docc/EnableDataRaceSafety.md)).
- Seit Swift 6.2 isoliert `.defaultIsolation(MainActor.self)` pro Target alles standardmäßig auf den Main Actor ([SE-0466](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md)). Laut Swift.org ist das für „scripts, UI code, and other executable targets“ gedacht ([Swift 6.2](https://www.swift.org/blog/swift-6.2-released/)).
- **Einschätzung:** Für eine kleine UI-App senkt das die Zahl der Concurrency-Fehler deutlich, mit denen Agents sonst ringen.

**Swift, Apples Agent-Werkzeuge in Xcode 27**

- Xcode 27 bringt SwiftUI-Skills für Coding-Agents mit ([WWDC26 SwiftUI-Guide](https://developer.apple.com/wwdc26/guides/swiftui/)). Lokal lassen sie sich über `xcrun mcpbridge run-agent skills export` exportieren. Der Export blieb im Test ohne laufendes Xcode hängen.
- Externe Agents binden Xcode per MCP an: `claude mcp add --transport stdio xcode -- xcrun mcpbridge`. Dabei gilt: „Before prompting an external agent (outside of Xcode), be sure to open your project in Xcode“ ([Apple](https://developer.apple.com/documentation/xcode/giving-external-agents-access-to-xcode)).
- Die MCP-Tools rendern Previews, das Tool „Preview Snapshot“ auch in Varianten wie Light und Dark. `RenderPreview` funktioniert für macOS-Previews. Seit Beta 5 gibt es eine Vorschau eines MCP-Servers „that runs without requiring an open Xcode workspace“ (`sudo xcrun mcp-server enable`), ausdrücklich als „early preview“ ([Xcode 27 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)).
- Lokal nicht getestet, um keine Freigabedialoge auszulösen.

**Swift, UI-Prüfung ohne Xcode**

- Ein PNG über `NSHostingView` mit `cacheDisplay` aus `swift test` oder einem `--snapshot`-Flag funktioniert, auch für AppKit-Controls (lokal geprüft).
- `ImageRenderer` ersetzt AppKit-Controls durch Platzhalter (lokal geprüft, [Apple](https://developer.apple.com/documentation/swiftui/imagerenderer)).
- `swift-snapshot-testing` hat eine SwiftUI-Strategie nur für iOS/tvOS ([Quelle](https://github.com/pointfreeco/swift-snapshot-testing/blob/main/Sources/SnapshotTesting/Snapshotting/SwiftUIView.swift)). Unter macOS geht der Weg über die `NSView`-Strategie ([Quelle](https://github.com/pointfreeco/swift-snapshot-testing/blob/main/Sources/SnapshotTesting/Snapshotting/NSView.swift)).

**Web-Stacks (C, D)**

- Die UI ist HTML. Agents können sie mit Playwright rendern und Screenshots vergleichen. Für Electron gibt es offizielle Wege über Playwright und WebdriverIO ([Electron](https://www.electronjs.org/docs/latest/tutorial/automated-testing)), für Tauri unter macOS nur den eingebetteten WebDriver-Server ([Tauri](https://v2.tauri.app/develop/tests/webdriver/)).
- TypeScript ist seit August 2025 die meistgenutzte Sprache auf GitHub. GitHub verbindet das mit „Typed languages that make agent-assisted coding more reliable“ ([Octoverse 2025](https://github.blog/news-insights/octoverse/octoverse-a-new-developer-joins-github-every-second-as-ai-leads-typescript-to-1/)).

**Einschätzung zur Zuverlässigkeit der Agents**

Primärquellen, die Stacks nach Agent-Erfolgsquote vergleichen, habe ich nicht gefunden. Belegt sind die Feedback-Schleifen:

- **Swift (A/B):** Compiler und Typprüfung sind streng. Build, Test und Snapshot laufen komplett per CLI (lokal in wenigen Schritten, erster Build fehlerfrei). Apple liefert eigene Agent-Skills und MCP-Tools. Es gibt zwei echte, aktiv gepflegte Menüleisten-Apps nach dem Muster „SwiftPM ohne `.xcodeproj`“ (CodexBar, CCSeva-Swift). Schwach sind die geringere Menge an Trainingscode im Vergleich zu TS und dass sich das Live-Verhalten der Menüleiste headless nur schwer prüfen lässt (CodexBar-Hinweis oben).
- **Web (C/D):** Agents schreiben und prüfen die UI am leichtesten. Der Teil, an dem eine Menüleisten-App aber hängt (Tray, Position, Keychain, Autostart, Notarisierung), steckt in Plugins und Konfiguration und ist schwerer zu verifizieren. Bei Tauri kommen zwei Sprachen und das Capabilities-System dazu.

### Keychain-Zugriff auf `Claude Code-credentials`

**Lokale Befunde**

- Der Eintrag liegt im dateibasierten Login-Schlüsselbund (`login.keychain-db`), Klasse `genp`, erstellt am 26.08.2026 und zuletzt geändert am 03.10.2026 um 06:32. Claude Code schreibt ihn also regelmäßig neu.
- Die ACL (per `security dump-keychain -a`, gefiltert auf diesen Eintrag) erlaubt `decrypt` u. a. **nur** für `/usr/bin/security` (`identifier "com.apple.security" and anchor apple`). Die `partition_id` ist `apple-tool:`.
- Das Binary von Claude Code 2.1.288 ruft `security add-generic-password -U -a … -s … -X …` und `security find-generic-password -a … -w -s …` auf. Claude Code verwaltet den Eintrag also selbst über das `security`-CLI.
- `security find-generic-password -s "Claude Code-credentials" -w > /dev/null` endete mit Exit-Code 0 und **ohne Dialog**.

**Was daraus folgt**

1. **Direkt über Security.framework** (`SecItemCopyMatching`, aus jedem Stack):
   - Der eigene Prozess steht nicht in der ACL, also erscheint der Dialog „Allow Once / Always Allow / Deny“ ([Apple Support](https://support.apple.com/guide/keychain-access/kyca1243/mac)).
   - Dateibasierte Einträge muss man über die dateibasierte Keychain lesen. Sie nutzt ACLs (`SecAccess`), keine Access Groups ([TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)).
   - Laut CodexBar kann Claude Code den Eintrag neu anlegen und dabei den Grant zurücksetzen. In einem Trace blieb der CodexBar-Eintrag in der Decrypt-ACL stehen, die Team-ID verschwand aber aus der Partition-ACL. „repeated manual grants therefore need not survive the next Claude Code refresh“ ([CodexBar docs/claude.md](https://github.com/steipete/CodexBar/blob/main/docs/claude.md)).
   - Ad-hoc-signierte Entwicklungs-Builds müssen eventuell erneut autorisiert werden, weil die ACL die Code-Signatur prüft ([CodexBar docs/keychain-prompts.md](https://github.com/steipete/CodexBar/blob/main/docs/keychain-prompts.md)).
2. **Subprozess `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w`:**
   - Läuft still, weil `security` in der ACL steht (lokal geprüft).
   - Das funktioniert in jedem Stack: Swift `Process`, Node `child_process`, Rust `std::process::Command`.
   - CCSeva macht genau das, „with a 10 s hard timeout (the call can otherwise hang on a keychain authorization prompt)“ ([CCSeva swift/README](https://github.com/Iamshankhadeep/ccseva/blob/main/swift/README.md)). CodexBar führt den Weg als „experimental“, weil „`security` can prompt“ ([Quelle](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthCredentials+SecurityCLIReader.swift)).
   - **Einschätzung:** Das ist ein undokumentiertes Implementierungsdetail von Claude Code und kann sich mit einem Update ändern.
3. **Stack-Bezug:** Der Zugriff ist überall gleich schwer. Für Electron fällt die gängige native Bibliothek `keytar` weg, sie ist seit Dezember 2022 archiviert ([GitHub](https://github.com/atom/node-keytar)).
4. **Agent-Tests:** CodexBar verbietet Agents Tests, „that can display macOS Keychain prompts“ ([AGENTS.md](https://github.com/steipete/CodexBar/blob/main/AGENTS.md)). Der Keychain-Zugriff gehört also hinter eine austauschbare Schnittstelle mit Stub. Das gilt für jeden Stack.

### Signieren und Notarisieren per CLI (CI-tauglich)

- Für Developer ID ist Notarisierung Pflicht. Voraussetzungen sind ein „Developer ID“-Zertifikat und die Hardened Runtime ([Apple](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)).
- `xcrun notarytool submit … --wait` akzeptiert ein Keychain-Profil (`store-credentials`) oder einen App-Store-Connect-API-Key (`--key`, `--key-id`, `--issuer`). Das `.app` wird vorher als ZIP verpackt (`ditto -c -k --keepParent`), danach heftet man das Ticket an ([Apple](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow); Optionen lokal per `notarytool submit --help` geprüft).
- **Swift mit SwiftPM:** `codesign --force --timestamp --options runtime --sign "Developer ID Application: …"`, dann `notarytool` und `stapler`. Ein reales Skript mit API-Key aus Env-Variablen findet sich bei CodexBar ([sign-and-notarize.sh](https://github.com/steipete/CodexBar/blob/main/Scripts/sign-and-notarize.sh)).
- **Swift mit Xcode-Projekt (XcodeGen/Tuist):** `xcodebuild -exportArchive -exportOptionsPlist …` ([Apple](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)).
- **Tauri:** in `tauri build` integriert ([Doku](https://v2.tauri.app/distribute/sign/macos/)). **Electron:** Forge oder Packager ([Doku](https://www.electronjs.org/docs/latest/tutorial/code-signing)).
- **CI:** Für GitHub Actions gibt es das Image `runs-on: xcode-27`, als „preview“. Seit 16.09.2026 basiert es auf macOS 27 ([runner-images#14404](https://github.com/actions/runner-images/issues/14404)). Für Swift reicht damit Xcode im Runner. Tauri braucht zusätzlich Rust und Node, Electron Node.

### Bekannte Eigenheiten von `MenuBarExtra`

1. **Öffnen und Schließen per Code:** `MenuBarExtra` „lacks 1st-party API to get or set the menu presentation state, … access the `NSStatusItem`, or access the popup's `NSWindow`. (Still as of Xcode 26)“ ([MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess)). Die SwiftUI-Updates von Juni und September 2026 nennen dazu nichts Neues ([Apple: SwiftUI updates](https://developer.apple.com/documentation/updates/swiftui)).
2. **macOS 27 hat den Workaround gebrochen:** Unter 27 waren in MenuBarExtraAccess der „presented“-Toggle und das Schließen per Button wirkungslos ([Issue #25](https://github.com/orchetect/MenuBarExtraAccess/issues/25)). Der Fix ruft `_beginExpandedInterfaceSession:` auf, also eine private Methode ([PR #26](https://github.com/orchetect/MenuBarExtraAccess/pull/26)). Programmatisches Öffnen hängt damit an privater API. **Einschätzung:** Für v1 egal, weil sich das Dropdown nur per Klick öffnet.
3. **Fenstergröße:** Der `.window`-Style richtet sich nach dem Inhalt.
   - Mit `ScrollView` war das Fenster beim ersten Öffnen korrekt und danach kleiner ([Forum 741553](https://developer.apple.com/forums/thread/741553), 2023).
   - Laut FluidMenuBarExtra blendet `.window` beim Schließen nicht aus, „doesn't persist selection state when the menu is opened“ und hat „a less-than-ideal resizing mechanism“ ([FluidMenuBarExtra](https://github.com/lfroms/fluid-menu-bar-extra)).
   - Für Tabs heißt das **Einschätzung:** den gewählten Tab im Modell oder in `@AppStorage` halten, nicht nur im View-`@State`, und die Größe fix setzen (z. B. `.frame(width:)`). Auf macOS 27 nicht verifiziert.
4. **Fokus, Settings und Fenster:**
   - `SettingsLink`/`openSettings()` funktionieren in Menüleisten-Apps unzuverlässig. Der bekannte Workaround schaltet die Activation Policy kurz auf `.regular` und zurück ([steipete.me](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items)).
   - Auf macOS 27.0 berichtet CodexBar, dass das Zurückschalten auf `.accessory` still fehlschlägt und das Dock-Icon bleibt, reproduzierbar mit einer minimalen AppKit-App ([CodexBar#4101](https://github.com/steipete/CodexBar/issues/4101)).
   - **Einschätzung:** `LSUIElement` im Info.plist setzen und die Policy zur Laufzeit nicht wechseln. Ohne Einstellungsfenster in v1 betrifft das die App kaum.
5. **Wenn Nutzer das Extra entfernen:** „An app that only shows in the menu bar will be automatically terminated if the user removes the extra from the menu bar“ ([Apple](https://developer.apple.com/documentation/swiftui/menubarextra)). Seit macOS 26 gibt es „Menu Bar > Allow in the Menu Bar“. Prozesse, die sich nicht auf eine Bundle-ID abbilden ließen, fehlten dort zeitweise, betroffen war z. B. Qt mit eigenem `NSApplicationMain` ([Forum 794920](https://developer.apple.com/forums/thread/794920)).

### Kein Dock-Icon und Autostart, Überblick

| | Swift (A/B) | Tauri | Electron |
|---|---|---|---|
| Kein Dock-Icon | `LSUIElement` ([Apple](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement)), lokal geprüft | `ActivationPolicy::Accessory` oder Info.plist-Merge | `dock.hide()` (lokal geprüft), `setActivationPolicy`, `extendInfo` |
| Autostart | `SMAppService.mainApp` ([Apple](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)) | LaunchAgent-Plist oder AppleScript ([Quelle](https://github.com/tauri-apps/plugins-workspace/blob/v2/plugins/autostart/src/lib.rs)) | `setLoginItemSettings` → SMAppService, braucht Signatur und Notarisierung ([Doku](https://www.electronjs.org/docs/latest/api/app)) |

### Erweiterbarkeit um weitere Provider-Tabs

- Alle Stacks schaffen Tabs mühelos. In SwiftUI ist das ein `Picker`/`TabView` über eine Liste von Providern, im Web eine Komponente pro Provider.
- **Einschätzung:** Entscheidend ist nicht der Stack, sondern die Provider-Schnittstelle: Daten holen, Limits liefern und Keychain-Zugriff abstrahieren. Diese Naht macht zugleich die Agent-Tests ohne Keychain-Dialog möglich.
- CodexBar zeigt den Preis von Komplexität: dort gibt es viele Provider, Quellen und Fallbacks ([docs/claude.md](https://github.com/steipete/CodexBar/blob/main/docs/claude.md)).

---

## Trade-offs zusammengefasst

1. **Leichtgewicht gegen Web-UI-Komfort:** Swift ist bei Speicher (16 MB gegen 48 bzw. 80 MB) und Paketgröße klar vorn. Web-Stacks machen UI-Iterationen und Screenshot-Prüfung am bequemsten.
2. **Apple pflegt die Menüleiste gegen eigene Kontrolle:** `MenuBarExtra` gleicht die Umbauten von macOS 27 automatisch aus, gibt aber wenig Kontrolle. Mit AppKit, Tauri oder Electron hat man Kontrolle, hängt aber an eigenem Code oder Upstream-Fixes. Das zeigen die macOS-27-Brüche: Forum-Threads, `tray-icon`-Fix im September 2026, offene Electron-Issues.
3. **Eine Toolchain gegen zwei:** Swift braucht nur Xcode/SwiftPM. Tauri braucht Rust und Node, Electron Node plus Packager-Ökosystem.
4. **Bundle-Skript gegen Projekt-Generator:** Reines SwiftPM ist abhängigkeitsfrei, aber Agents pflegen das Packaging selbst. XcodeGen bringt Standard-Xcode-Mechanismen und funktioniert besser mit Xcodes Agent-Tools, die ein offenes Projekt erwarten, kostet aber ein zusätzliches Tool.
5. **Keychain neutralisiert:** Kein Stack hat hier einen Vorteil. Der stille Weg über `/usr/bin/security` hängt an einem Implementierungsdetail von Claude Code.

## Tendenz (ausdrücklich nur eine Tendenz, keine Entscheidung)

**Tendenz:** Option **A, SwiftUI `MenuBarExtra(.window)`**, gebaut als SwiftPM-Package mit kleinem Bundle- und Signatur-Skript wie bei CodexBar und CCSeva-Swift. Dazu:

- `.defaultIsolation(MainActor.self)`,
- `LSUIElement` im Info.plist,
- `SMAppService.mainApp` für den Autostart,
- PNG-Snapshots über `NSHostingView` als Selbstprüfung der Agents,
- der Keychain-Zugriff hinter einer Provider-Schnittstelle.

Option **B (hybrid)** bliebe die Ausweichroute, falls `MenuBarExtra` an Fenstergröße oder Verhalten scheitert. Das gleiche SwiftUI-Panel ließe sich dann in ein eigenes `NSStatusItem` einhängen, inklusive `expandedInterfaceDelegate`.

Gründe: geringster Ressourcenbedarf, keine Fremd-Runtime, Apple pflegt die Menüleisten-Integration unter macOS 27, und Build, Test und Snapshot ohne Xcode-GUI sind lokal nachgewiesen.

Gegenargumente, die das Entscheidungsticket abwägen sollte:

- Web-Stacks sind für Agents vertrauter.
- Live-Verhalten der Menüleiste lässt sich headless kaum prüfen.
- Die Eigenheiten von `MenuBarExtra` (Punkte 1–4 oben).

## Offene Punkte und nicht Geprüftes

- Keine echte Tauri-App gebaut (kein Rust lokal). Die Speicherzahl ist eine WKWebView-Näherung.
- XcodeGen und Tuist nicht lokal ausprobiert.
- Xcode-MCP (`RenderPreview`, headless `mcp-server`) nicht lokal ausprobiert. Nötig wären Freigabedialoge bzw. `sudo`.
- Dropdown nicht live geöffnet. Speicher bei offenem Dropdown, Klickverhalten und Live-Screenshots fehlen deshalb, weil sie Bedienungshilfen- bzw. Bildschirmaufnahme-Freigaben brauchen.
- Echte Developer-ID-Signatur und Notarisierung nicht ausgeführt, nur ad-hoc signiert. Die Optionen von notarytool wurden per `--help` geprüft.
- Ob Claude Code seinen Keychain-Eintrag dauerhaft über das `security`-CLI anlegt, ist nicht dokumentiert, nur im Binary beobachtet.

## Quellen

**Apple**
- MenuBarExtra: https://developer.apple.com/documentation/swiftui/menubarextra
- MenuBarExtraStyle.window: https://developer.apple.com/documentation/swiftui/menubarextrastyle/window
- SwiftUI updates: https://developer.apple.com/documentation/updates/swiftui
- AppKit updates: https://developer.apple.com/documentation/updates/appkit
- NSStatusItem: https://developer.apple.com/documentation/appkit/nsstatusitem
- NSStatusItem.expandedInterfaceDelegate: https://developer.apple.com/documentation/appkit/nsstatusitem/expandedinterfacedelegate
- NSStatusItem.expandedInterfaceSession: https://developer.apple.com/documentation/appkit/nsstatusitem/expandedinterfacesession
- NSHostingSceneRepresentation: https://developer.apple.com/documentation/swiftui/nshostingscenerepresentation
- ImageRenderer: https://developer.apple.com/documentation/swiftui/imagerenderer
- LSUIElement: https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement
- SMAppService: https://developer.apple.com/documentation/servicemanagement/smappservice
- SMAppService.mainApp: https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp
- TN3137 On Mac keychain APIs and implementations: https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains
- Keychain-Zugriffsdialog: https://support.apple.com/guide/keychain-access/kyca1243/mac
- Notarizing macOS software before distribution: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- Customizing the notarization workflow: https://developer.apple.com/documentation/security/customizing-the-notarization-workflow
- Giving external agents access to Xcode: https://developer.apple.com/documentation/xcode/giving-external-agents-access-to-xcode
- Extending and customizing agents: https://developer.apple.com/documentation/xcode/extending-and-customizing-agents
- Xcode 27 Release Notes: https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes
- Xcode 16 Release Notes: https://developer.apple.com/documentation/xcode-release-notes/xcode-16-release-notes
- WWDC26-289 Modernize your AppKit app: https://developer.apple.com/videos/play/wwdc2026/289/
- WWDC26-272 Use SwiftUI with AppKit and UIKit: https://developer.apple.com/videos/play/wwdc2026/272/
- WWDC26-259 Xcode, agents, and you: https://developer.apple.com/videos/play/wwdc2026/259/
- WWDC26 SwiftUI-Guide: https://developer.apple.com/wwdc26/guides/swiftui/
- Forum 836113 (NSStatusItem-Probleme macOS 27): https://developer.apple.com/forums/thread/836113
- Forum 832823 (NSStatusItem-Interaktionen macOS 27): https://developer.apple.com/forums/thread/832823
- Forum 794920 (MenuBarExtra fehlt, macOS 26): https://developer.apple.com/forums/thread/794920
- Forum 741553 (MenuBarExtra-Fenstergröße): https://developer.apple.com/forums/thread/741553
- Bedienungshilfen-Freigabe: https://support.apple.com/guide/mac-help/mh43185/mac
- Bildschirmaufnahme-Freigabe: https://support.apple.com/guide/mac-help/mchld6aa7d23/mac

**Swift**
- Swift 6.2 Released: https://www.swift.org/blog/swift-6.2-released/
- SE-0466 Default actor isolation: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md
- Swift Migration Guide, Data-race safety: https://github.com/swiftlang/swift-migration-guide/blob/main/Guide.docc/EnableDataRaceSafety.md
- swift-snapshot-testing: https://github.com/pointfreeco/swift-snapshot-testing
- XcodeGen: https://github.com/yonaskolb/XcodeGen
- Tuist: https://github.com/tuist/tuist
- MenuBarExtraAccess (README, #25, PR #26): https://github.com/orchetect/MenuBarExtraAccess
- FluidMenuBarExtra: https://github.com/lfroms/fluid-menu-bar-extra
- Settings aus Menüleisten-Apps (Peter Steinberger): https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items

**Tauri**
- System Tray: https://v2.tauri.app/learn/system-tray/
- macOS Code Signing: https://v2.tauri.app/distribute/sign/macos/
- macOS Application Bundle: https://v2.tauri.app/distribute/macos-application-bundle/
- WebDriver: https://v2.tauri.app/develop/tests/webdriver/
- Positioner: https://v2.tauri.app/plugin/positioner/
- Autostart (Doku und Quellcode): https://v2.tauri.app/plugin/autostart/, https://github.com/tauri-apps/plugins-workspace/blob/v2/plugins/autostart/src/lib.rs
- Process Model: https://v2.tauri.app/concept/process-model/
- Webview Versions: https://v2.tauri.app/reference/webview-versions/
- Start (App-Größe): https://v2.tauri.app/start/
- Capabilities: https://v2.tauri.app/security/capabilities/
- `set_activation_policy`: https://github.com/tauri-apps/tauri/blob/dev/crates/tauri/src/app.rs
- macOS-27-Tray-Bug: https://github.com/tauri-apps/tauri/issues/16035, https://github.com/tauri-apps/tray-icon/issues/355, https://github.com/tauri-apps/tray-icon/pull/365
- tauri-nspanel: https://github.com/ahkohd/tauri-nspanel
- Menüleisten-Beispiel: https://github.com/ahkohd/tauri-macos-menubar-app-example

**Electron**
- Tray: https://www.electronjs.org/docs/latest/api/tray
- app (Activation Policy, Login Items): https://www.electronjs.org/docs/latest/api/app
- Dock: https://www.electronjs.org/docs/latest/api/dock
- Code Signing: https://www.electronjs.org/docs/latest/tutorial/code-signing
- Automated Testing: https://www.electronjs.org/docs/latest/tutorial/automated-testing
- Process Model: https://www.electronjs.org/docs/latest/tutorial/process-model
- Release-Timelines: https://www.electronjs.org/docs/latest/tutorial/electron-timelines
- osx-sign Entitlements: https://github.com/electron/osx-sign/blob/main/entitlements/default.darwin.plist
- @electron/packager `extendInfo`: https://github.com/electron/packager/blob/main/src/types.ts
- menubar: https://github.com/max-mapper/menubar
- node-keytar (archiviert): https://github.com/atom/node-keytar
- electron#53889: https://github.com/electron/electron/issues/53889

**Echte Menüleisten-Apps und Sonstiges**
- CodexBar: https://github.com/steipete/CodexBar (AGENTS.md, Scripts/sign-and-notarize.sh, docs/keychain-prompts.md, docs/claude.md, Issue #4101)
- CCSeva (Electron und native Swift): https://github.com/Iamshankhadeep/ccseva
- SwiftBar: https://github.com/swiftbar/SwiftBar
- Wails: https://github.com/wailsapp/wails
- claude-code-meter (Übersicht): https://github.com/gxjansen/claude-code-meter
- GitHub Octoverse 2025: https://github.blog/news-insights/octoverse/octoverse-a-new-developer-joins-github-every-second-as-ai-leads-typescript-to-1/
- GitHub-Actions-Image Xcode 27: https://github.com/actions/runner-images/issues/14404
