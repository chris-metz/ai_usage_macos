# Pacemark v1 spec

Pacemark is a macOS menu bar app that shows the limits of your Claude subscription as bars with a pace marker: the session limit, the weekly limit and every model limit (today the Fable limit). This spec is the complete brief for building v1. It merges every decision of [Map: v1 spec for the menu bar app for Claude limits](https://github.com/chris-metz/pacemark/issues/1). The tickets hold the reasons, and this document holds the result.

**How to use it**

- Terms are defined in [`GLOSSARY.md`](../GLOSSARY.md). Use them in code, tests and docs, e.g. `utilization`, never "usage".
- The decisions that are hard to reverse live in two ADRs, and this spec doesn't repeat their reasoning: [ADR 0001](adr/0001-claude-limits-via-claude-cli.md) covers the data source, [ADR 0002](adr/0002-swiftui-menubarextra-as-swiftpm-package.md) the stack and structure.
- Behaviour, strings, thresholds and timings are binding. Use the strings in [Appendix: all strings](#appendix-all-strings) verbatim.
- Type and function names are suggestions; keep them unless you have a reason. Sizes are starting points. The snapshot images are what you check.
- If something isn't settled here, pick the simplest behaviour consistent with this spec and name the choice in your PR description, so the human can confirm it.
- [Build order](#11-build-order) splits the work into steps of one agent session each.

**Contents**

1. [Scope](#1-scope)
2. [The menu bar item](#2-the-menu-bar-item)
3. [The dropdown](#3-the-dropdown)
4. [The settings window](#4-the-settings-window)
5. [Starting and quitting](#5-starting-and-quitting)
6. [Logic](#6-logic)
7. [Provider interface](#7-provider-interface)
8. [Claude provider](#8-claude-provider)
9. [Package, bundle and scripts](#9-package-bundle-and-scripts)
10. [Verification](#10-verification)
11. [Build order](#11-build-order)
12. [Changes made while writing this spec](#12-changes-made-while-writing-this-spec)
13. [Sources](#13-sources)
- [Appendix: all strings](#appendix-all-strings)

---

## 1. Scope

v1 shows the Claude limits of the Claude Code account logged in on the human's own Mac:

- **One provider:** Claude. No tab bar; the dropdown never names Claude.
- **Limits:** the session limit, the weekly limit and every model limit Claude reports.
- **Data source:** only `claude -p "/usage"`. Pacemark never touches credentials ([ADR 0001](adr/0001-claude-limits-via-claude-cli.md)).
- **Distribution:** built locally with `./scripts/install.sh`. There are no releases.
- **Requirements:** macOS 27 or later; Claude Code 2.1.283 or later, installed and logged in.

**Out of scope** (see the map): further providers and the tab bar; the App Store; multiple accounts; history and charts; token or cost statistics; auto-update; notifications; public releases (Developer ID, notarization, GitHub Releases, Homebrew).

**Guiding principle:** simple. Pacemark is deliberately the counter-design to CodexBar. When in doubt, leave it out.

---

## 2. The menu bar item

The item is the label of a `MenuBarExtra` scene, drawn as one image ([ADR 0002](adr/0002-swiftui-menubarextra-as-swiftpm-package.md)). It shows a gauge glyph and, by default, the utilization of the **menu bar limit**.

- **Menu bar limit:** the limit picked in the settings. By default, and whenever the picked limit is missing from the current values, it is the provider's first limit, the session limit. Hiding a limit in the dropdown doesn't affect it.
- **Percentage:** the menu bar limit's displayed utilization ([6.1](#61-pace-and-limit-display)), e.g. `71%`. With no window it shows `0%`.

### States

The first matching row wins. "≥ 90%" refers to the displayed (rounded) percentage.

| Situation | Percentage on (default) | Percentage off |
|---|---|---|
| Loading: no query has finished since launch | glyph | glyph |
| No values: the last query failed temporarily and nothing has loaded yet | glyph | glyph |
| Persistent error | glyph `⚠︎` | glyph `⚠︎` |
| Values, menu bar limit below 90% (or no window: `0%`) | glyph `71%` | glyph |
| Values, menu bar limit ≥ 90% | glyph, `91%` red | glyph red |
| Stale values ([6.3](#63-display)) | glyph, `71%` dimmed | glyph dimmed |
| Stale values, ≥ 90% | glyph, `91%` red and dimmed | glyph red and dimmed |

- Only the element that carries the value changes colour. With the percentage on, that is the text, and the glyph stays in the foreground colour. With the percentage off, the glyph takes over red and dimming.
- `⚠︎` is never red: red in the menu bar means "limit almost exhausted".
- Accessibility text: see [Appendix](#menu-bar-accessibility-text).

### Drawing

Verified in [Can the menu bar item show a red or dimmed percentage?](https://github.com/chris-metz/pacemark/issues/17):

- **One image in every state:** `NSImage(size:flipped:drawingHandler:)` with `isTemplate = false`, passed to the label as `Image(nsImage:)`. Never use `Image` plus `Text`: SwiftUI drops every colour and opacity modifier on the label's `Text`.
- **Colours resolve inside the drawing handler.** Read `NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])`. Dark (`.darkAqua`, `.vibrantDark`) gives a foreground of pure white; light gives pure black. Don't use `labelColor`, `secondaryLabelColor` or any other semantic colour (they render grey on the vibrant menu bar), and don't resolve colours before the handler runs.
- **Red** is `NSColor.systemRed`, resolved in the drawing appearance.
- **Dimmed** is the same colour at alpha **0.4**, for white, black and red alike.
- **Layout:**
  - The SF Symbol `gauge.with.needle` at its default size (15×15 pt), tinted with `NSImage.SymbolConfiguration(paletteColors: [colour])`.
  - A 4 pt gap.
  - The text in `NSFont.menuBarFont(ofSize: 0)` (13 pt, regular), or for a persistent error the SF Symbol `exclamationmark.triangle` at `SymbolConfiguration(pointSize: 13, weight: .regular)` in the foreground colour.
  - The image is as large as its content, with glyph and text centred vertically.
- **Accessibility:** set `accessibilityDescription` on the `NSImage`. SwiftUI drops `.accessibilityLabel` on the label.
- **A pure function:** (menu bar display state) → `NSImage`, so snapshot tests can render it ([10.2](#102-snapshot-tests)).

---

## 3. The dropdown

`MenuBarExtra` in `.window` style holds one SwiftUI view with a fixed width. Its state lives in the app model, not in view state, because `MenuBarExtra` discards view state on close.

### Layout

```
┌────────────────────────────────────────┐
│ Session limit                      71% │
│ ━━━━━━━━━━━━━━━━━━━━━━━━│━━─────────── │
│ Resets in 1 hr 52 min     8% over pace │
│                                        │
│ Weekly limit                       36% │
│ ━━━━━━━━━━━━━━─│────────────────────── │
│ Resets Wed 03:00         4% under pace │
│                                        │
│ Fable limit                         0% │
│ ───────────────│────────────────────── │
│ Resets Wed 03:00        40% under pace │
├────────────────────────────────────────┤
│                       Settings…   Quit │
└────────────────────────────────────────┘
```

`━` is the fill, `─` the track, `│` the pace marker.

- **Width** 300 pt. Padding 12 pt at the top, 14 pt at the sides, 8 pt at the bottom; 12 pt between limits. The height follows the content.
- **One row per limit** that isn't hidden in the settings, in the order the provider delivers them:
  - **Line 1:** the title on the left (13 pt semibold); the displayed utilization on the right (13 pt semibold, monospaced digits).
  - **Bar:** a capsule 6 pt high across the full width. The track is a neutral system fill (`.quaternary`). The fill starts at the left, its width is the displayed utilization / 100, and its colour follows the state below.
  - **Pace marker:** a vertical line 2 pt wide in the primary colour, reaching 3 pt above and below the bar, with a 1.5 pt outline in the dropdown's background colour so it stays visible on the fill. It sits at pace / 100 of the bar width.
  - **Line 2** (11 pt): the reset line on the left (secondary colour), the pace text on the right in its colour.
- **Footer:** a separator, then the stale line (only while values are stale), then "Settings…" and "Quit" as borderless buttons, right-aligned, in the secondary colour. "Settings…" carries ⌘, and "Quit" carries ⌘Q via `.keyboardShortcut`.
- There is **no** tab bar, provider name, refresh button, spinner, or "Updated …" line while everything works. New values replace old ones in place.
- **Accessibility:** each limit row is one element, e.g. "Session limit, 71%, 12% over pace, resets in 1 hr 52 min".

### Limit states

Computed by [6.1](#61-pace-and-limit-display). The first matching state wins.

| State | Bar | Pace marker | Line 2, left | Line 2, right |
|---|---|---|---|---|
| No window | empty | none | `Starts with your next message` | nothing |
| Exhausted | full, red | shown | reset line | `Limit reached`, red |
| High | red | shown | reset line | as over/on/under pace below |
| Over pace | orange | shown | reset line | `12% over pace`, orange |
| On pace | blue | shown | reset line | `On pace`, secondary |
| Under pace | blue | shown | reset line | `4% under pace`, green |

Colours are the macOS system colours `systemBlue`, `systemOrange`, `systemRed` and `systemGreen` (via `Color(nsColor:)`) plus the secondary label colour; all adapt to light and dark. Blue is fixed and doesn't follow the system accent colour.

### Reset line

- **No window:** `Starts with your next message`.
- **Round first:** the reset time is rounded to the nearest full minute before anything else. Claude reports `00:59:59.88` for the weekly limit and `01:00:00` for the Fable limit, which belong to the same reset.
- **Less than 24 h away:** a countdown. The remaining time is rounded **up** to whole minutes, with a floor of 1, so it never shows `0 min`:
  - `Resets in 52 min`
  - `Resets in 1 hr 52 min`
  - `Resets in 2 hr` (no `0 min`)
- **24 h or more away:** the weekday and time, e.g. `Resets Wed 03:00`. Format with `Date.FormatStyle.dateTime.weekday(.abbreviated).hour().minute()` in the system time zone.
- **Locale:** English language with the user's region and hour-cycle preference. Build it from `Locale.autoupdatingCurrent` via `Locale.Components`, replacing only the language with English. The plain current locale on the human's Mac is `de_DE` and would print `Mi.`. Verified: `en_DE` gives `Wed 03:00`, `en_US` gives `Wed 3:00 AM`.

### Other contents

These replace the limit rows; the footer stays.

| Situation | Content |
|---|---|
| Loading | `Loading…` (secondary) |
| No values after a temporary error | heading `Can't load your limits right now`, below it `Trying again shortly.` No link. |
| Persistent error | the problem's heading (13 pt semibold), its message (Markdown, secondary, selectable with `.textSelection(.enabled)` so a command like `claude update` can be copied) and its link, if any |
| All limits hidden | `All limits are hidden.` (secondary) |

With stale values, the bars stay, and the pace marker keeps moving with the current time. The footer shows the stale line `Couldn't update · Last update 23 min ago` on its own row above the buttons.

---

## 4. The settings window

A small window with the title `Pacemark Settings`: one page in the grouped style of System Settings, without tabs. Changes apply at once; there is no Save button.

```
┌─────────────── Pacemark Settings ───────────────┐
│                                                  │
│  General                                         │
│  ┌────────────────────────────────────────────┐  │
│  │ Open at Login                        [ ○ ] │  │
│  │ Refresh every                  [ 5 min ▾ ] │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  Menu Bar                                        │
│  ┌────────────────────────────────────────────┐  │
│  │ Limit                  [ Session limit ▾ ] │  │
│  │ Show percentage                      [ ● ] │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  Dropdown                                        │
│  ┌────────────────────────────────────────────┐  │
│  │ Session limit                        [ ● ] │  │
│  │ Weekly limit                         [ ● ] │  │
│  │ Fable limit                          [ ● ] │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  Version 0.1 (a1b2c3d) · GitHub  [Quit Pacemark] │
└──────────────────────────────────────────────────┘
```

- **Window:** a SwiftUI `Form` with `.formStyle(.grouped)`. The width is fixed at 440 pt, the height follows the number of limits, and it isn't resizable (`.windowResizability(.contentSize)`). There is a single instance.
- **Open at Login** (a switch):
  - It shows `SMAppService.mainApp.status == .enabled`, re-read when the window appears and when the app becomes active. The app stores nothing of its own about it.
  - Switching on calls `register()`, switching off calls `unregister()`. Nothing else ever calls either. On a thrown error: log it and re-read the status.
  - With status `.requiresApproval` (the user turned it off in System Settings, where `register()` changes nothing on macOS 27), the switch shows off. Below it: `Turned off in System Settings.` and a link button `Open Login Items Settings` that calls `SMAppService.openSystemSettingsLoginItems()`.
  - Only the copy at `/Applications/Pacemark.app` touches the login item. Any other copy, such as a test build, shows the switch disabled, never reads the status (reading it from another copy can move the login item there), and shows `Move Pacemark to Applications to use this.` below it.
- **Refresh every:** a picker with `5 min`, `10 min`, `15 min`. The default is 5.
- **Limit** (the menu bar limit): a picker of the current limits by title, in provider order.
  - It selects the stored choice. If the stored choice is missing from the current limits, it shows an extra entry `<stored title> (not available)` and selects that. With nothing stored, it selects the first limit.
  - Picking an entry stores its qualified id and title ([6.5](#65-settings-storage)).
  - Before the first successful query since launch, and while a persistent error is shown, it is disabled and shows the stored title, or `—` without one.
- **Show percentage:** a switch, on by default.
- **Dropdown:** one switch per current limit, labelled with its title; on means shown. Every limit can be hidden, even all of them.
  - The list comes from the most recent successful query since launch, so it is empty before that and while a persistent error is shown. The group then shows `Your limits appear here once Pacemark has loaded them.` instead.
  - Stored hidden limits stay untouched, whether or not the provider currently delivers them.
- **Footer:**
  - On the left, `Version 0.1 (a1b2c3d)` and a `GitHub` link to `https://github.com/chris-metz/pacemark`. When the bundle has no commit key ([9.4](#94-bundle-script)), it shows only `Version 0.1`.
  - On the right, a `Quit Pacemark` button with ⌘Q. With the menu bar item hidden in System Settings, this window is the only place left to quit.

---

## 5. Starting and quitting

- **First launch** shows only the menu bar item. No window opens.
- **Never a Dock icon or a ⌘-Tab entry,** not even while the settings window is open. `LSUIElement` is set, and the activation policy stays `.accessory` throughout.
- **Launch at login** is off until the user turns on "Open at Login". Pacemark never adds itself.
- **Opening the settings window** has three ways in:
  - `Settings…` in the dropdown footer
  - ⌘, while the dropdown is open
  - opening Pacemark again while it runs (Spotlight, Finder, `open`). This also works when the item is hidden in System Settings > Menu Bar.

  Opening it closes the dropdown and activates the app. If the window is already open, it comes to the front.
- **Quitting:**
  - `Quit` in the dropdown footer and `Quit Pacemark` in the settings window quit at once without asking. ⌘Q works in both.
  - ⌘-dragging the item out of the menu bar also quits (built-in `MenuBarExtra` behaviour).
- **Nothing to save on quit.** Settings are written on every change; limit values are never stored. Killing the app (as `install.sh` does) is safe.

---

## 6. Logic

All of this lives in `PacemarkKit` and knows no provider. The pace, the refresh schedule and the display are **pure functions**: tests call them with fixed dates, without a clock and without a real `claude`.

### 6.1 Pace and limit display

`limitDisplay(limit, now) -> LimitDisplay`, for every limit of every provider:

- **Window running:** `limit.window != nil` and `window.resetsAt > now`. Otherwise the state is **No window**: a null or missing reset time or utilization, or a reset time already passed.
- **Displayed utilization** `U` = utilization rounded to a whole number (halves away from zero), clamped to 0–100. A server value above 100 shows as `100%`. With no window, `U` is 0.
- **Window start** = reset time − window length (5 h for the session limit, 7 days for the weekly limit and every model limit).
- **Pace** `p` = elapsed share of the window in percent, clamped to 0–100. It rises linearly, day and night, and is computed from `now` at render time, not at fetch time, so the pace marker moves between queries.
- **Deviation** `D` = (utilization clamped to 0–100) − `p`, rounded to a whole number (halves away from zero). **State, text and colour all derive from `D` and `U`**, so "On pace" never sits next to an orange bar.
- **States,** first match wins:
  1. **No window**
  2. **Exhausted:** `U` = 100
  3. **High:** `U` ≥ 90 (the bar is red; the text follows `D` as in 4–6)
  4. **Over pace:** `D` ≥ 1, text `{D}% over pace`
  5. **On pace:** `D` = 0, text `On pace`
  6. **Under pace:** `D` ≤ −1, text `{|D|}% under pace`
- **Output:** the title, the percent text `{U}%`, the fill fraction, the fill colour, the pace marker position (none for no window), the reset line, the pace text and its colour.

### 6.2 Refresh schedule

The app triggers every query; the provider is passive. Each provider has its own state and schedule (v1 has one provider).

**State per provider**

| Field | Meaning |
|---|---|
| `lastAttemptAt` | when the last query **finished**; nil before the first |
| `lastOutcome` | `success`, `unavailable` or `problem(Problem)` of the last query |
| `limits` | the limits from the last success; cleared on `problem` |
| `lastSuccessAt` | when the last success finished |
| `failureStreak` | consecutive `unavailable` outcomes; reset to 0 by `success` and by `problem` |
| `isQuerying` | a query is running |

**Next scheduled query:** `nextQueryAt(state, interval, now) -> Date` is the earliest of:

- `now`, if `lastAttemptAt` is nil (launch).
- `lastAttemptAt` + 1 min if `failureStreak` = 1, + 2 min if it is 2, otherwise + the refresh interval (5, 10 or 15 min).
- For every limit in `limits`, hidden ones included: its `resetsAt` + **65 s**, if that lies after `lastAttemptAt`. The 65 s get past Claude Code's own 60 s snapshot.

If the result is at or before `now`, query now.

**Event triggers**

- **Dropdown opens:** query if `lastAttemptAt` is nil or more than 60 s ago. This applies in every state, so a fixed error disappears as soon as you look. The stored values show at once, and the new ones replace them in place. Detect the opening with `.onAppear` on the dropdown's root view; `MenuBarExtra` rebuilds the view on every open.
- **Wake from sleep** (`NSWorkspace.didWakeNotification`): query as soon as `NWPathMonitor` reports `.satisfied`, at the latest 30 s after wake.
- **Network comes back** (the path turns `.satisfied`) and `lastOutcome` is `unavailable`: query at once.
- **The interval setting changes:** recompute; a new interval counts from `lastAttemptAt`, so if that time has already passed, query now.

**Single flight:** only one query runs per provider. A trigger that fires while one runs is dropped; when it finishes, the next time is recomputed. The app keeps one timer task that sleeps until the next time and is re-armed after every state change.

### 6.3 Display

`display(state, settings, now) -> Display` decides everything the menu bar item and the dropdown show.

- **Stale** = `lastOutcome` is `unavailable`, `limits` exist, and `now − lastSuccessAt` > **2 × the refresh interval** (10, 20 or 30 min). A short hiccup stays invisible; a query that is still running doesn't count as failed. There is no maximum age.
- **Dropdown content,** first match wins:
  1. `lastOutcome` nil → Loading
  2. `problem` → that problem
  3. `limits` exist → all hidden, or the visible limit rows ([6.1](#61-pace-and-limit-display)); plus the stale line if stale
  4. otherwise → no values after a temporary error
- **Menu bar:** the rows of the table in [2](#states) for the menu bar limit, picked as in [2](#2-the-menu-bar-item), plus its accessibility text.
- **Stale line:** `Couldn't update · Last update {age} ago`, where the age is `now − lastSuccessAt`:
  - `{m} min` below 60 min
  - `{h} hr` below 24 h
  - `1 day`, `{d} days` from then on

  Every count is rounded down.

### 6.4 App model

`AppModel` (`@Observable`, main actor) holds the provider, its state, the settings and `now`, and exposes the `Display`.

- **`now`** updates on a tick every full minute (aligned to the minute), when the dropdown opens and after every query. That re-renders everything time-dependent:
  - in the open dropdown: the pace marker, the countdown and the stale line
  - in the menu bar: dimming once values turn stale, and `0%` after the menu bar limit's reset time
- **Recording a result:**
  - `success` sets `limits`, `lastSuccessAt` and the outcome.
  - `unavailable` keeps `limits` and raises `failureStreak`.
  - `problem` clears `limits`.
- **Settings** live in the model and write through to the store ([6.5](#65-settings-storage)) on every change. A change re-renders the menu bar and the dropdown at once.
- **Events in, timers out:** the model takes events as methods (launch, dropdown opened, wake, network satisfied, minute tick, query finished) with an injectable clock. A small driver in the app connects real timers, `NSWorkspace` and `NWPathMonitor`. Tests call the methods directly with a `FakeProvider` and fixed dates.
- **Logging:** `fetch()` runs off the main actor; the model stays on it. Diagnostics go to the unified log (`Logger`, subsystem `xyz.chrismetz.pacemark`, category `app`), never to the UI.

### 6.5 Settings storage

`UserDefaults`, written on every change. The app uses the standard suite; tests use a throwaway `UserDefaults(suiteName:)` per test. Invalid values fall back to the default silently.

| Key | Type | Default | Rule |
|---|---|---|---|
| `refreshIntervalMinutes` | Int | 5 | 5, 10 or 15; anything else reads as 5 |
| `showPercentage` | Bool | true | |
| `hiddenLimits` | [String] | [] | qualified limit ids; only these are remembered, so a new model limit shows |
| `menuBarLimitID` | String | none | qualified limit id; none means the first limit |
| `menuBarLimitTitle` | String | none | the title at the time it was picked, for `(not available)` |

- **Qualified limit id** = `{provider.id}/{limit.id}`, e.g. `claude/session` or `claude/model:Fable`. Ids are never shown, so stored settings survive a change of display strings.
- **Not stored:** "Open at Login" (`SMAppService` is the truth) and limit values.

---

## 7. Provider interface

In `PacemarkKit`. A provider answers each query with exactly one of three results.

```swift
public protocol Provider: Sendable {
    /// Stable id, never shown, e.g. "claude". Prefixes the stored limit ids.
    var id: String { get }
    /// Display name, e.g. "Claude". Unused in v1 (no tab bar).
    var name: String { get }
    /// Runs one query. Never called concurrently for the same provider;
    /// runs off the main actor.
    func fetch() async -> FetchResult
}

public enum FetchResult: Equatable, Sendable {
    case limits([Limit])    // success, in display order; the first is the default menu bar limit
    case unavailable        // temporary error: old values stay, the retry schedule applies
    case problem(Problem)   // persistent error: old values go, the message replaces the bars
}

public struct Limit: Equatable, Sendable, Identifiable {
    public let id: String               // unique within the provider, stable, never shown
    public let title: String            // label above the bar
    public let windowLength: TimeInterval
    public let window: ActiveWindow?    // nil = no window
}

public struct ActiveWindow: Equatable, Sendable {
    public let utilization: Double      // percent as delivered; may exceed 100
    public let resetsAt: Date
}

public struct Problem: Equatable, Sendable {
    public let heading: String
    public let message: String          // Markdown, so commands render as inline code
    public let link: ProblemLink?
}

public struct ProblemLink: Equatable, Sendable {
    public let title: String
    public let url: URL
}
```

- **The provider is passive:** no timer, no schedule of its own, no caching of limit values across calls. Provider-internal state (for Claude: the binary path and the version check) stays inside it.
- **Utilization and reset time** come together or not at all (`window`). The pace logic still treats a reset time in the past as no window, because that depends on `now`.
- **The provider supplies finished text** for problems, so the UI shows messages without knowing where they come from.
- **A new provider** later is a new target `Pacemark<Name>` plus one line in the shell. The tab bar and what the menu bar and settings show for several providers get decided and built together with that provider.

---

## 8. Claude provider

In `PacemarkClaude`, which depends on `PacemarkKit`. `ClaudeProvider` has `id` `claude` and `name` `Claude`. It is assembled from three parts, each tested on its own:

- **Locator:** finds the `claude` binary.
- **`CommandRunner`:** runs a process. The protocol has one method; the real implementation is `ProcessRunner`.
- **Parser:** pure. It reads stream-json, `--version` and `auth status` output.

### 8.1 One query

`fetch()` runs these steps, and the first step that settles the result ends it:

1. **Locate** ([8.2](#82-locating-the-binary)). If nothing is found → `problem` *Claude Code not found*.
2. **Check the version** ([8.3](#83-version-check)), only when the binary changed since the last check:
   - too old → `problem` *Claude Code too old*
   - the check itself fails → `unavailable`
3. **Run `/usage`** ([8.4](#84-the-isolated-invocation)). A timeout or a non-zero exit → `unavailable`.
4. **Parse** ([8.5](#85-parsing-usage_report)):
   - limits → `limits`
   - `rate_limits: null` → `unavailable`
   - schema mismatch → `problem` *Unexpected response*
   - no `usage_report` → step 5
5. **Run `claude auth status`** with the same isolation, parsing its stdout as JSON:
   - `loggedIn: false` → `problem` *Not logged in*
   - `loggedIn: true` → `problem` *Unexpected response*
   - anything else (timeout, unreadable) → `unavailable`

   Rely on the JSON, not the exit code (it is 1 when logged out). This step only runs when `usage_report` is missing.

There is no "token expired" state: Claude Code refreshes the token itself, and if that finally fails, it logs out and step 5 reports it. Pacemark never starts a login.

### 8.2 Locating the binary

1. **Known locations,** in this order, relative to the home directory passed in (tests use a temp dir):
   1. `~/.local/bin/claude`
   2. `/opt/homebrew/bin/claude`
   3. `/usr/local/bin/claude`
   4. `~/.local/share/mise/shims/claude`
   5. `~/.asdf/shims/claude`
   6. `~/.nvm/versions/node/*/bin/claude`, newest Node version first (numeric sort)
   7. `~/.claude/local/claude`

   Only executable files count after resolving symlinks. Dead symlinks, directories and non-executable files are skipped. Which of several `claude` binaries wins doesn't matter: they share one login.
2. **Fallback, the login shell:**
   - Take the shell from the user record (`getpwuid(getuid()).pw_shell`, falling back to `/bin/zsh`), not from `$SHELL`, which GUI apps may lack.
   - Run `<shell> -l -i -c 'command -v claude'` through the `CommandRunner` with a **5 s** timeout. `-i` matters: mise only activates in interactive shells.
   - Parse tolerantly: take the last stdout line that is an absolute path to an executable file.
3. **Remember the found path** in memory. Search again when it's no longer executable. While in *Claude Code not found*, search again on every query (under 0.3 s), so a fresh install is picked up. There is no setting for the path.

### 8.3 Version check

- **Run** `<claude> --version` (same isolation as [8.4](#84-the-isolated-invocation)). The output looks like `2.1.289 (Claude Code)`.
- **Parse** the leading `\d+(\.\d+)*` and compare it component-wise with **2.1.283**, counting missing components as 0.
  - Lower → *too old*, with the found version in the message.
  - Unparseable → log it and carry on, so a changed format never blocks the app.
  - Non-zero exit or timeout → `unavailable`.
- **Cache the result together with the binary's identity:** its symlink-resolved path plus that file's modification date. Run the check again only when the identity changes. `claude update` re-points the native installer's symlink, Homebrew and mise change the target, and npm changes the modification date. Without this, "too old" would stick forever.

### 8.4 The isolated invocation

Fixed by [ADR 0001](adr/0001-claude-limits-via-claude-cli.md):

```
<claude> -p --no-session-persistence --strict-mcp-config --safe-mode --setting-sources "" \
  --output-format stream-json --verbose "/usage" < /dev/null
```

As an argument array: `["-p", "--no-session-persistence", "--strict-mcp-config", "--safe-mode", "--setting-sources", "", "--output-format", "stream-json", "--verbose", "/usage"]`.

- **Environment,** exactly this:
  - `HOME`
  - `USER`
  - `PATH=/usr/bin:/bin:/usr/sbin:/sbin`
  - `DISABLE_AUTOUPDATER=1`
  - `DISABLE_TELEMETRY=1`

  **Never** set `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`: it silently turns `rate_limits` into `null`. The npm package runs the same native binary without Node, so the minimal `PATH` works for every install method.
- **Working directory:** `~/Library/Caches/xyz.chrismetz.pacemark/claude-cwd`, created empty if missing. It is the same folder every time, so Claude Code only ever sees one folder.
- **stdin:** `/dev/null`. Without it, `claude` waits 3 s for input.
- **Timeout:** **30 s** (a normal run takes 1.4–2.2 s). Then SIGTERM, and SIGKILL 2 s later.
- **Shared:** `--version` and `auth status` use the same environment, working directory, stdin and timeout.
- **Runs off the main actor** (a `@concurrent` function).
- **`ProcessRunner`** uses Foundation's `Process`. It reads stdout and stderr concurrently while the process runs, so a full pipe buffer can't deadlock it. The result is the exit status, stdout and stderr, or "timed out".

### 8.5 Parsing `usage_report`

- **Stream:** split stdout into lines and parse each non-empty line as JSON; skip lines that don't parse. Take the first object with `"type": "assistant"` that has a non-null `usage_report`. If there is none, the report is missing.
- **`usage_report.rate_limits`:** `null` → `unavailable`. Otherwise it must be an object with an array `limits`.
- **Rows:** each row is an object.
  - Use `kind`, `percent`, `resets_at` and `scope.model.display_name`.
  - Ignore `group`, `severity` and `is_active`. `is_active` does not say whether a window runs.

  | Row | Limit `id` | `title` | Window length |
  |---|---|---|---|
  | `kind: "session"` | `session` | `Session limit` | 5 h |
  | `kind: "weekly_all"` | `weekly` | `Weekly limit` | 7 days |
  | `kind: "weekly_scoped"` with a non-null `scope.model` | `model:<display_name>` | `<display_name> limit`, e.g. `Fable limit` | 7 days |

  - **Ignored, not an error:** rows with any other `kind`, and `weekly_scoped` rows whose scope isn't a model (e.g. `surface`).
- **Window:** `percent` (any JSON number) and `resets_at` (an ISO 8601 string) both present and non-null → `ActiveWindow`; otherwise `nil`. A session row with `percent: 0` and `resets_at: null` is no window, not an active window at 0%.
- **Dates:** parse with `Date.ISO8601FormatStyle(includingFractionalSeconds: true)`. It reads both `2026-10-03T11:09:59.823825+00:00` and `2026-10-07T01:00:00+00:00` (verified).
- **Order:** always the session limit first, then the weekly limit, then the model limits in server order, whatever the server's row order.
  - Without a `session` row, Claude still delivers a session limit with `window: nil`, so the menu bar default stays stable.
  - A duplicate row (second session, second weekly, or a repeated model name) is ignored and logged.
- **Unexpected response** (schema mismatch) when any of these holds:
  - `usage_report` or `rate_limits` is neither null nor an object
  - `limits` is missing or not an array, or a row isn't an object
  - a recognised row has `percent` that is neither a number nor null, `resets_at` that is neither null nor a parseable date, or a model scope without a non-empty string `display_name`
  - there is no recognised row at all (a renamed `kind` must not look like "no window")

### 8.6 Logging

`Logger` with subsystem `xyz.chrismetz.pacemark` and category `claude`. Log:

- the found path and how it was found
- the version and the check's outcome
- each invocation's exit status, duration and stderr (truncated to 2 KB)
- which schema rule failed
- ignored rows

Never show any of it in the UI.

---

## 9. Package, bundle and scripts

### 9.1 Layout

```
Package.swift
Sources/
  Pacemark/            shell: the App, the MenuBarExtra and Window scenes, the app delegate
  PacemarkKit/         provider interface and types, pace, schedule, display, settings,
                       app model, dropdown and settings views, menu bar label image
  PacemarkClaude/      ClaudeProvider, locator, CommandRunner/ProcessRunner, parser
Tests/
  PacemarkKitTests/    pace, schedule, display, settings store, app model, snapshots
    __Snapshots__/     reference PNGs
  PacemarkClaudeTests/ parser, version and auth parsing, runner, locator, provider flow
    Fixtures/          moved from docs/fixtures/claude (resources)
Resources/
  AppIcon.icon/        Icon Composer icon
scripts/
  bundle.sh
  install.sh
.gitignore             .build/, build/
```

| Target | Kind | Depends on |
|---|---|---|
| `Pacemark` | executable | `PacemarkKit`, `PacemarkClaude` |
| `PacemarkKit` | library | – |
| `PacemarkClaude` | library | `PacemarkKit` |
| `PacemarkKitTests` | tests | `PacemarkKit` |
| `PacemarkClaudeTests` | tests | `PacemarkClaude` |

`PacemarkKit` can't import `PacemarkClaude`, so the compiler keeps Claude internals out of the UI and the pace logic. `CommandRunner` stays in `PacemarkClaude` until a second CLI-based provider needs it.

### 9.2 `Package.swift`

- `// swift-tools-version: 6.2` or later. `platforms: [.macOS("27.0")]`.
- **Every target:** Swift 6 language mode with full data-race checking, plus `.defaultIsolation(MainActor.self)`. Only the work that must run in the background opts out, chiefly the `claude` call.
- **No third-party dependencies,** not even in tests. Use Swift Testing (`import Testing`).
- `PacemarkClaudeTests` declares `resources: [.copy("Fixtures")]`.

### 9.3 The shell

The executable target contains only:

- **The `App`:**
  - an `@NSApplicationDelegateAdaptor`
  - the `AppModel` with `ClaudeProvider()`, the one place that names a provider
  - a `MenuBarExtra` (`.window` style) whose label is `Image(nsImage:)` from the display
  - a `Window("Pacemark Settings", id: "settings")` with `.defaultLaunchBehavior(.suppressed)`
- **The app delegate:**
  - It handles `applicationShouldHandleReopen` by opening the settings window. A menu-bar-only app otherwise ignores the reopen event.
  - If the `Window` scene can't be opened reliably from there (it needs `openWindow` from a live SwiftUI view), or doesn't come to the front, use the fallback from ADR 0002: an AppKit `NSWindow` hosting the same settings view, owned by the delegate.

### 9.4 Bundle script

`scripts/bundle.sh` turns the SwiftPM build into `build/Pacemark.app`:

1. `swift build -c release --product Pacemark`.
2. Copy the binary to `Contents/MacOS/Pacemark`.
3. **Compile the icon:**
   ```
   xcrun actool Resources/AppIcon.icon --compile build/Pacemark.app/Contents/Resources \
     --app-icon AppIcon --platform macosx --target-device mac \
     --minimum-deployment-target 27.0 --output-partial-info-plist build/partial.plist
   ```
   This produces `Assets.car` plus a fallback `AppIcon.icns`.
4. **Write `Contents/Info.plist`,** then merge `build/partial.plist` into it:

   | Key | Value |
   |---|---|
   | `CFBundleIdentifier` | `xyz.chrismetz.pacemark` (effectively permanent: launch at login is tied to it) |
   | `CFBundleName`, `CFBundleDisplayName` | `Pacemark` |
   | `CFBundleExecutable` | `Pacemark` |
   | `CFBundlePackageType` | `APPL` |
   | `CFBundleShortVersionString` | `0.1` |
   | `CFBundleVersion` | `git rev-list --count HEAD`; `1` outside a Git checkout |
   | `PacemarkGitCommit` | `git rev-parse --short HEAD`, plus `-dirty` when `git status --porcelain` isn't empty; omitted outside a Git checkout |
   | `LSMinimumSystemVersion` | `27.0` |
   | `LSUIElement` | `true` |
   | `CFBundleDevelopmentRegion` | `en` |
   | `CFBundleIconName`, `CFBundleIconFile` | `AppIcon` (from the partial plist) |

5. **Sign:**
   - Use the first `Apple Development` identity from `security find-identity -v -p codesigning`, with `codesign --force --sign <identity>`. Without one, sign ad-hoc (`--sign -`).
   - There is no hardened runtime and no notarization: a locally built app isn't quarantined. The first signing may show a keychain dialog; the human clicks "Always Allow" once.
   - Finish with `codesign --verify --strict`.

### 9.5 Install script

`./scripts/install.sh` is the one command the human runs, or asks an agent to run:

1. Run `scripts/bundle.sh`.
2. Quit a running Pacemark (`pkill -x Pacemark`) and wait until it's gone.
3. Replace `/Applications/Pacemark.app` with the new build. It always goes to `/Applications`, because the login item remembers the location.
4. Launch it with `open`.

It doesn't run the tests: keeping `main` green is the agents' job during development.

### 9.6 App icon

- **Motif:** the gauge motif in white on a solid indigo fill (`#4351C7`), without a colourful gradient. The gauge is **original art** with its own proportions, not a trace of the SF Symbol: the SF Symbols licence forbids system images, or anything confusingly similar, in app icons.
- **Format:** `Resources/AppIcon.icon/` is an Icon Composer folder: `icon.json` plus one white SVG layer. Take the key names from Xcode's template, since the schema is undocumented. The format gets the dark, clear and tinted variants for free.
- **Check:** export a PNG with `ictool` (inside Icon Composer.app) and look at it.

### 9.7 README

Add a short "Build from source" section:

- Requirements: macOS 27, Xcode 27, and Claude Code 2.1.283 or later, installed and logged in.
- The command: `./scripts/install.sh`.

---

## 10. Verification

Agents verify their own work with `swift test`. No test ever launches the real `claude` and nothing checks the live endpoint ([ADR 0001](adr/0001-claude-limits-via-claude-cli.md)). Fixed inputs throughout: time zone `Europe/Berlin`, locale `en_DE` (plus `en_US` where formatting is tested), a fixed `now`, and a fixed version string.

### 10.1 Unit tests

- **Pace** ([6.1](#61-pace-and-limit-display)):
  - every state
  - boundaries: deviation +0.5 → `1% over pace`, −0.5 → `1% under pace`, 0.49 → `On pace`; utilization 89.5 → High, 99.5 → Exhausted, 140 → `100%`
  - reset time just passed → No window
  - window start at 0% and at 100% elapsed
- **Reset line:**
  - countdown boundaries, with `now` on a full minute: 30 s → `1 min`, 59 min 30 s → `1 hr`, 23 h 59 min, exactly 24 h → weekday
  - a reset time a few seconds ahead that rounds to before `now` → `1 min`
  - rounding `00:59:59.88` → `03:00` Berlin time
  - `en_DE` and `en_US`
- **Stale line:** min, hr and day forms.
- **Refresh schedule** ([6.2](#62-refresh-schedule)):
  - launch
  - each interval (5, 10, 15)
  - the retry stages after 1, 2 and 3 failures
  - +65 s after a reset (hidden limits included; ignored once that time lies before the last attempt)
  - the open trigger at 59 s and 61 s
  - an interval change whose new time has already passed
- **Display** ([6.3](#63-display)):
  - every dropdown content and every menu bar row in both percentage modes
  - stale at each interval (just below and above 2×)
  - a problem clears values, followed by `unavailable` (→ no values)
  - the menu bar limit picked, missing (→ first limit) and hidden in the dropdown
  - all limits hidden
  - accessibility texts
- **Settings store:** round trip and every fallback.
- **App model** with a `FakeProvider` of scripted results:
  - the outcome bookkeeping of [6.4](#64-app-model)
  - single flight
  - settings written through
- **Claude parser,** with every fixture ([10.3](#103-fixtures)) and these hand-edited variants:
  - no `session` row
  - `percent: null`
  - a `resets_at` without fractional seconds
  - `rate_limits: null`
  - an unknown `kind`
  - a `surface` scope
  - two model limits
  - a repeated model name
  - `percent` above 100
  - a known row with a wrong type
  - no recognised row
  - malformed JSON lines
- **`--version` and `auth status` parsing:** the fixtures, plus an unparseable version and versions just below, at and above 2.1.283.
- **`ProcessRunner`,** only with system binaries:
  - `/bin/echo`
  - `/bin/sh -c 'exit 3'`
  - large output (no deadlock)
  - `/bin/sleep` with a short timeout, for the SIGTERM → SIGKILL path
- **Locator:** a temp home with fake executables, a symlink, a dead symlink, a non-executable file and several nvm versions. The login-shell fallback runs through a fake runner, including banner lines before the path.
- **Provider flow,** with a fake runner that answers by arguments with fixture output:
  - each step of [8.1](#81-one-query)
  - the version re-check on an identity change
  - **the exact invocation:** flags, environment, working directory, stdin and timeout

### 10.2 Snapshot tests

- **Rendering:**
  - Views go through `NSHostingView` at a fixed size, under the `.aqua` and `.darkAqua` appearances, onto an explicit opaque background (the window background colour), at 2× scale.
  - The menu bar label image is drawn under `.vibrantLight` and `.vibrantDark` onto a light and a dark menu-bar-like background.
- **References:**
  - They live as PNGs in `Tests/PacemarkKitTests/__Snapshots__/`, named `<test>-<variant>.png`, and are read via `#filePath`, not as resources.
  - Pixels may differ by at most 3/255 per channel.
  - On a mismatch, write the actual image and a diff to `.build/snapshot-failures/` and fail.
  - A missing reference is written and the test fails ("new reference recorded, inspect it"). `PACEMARK_RECORD_SNAPSHOTS=1` re-records all of them.
  - **The agent looks at every new or changed reference image before committing it.**
- **Cases,** each in light and dark:
  - **Dropdown:**
    - three limits over, on and under pace
    - High and Exhausted
    - a session limit with no window
    - stale
    - Loading
    - no values after a temporary error
    - each of the four problems
    - all limits hidden
    - some limits hidden
  - **Menu bar label, percentage on:** normal, `0%`, red, dimmed, red and dimmed, `⚠︎`, glyph only.
  - **Menu bar label, percentage off:** plain, red, dimmed, red and dimmed, `⚠︎`.
  - **Settings window:**
    - default with values
    - before the first success
    - a `(not available)` choice
    - the Open at Login note for `.requiresApproval`
    - a copy outside `/Applications` (switch disabled)

### 10.3 Fixtures

Real output, redacted. They live in [`docs/fixtures/claude/`](fixtures/claude/) until the test target exists. Then move them to `Tests/PacemarkClaudeTests/Fixtures/` (SwiftPM resources must live inside the target), fix the links here, and add the hand-edited variants there as `variant-<what>.stream.jsonl`.

| File | What it is |
|---|---|
| [`usage.stream.jsonl`](fixtures/claude/usage.stream.jsonl) | `/usage` with a session window running: session 14%, weekly 36%, Fable 0%. Assistant and result lines. Claude Code 2.1.288, 3 Oct 2026. |
| [`usage-no-session-window.stream.jsonl`](fixtures/claude/usage-no-session-window.stream.jsonl) | No session window: the `session` row has `percent: 0` and `resets_at: null`. Only `limits[]` and the text are real; the envelope comes from the 3 Oct capture. 4 Oct 2026. |
| [`usage-logged-out.stream.jsonl`](fixtures/claude/usage-logged-out.stream.jsonl) | Not logged in: exit 0, no `usage_report`, a cost summary as text. System init, assistant and result lines. Claude Code 2.1.289, captured with a throwaway config directory. |
| [`version.txt`](fixtures/claude/version.txt) | `claude --version` |
| [`auth-status-logged-in.json`](fixtures/claude/auth-status-logged-in.json) | `claude auth status`, logged in (exit 0) |
| [`auth-status-logged-out.json`](fixtures/claude/auth-status-logged-out.json) | `claude auth status`, logged out (exit 1) |

Facts the parser relies on:

- Reset times jitter by fractions of a second between queries and sit on either side of the full minute.
- `utilization` in the OAuth response's flat fields is a float. `usage_report` doesn't have those fields, and its `percent` is an integer.

The full write-ups are on the branch `task/echte-usage-antwort`.

### 10.4 The human's checklist

Agents can't verify the real menu bar headless. Whenever an agent changes the menu bar item, how the dropdown opens, or the settings window, it hands the human the relevant items of this checklist after running `./scripts/install.sh`:

- [ ] A click on the item opens the dropdown right under it; a click elsewhere closes it.
- [ ] Reopening the dropdown after a minute brings fresh values within about 2 s.
- [ ] In a light and in a dark menu bar (switch the wallpaper), the glyph, the percentage, red and dimmed all read well, also with the percentage off.
- [ ] `Settings…`, ⌘, in the dropdown, and opening Pacemark again (Spotlight or Finder) each bring the settings window to the front. There's never a Dock icon or a ⌘-Tab entry.
- [ ] With the item hidden in System Settings > Menu Bar, opening Pacemark again shows the settings, and `Quit Pacemark` quits.
- [ ] ⌘Q quits from the dropdown and from the settings window.
- [ ] A change in the settings shows at once in the menu bar.
- [ ] Open at Login: turned on, Pacemark runs after logging out and in, and it is still on after another `./scripts/install.sh`.

---

## 11. Build order

Each step fits one agent session and ends with a green `swift test` and a commit.

1. **Skeleton and pace:**
   - `Package.swift`, the three targets, `.gitignore`
   - the provider types ([7](#7-provider-interface))
   - the pace and limit display ([6.1](#61-pace-and-limit-display)) with the reset line, plus their tests
2. **Claude parser:** move the fixtures, the parser ([8.5](#85-parsing-usage_report)), `--version` and `auth status` parsing, and the variants.
3. **Running Claude:** `CommandRunner` and `ProcessRunner`, the locator, the version check, and `ClaudeProvider`'s flow with the fake runner ([8.1](#81-one-query)–[8.4](#84-the-isolated-invocation)).
4. **Schedule, display and settings:** [6.2](#62-refresh-schedule), [6.3](#63-display) and [6.5](#65-settings-storage) as pure functions and the store.
5. **App model and menu bar label:** [6.4](#64-app-model) with a `FakeProvider`, the label image ([2](#drawing)) and its snapshots.
6. **Dropdown:** the view ([3](#3-the-dropdown)) and its snapshots.
7. **Settings window:** the view ([4](#4-the-settings-window)) without Open at Login, and its snapshots.
8. **Shell and bundle:**
   - the shell ([9.3](#93-the-shell)) with the driver for timers, wake and network
   - `bundle.sh` and `install.sh`
   - the app icon and the README
   - first `./scripts/install.sh`, then the checklist ([10.4](#104-the-humans-checklist))
9. **Open at Login:** `SMAppService` ([4](#4-the-settings-window)). Check on the real Mac that the login item survives a rebuild by `install.sh`. If it doesn't, report it rather than work around it.

---

## 12. Changes made while writing this spec

Confirmed by the human in [Write up the v1 spec](https://github.com/chris-metz/pacemark/issues/10).

**Changes to earlier decisions**

- **No tab bar in v1.** Changes [How does a provider deliver its limits to the UI?](https://github.com/chris-metz/pacemark/issues/13), which had it appear by itself from two providers on. The tab bar, the menu bar with several providers, and the settings for several providers are built together with the second provider. The provider interface, the per-provider refresh state and the provider-qualified setting ids stay, so that step remains small.
- **`CFBundleVersion` is the commit count;** the Git hash goes to `PacemarkGitCommit`. Changes [How do the settings behave?](https://github.com/chris-metz/pacemark/issues/18): macOS expects digits and dots in `CFBundleVersion`. The window still shows `Version 0.1 (a1b2c3d)`.
- **The "Can't read your limits" link** is `Open on GitHub` to the repo page, not "Check for updates" to the releases page. Changes [When does the app refresh, and what does it show on errors?](https://github.com/chris-metz/pacemark/issues/9): v1 has no releases ([How does a release reach users?](https://github.com/chris-metz/pacemark/issues/15)).

**Settled here**

- **Limit titles:** `Session limit`, `Weekly limit`, `<Model> limit`.
- **Reset line:** `Resets in 1 hr 52 min` and `Resets Wed 03:00`. The reset time is rounded to the full minute and the countdown rounds up. Times follow the user's region and 12/24-hour setting, with English weekday names.
- **Thresholds use the displayed, rounded percentage:** red at `90%`, `Limit reached` at `100%`.
- **A persistent error clears stored values,** so a later temporary error shows "Can't load your limits right now", not old bars.
- **Parsing:** a fixed limit order, "Unexpected response" only for real schema breaks, and an unreadable `--version` never blocks.
- **The login shell** comes from the user record; it has a 5 s timeout.
- **`claude` runs in a fixed empty folder** in the app's caches.
- **New strings:** the stale line moves to its own row (with `hr` and `day` forms); the install link points to `https://code.claude.com/docs/en/setup`; there are two Open at Login notes and the menu bar accessibility texts.
- **Fixtures** are on `main` in English, plus four new ones (`--version`, `auth status` logged in and out, `/usage` logged out).
- **Small fills:** `Limit reached` is red; a limit with no window shows `0%` at the top right; the settings window is 440 pt wide.

---

## 13. Sources

Every ticket of [Map: v1 spec for the menu bar app for Claude limits](https://github.com/chris-metz/pacemark/issues/1). Each holds the reasoning and the rejected options behind its part of this spec.

| Ticket | Where it shows up here |
|---|---|
| [Where can the app get the Claude limits?](https://github.com/chris-metz/pacemark/issues/2) | background for [8](#8-claude-provider) |
| [What tech stack options exist for a menu bar app?](https://github.com/chris-metz/pacemark/issues/3) | background for [9](#9-package-bundle-and-scripts) |
| [What do the dropdown and the menu bar item look like?](https://github.com/chris-metz/pacemark/issues/4) | [2](#2-the-menu-bar-item), [3](#3-the-dropdown) |
| [Capture a real usage response from our own Claude account](https://github.com/chris-metz/pacemark/issues/5) | [10.3](#103-fixtures) |
| [Which data source does v1 use for the Claude limits?](https://github.com/chris-metz/pacemark/issues/6) | [8](#8-claude-provider), ADR 0001 |
| [Which tech stack does v1 use?](https://github.com/chris-metz/pacemark/issues/7) | [9](#9-package-bundle-and-scripts), ADR 0002 |
| [Which language does the app use for its text?](https://github.com/chris-metz/pacemark/issues/16) | English throughout |
| [How exactly is the pace calculated?](https://github.com/chris-metz/pacemark/issues/8) | [6.1](#61-pace-and-limit-display), [3](#limit-states) |
| [When does the app refresh, and what does it show on errors?](https://github.com/chris-metz/pacemark/issues/9) | [6.2](#62-refresh-schedule), [6.3](#63-display), [3](#other-contents) |
| [What is the app called, and what does its icon look like?](https://github.com/chris-metz/pacemark/issues/11) | [2](#drawing), [9.6](#96-app-icon) |
| [Can the menu bar item show a red or dimmed percentage?](https://github.com/chris-metz/pacemark/issues/17) | [2](#drawing) |
| [How does a provider deliver its limits to the UI?](https://github.com/chris-metz/pacemark/issues/13) | [7](#7-provider-interface), [8](#8-claude-provider), [9.1](#91-layout) |
| [How does a release reach users?](https://github.com/chris-metz/pacemark/issues/15) | [9.4](#94-bundle-script), [9.5](#95-install-script), [10.4](#104-the-humans-checklist) |
| [Capture the response when no session window is active](https://github.com/chris-metz/pacemark/issues/12) | [8.5](#85-parsing-usage_report), [10.3](#103-fixtures) |
| [How do you start and quit the app?](https://github.com/chris-metz/pacemark/issues/14) | [4](#4-the-settings-window), [5](#5-starting-and-quitting) |
| [How do the settings behave?](https://github.com/chris-metz/pacemark/issues/18) | [4](#4-the-settings-window), [6.5](#65-settings-storage) |
| [Write up the v1 spec](https://github.com/chris-metz/pacemark/issues/10) | [12](#12-changes-made-while-writing-this-spec) |

---

## Appendix: all strings

Use these verbatim. `{…}` marks a value. Percentages have no space before `%`: build them as `"\(n)%"`, not with a locale percent formatter (which would print `71 %` in some regions).

### Menu bar

| Where | String |
|---|---|
| Percentage | `{U}%` |
| Persistent error | SF Symbol `exclamationmark.triangle` (no text) |

### Menu bar accessibility text

| Situation | Text |
|---|---|
| Loading, or no values | `Pacemark` |
| Persistent error | `Pacemark: {problem heading}` |
| Values | `{menu bar limit title} {U}%`, e.g. `Session limit 71%` |
| Stale values | `{menu bar limit title} {U}%, not up to date` |

The accessibility text always names the menu bar limit and its percentage, even with the percentage hidden.

### Dropdown

| Where | String |
|---|---|
| Limit titles | `Session limit`, `Weekly limit`, `{display_name} limit` |
| Utilization | `{U}%` |
| No window, line 2 left | `Starts with your next message` |
| Countdown below 1 h | `Resets in {m} min` |
| Countdown from 1 h | `Resets in {h} hr {m} min`, or `Resets in {h} hr` when `{m}` is 0 |
| 24 h or more | `Resets {weekday} {time}`, e.g. `Resets Wed 03:00` |
| Exhausted | `Limit reached` |
| Over pace | `{D}% over pace` |
| On pace | `On pace` |
| Under pace | `{D}% under pace` |
| Loading | `Loading…` |
| No values, heading | `Can't load your limits right now` |
| No values, text | `Trying again shortly.` |
| All hidden | `All limits are hidden.` |
| Stale line | `Couldn't update · Last update {age} ago` with `{m} min`, `{h} hr`, `1 day`, `{d} days` |
| Footer | `Settings…` (⌘,), `Quit` (⌘Q) |
| Row accessibility | `{title}, {U}%, {pace text}, {reset line with a lower-case first letter}`, e.g. `Session limit, 71%, 12% over pace, resets in 1 hr 52 min` |

### Problems (supplied by the Claude provider)

| State | Heading | Message (Markdown) | Link |
|---|---|---|---|
| Claude Code not found | `Claude Code not found` | `Pacemark reads your limits through Claude Code. Install it and log in.` | `Install Claude Code` → `https://code.claude.com/docs/en/setup` |
| Claude Code too old | `Claude Code is too old` | ``Pacemark needs version 2.1.283 or later (found {version}). Run `claude update` in Terminal.`` | none |
| Not logged in | `Claude Code is not logged in` | ``Run `claude` in Terminal and log in.`` | none |
| Unexpected response | `Can't read your limits` | `Claude changed how it reports limits. A newer version of Pacemark should fix this.` | `Open on GitHub` → `https://github.com/chris-metz/pacemark` |

### Settings window

| Where | String |
|---|---|
| Window title | `Pacemark Settings` |
| Groups | `General`, `Menu Bar`, `Dropdown` |
| Rows | `Open at Login`, `Refresh every`, `Limit`, `Show percentage`, one per limit with its title |
| Interval choices | `5 min`, `10 min`, `15 min` |
| Missing menu bar limit | `{stored title} (not available)` |
| Limit picker without values or a stored choice | `—` |
| No limits yet | `Your limits appear here once Pacemark has loaded them.` |
| Login item turned off in System Settings | `Turned off in System Settings.` and the link button `Open Login Items Settings` |
| Copy outside `/Applications` | `Move Pacemark to Applications to use this.` |
| Version | `Version {CFBundleShortVersionString} ({PacemarkGitCommit})`, or `Version {CFBundleShortVersionString}` without the commit key |
| Repo link | `GitHub` → `https://github.com/chris-metz/pacemark` |
| Quit | `Quit Pacemark` (⌘Q) |
