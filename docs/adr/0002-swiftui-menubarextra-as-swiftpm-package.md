# Native SwiftUI with `MenuBarExtra`, built as a pure SwiftPM package

The app is built in Swift 6 with SwiftUI. The menu bar is handled by `MenuBarExtra` in `.window` style; the project is a pure SwiftPM package without an `.xcodeproj` and without third-party dependencies; the minimum version is macOS 27. The deciding factor is that agents build the app alone and verify it themselves: build, tests and PNG snapshots run entirely via `swift build`/`swift test` without the Xcode GUI (verified locally), the strict compiler catches errors early, and the tricky part of a menu bar app (status item, launch at login, no Dock icon) comes from Apple APIs instead of plugins. On top of that, at 16 MB of RAM when idle the stack is the lightest, in line with the guiding principle "simple".

## Considered Options

- **Tauri 2:** a web UI that agents can conveniently check in a browser. In exchange: two toolchains (Rust and Node), about three times the memory, panel positioning and launch at login (without SMAppService) only via plugins, and the click bug in the macOS 27 menu bar was open until September 2026.
- **Electron:** the largest ecosystem, but a package of about 300 MB, 80 MB of RAM, 4 processes, a major version every 8 weeks, and open macOS 27 issues.
- **AppKit `NSStatusItem` with its own popover or window (like CodexBar):** full control over opening, closing and position. On macOS 27 the app would have to implement the new Expanded Interface Session itself via `expandedInterfaceDelegate`, where the developer forums report many breakages. v1 doesn't need that control, because the dropdown only opens on click.
- **XcodeGen, Tuist or an Xcode project:** standard Xcode mechanisms and access to Xcode's agent tooling, which however needs Xcode to be open. Costs an extra tool or a project file that can't be created via the CLI.

## Consequences

- **Structure:** Logic and views live in a library; the executable target is only the shell with the `MenuBarExtra` scene. The dropdown is a standalone view with a fixed width; its state lives in the model, not in view state, because `MenuBarExtra` discards view state on close.
- **Fallback route:** If `MenuBarExtra` fails on window size or behavior, only the shell is swapped for a custom `NSStatusItem`; the view stays.
- **Swift settings:** Swift 6 language mode with full data-race checking and `.defaultIsolation(MainActor.self)`. Only the `claude` call runs explicitly in the background.
- **Bundle:** A script builds the `.app` bundle from the SwiftPM build (Info.plist with `LSUIElement`, icon, signature). Launch at login uses `SMAppService.mainApp`.
- **Self-verification:** Tests use Swift Testing. Snapshot tests render the dropdown and the menu bar item with sample data and a fixed time via `NSHostingView` as PNG, in light and dark with an explicit background, and compare them against reference images in the repo. The agent looks at new reference images before accepting them.
- **Remaining gap:** Behavior in the real menu bar (click, position) can't be verified headless. It is tested via model and state, not via UI automation.
- **No third-party dependencies,** not even in tests. Foundation, SwiftUI and our own code cover the child process, JSON and image comparison.
- **macOS 27 as the minimum version:** Older versions would be unverified, especially since the menu bar changed with 27. Anyone still on macOS 26 can't launch the app. The bar can be lowered later.
