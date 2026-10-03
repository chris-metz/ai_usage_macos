# Native SwiftUI mit `MenuBarExtra`, gebaut als reines SwiftPM-Package

Die App wird in Swift 6 mit SwiftUI gebaut. Die Menüleiste übernimmt `MenuBarExtra` im `.window`-Style, das Projekt ist ein reines SwiftPM-Package ohne `.xcodeproj` und ohne Fremdabhängigkeiten, die Mindestversion ist macOS 27. Den Ausschlag gibt, dass Agents die App allein bauen und selbst prüfen: Build, Tests und PNG-Snapshots laufen komplett per `swift build`/`swift test` ohne Xcode-GUI (lokal nachgewiesen), der strenge Compiler fängt Fehler früh, und der heikle Teil einer Menüleisten-App (Status Item, Autostart, kein Dock-Icon) kommt aus Apple-APIs statt aus Plugins. Dazu ist der Stack mit 16 MB RAM im Leerlauf am leichtesten, passend zum Leitprinzip „einfach“.

## Considered Options

- **Tauri 2:** Web-UI, die Agents bequem im Browser prüfen. Dafür zwei Toolchains (Rust und Node), etwa dreimal so viel Speicher, Panel-Position und Autostart (ohne SMAppService) nur über Plugins, und der Klick-Bug der macOS-27-Menüleiste war bis September 2026 offen.
- **Electron:** größtes Ökosystem, aber etwa 300 MB Paket, 80 MB RAM, 4 Prozesse, alle 8 Wochen eine Major-Version und offene macOS-27-Issues.
- **AppKit `NSStatusItem` mit eigenem Popover oder Fenster (wie CodexBar):** volle Kontrolle über Öffnen, Schließen und Position. Unter macOS 27 müsste die App dafür die neue Expanded Interface Session über `expandedInterfaceDelegate` selbst umsetzen, wo das Entwicklerforum viele Brüche meldet. v1 braucht diese Kontrolle nicht, weil sich das Dropdown nur per Klick öffnet.
- **XcodeGen, Tuist oder ein Xcode-Projekt:** Standard-Xcode-Mechanismen und Anschluss an Xcodes Agent-Werkzeuge, die aber ein geöffnetes Xcode brauchen. Kostet ein zusätzliches Tool bzw. eine Projektdatei, die sich nicht per CLI anlegen lässt.

## Consequences

- **Aufbau:** Logik und Views liegen in einer Library, das ausführbare Target ist nur die Hülle mit der `MenuBarExtra`-Scene. Das Dropdown ist eine eigenständige View mit fester Breite, ihr Zustand liegt im Modell, nicht im View-State, weil `MenuBarExtra` ihn beim Schließen verwirft.
- **Ausweichroute:** Scheitert `MenuBarExtra` an Fenstergröße oder Verhalten, wird nur die Hülle gegen ein eigenes `NSStatusItem` getauscht, die View bleibt.
- **Swift-Einstellungen:** Swift-6-Sprachmodus mit voller Data-Race-Prüfung und `.defaultIsolation(MainActor.self)`. Nur der Aufruf von `claude` läuft ausdrücklich im Hintergrund.
- **Bundle:** Ein Skript baut aus dem SwiftPM-Build das `.app`-Bundle (Info.plist mit `LSUIElement`, Icon, Signatur). Autostart läuft über `SMAppService.mainApp`.
- **Selbstprüfung:** Tests mit Swift Testing. Snapshot-Tests rendern Dropdown und Menüleisten-Symbol mit Beispieldaten und fester Uhrzeit über `NSHostingView` als PNG, in Hell und Dunkel mit explizitem Hintergrund, und vergleichen sie mit Referenzbildern im Repo. Neue Referenzbilder sieht sich der Agent an, bevor er sie übernimmt.
- **Restlücke:** Das Verhalten in der echten Menüleiste (Klick, Position) lässt sich headless nicht prüfen. Es wird über Modell und Zustand getestet, nicht über UI-Automation.
- **Keine Fremdabhängigkeiten,** auch nicht in Tests. Kindprozess, JSON und Bildvergleich decken Foundation, SwiftUI und eigener Code ab.
- **macOS 27 als Mindestversion:** Ältere Versionen wären ungeprüft, gerade die Menüleiste hat sich mit 27 geändert. Wer noch macOS 26 nutzt, kann die App nicht starten. Die Grenze lässt sich später senken.
