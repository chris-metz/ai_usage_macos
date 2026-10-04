import AppKit
import PacemarkKit
import Testing

/// The menu bar label image (§2 Drawing), drawn the way a light and a dark
/// menu bar would.
@Suite struct MenuBarLabelTests {
    @Test func labelPercentage() {
        let display = MenuBarDisplay(content: .percentage("14%", isRed: false, isDimmed: false), accessibilityText: "Session limit 14%")

        expectLabelSnapshot(menuBarImage(display))
    }

    @Test func label0Percent() {
        let display = MenuBarDisplay(content: .percentage("0%", isRed: false, isDimmed: false), accessibilityText: "Session limit 0%")

        expectLabelSnapshot(menuBarImage(display))
    }

    @Test func labelRed() {
        let display = MenuBarDisplay(content: .percentage("91%", isRed: true, isDimmed: false), accessibilityText: "Session limit 91%")

        expectLabelSnapshot(menuBarImage(display))
    }

    @Test func labelDimmed() {
        let display = MenuBarDisplay(
            content: .percentage("71%", isRed: false, isDimmed: true),
            accessibilityText: "Session limit 71%, not up to date"
        )

        expectLabelSnapshot(menuBarImage(display))
    }

    @Test func labelRedAndDimmed() {
        let display = MenuBarDisplay(
            content: .percentage("91%", isRed: true, isDimmed: true),
            accessibilityText: "Session limit 91%, not up to date"
        )

        expectLabelSnapshot(menuBarImage(display))
    }

    @Test func labelWarning() {
        let display = MenuBarDisplay(content: .warning, accessibilityText: "Pacemark: Claude Code is not logged in")

        expectLabelSnapshot(menuBarImage(display))
    }

    @Test func labelGlyphOnly() {
        let display = MenuBarDisplay(content: .glyph(), accessibilityText: "Pacemark")

        expectLabelSnapshot(menuBarImage(display))
    }

    // With the percentage off, from the display of a state: the glyph
    // carries red and dimming, and ⚠︎ stays.

    @Test func labelPercentageOffPlain() {
        expectLabelSnapshot(percentageOff(succeeded(at71, at: now)))
    }

    @Test func labelPercentageOffRed() {
        expectLabelSnapshot(percentageOff(succeeded(at91, at: now)))
    }

    @Test func labelPercentageOffDimmed() {
        expectLabelSnapshot(percentageOff(failed(after: at71, age: 23 * 60)))
    }

    @Test func labelPercentageOffRedAndDimmed() {
        expectLabelSnapshot(percentageOff(failed(after: at91, age: 23 * 60)))
    }

    @Test func labelPercentageOffWarning() {
        expectLabelSnapshot(percentageOff(ProviderState(lastAttemptAt: now, lastOutcome: .problem(notLoggedIn))))
    }

    @Test func withThePercentageOffTheImageStillCarriesTheLimitAndItsPercentage() {
        #expect(percentageOff(succeeded(at71, at: now)).accessibilityDescription == "Session limit 71%")
    }

    @Test func imageCarriesTheAccessibilityText() {
        let display = MenuBarDisplay(content: .percentage("14%", isRed: false, isDimmed: false), accessibilityText: "Session limit 14%")

        #expect(menuBarImage(display).accessibilityDescription == "Session limit 14%")
    }
}

private let at71 = [session(utilization: 71, resetsAt: "2026-10-04T12:00:00Z")]
private let at91 = [session(utilization: 91, resetsAt: "2026-10-04T12:00:00Z")]

/// The label image for `state` at `now` with the percentage off.
private func percentageOff(_ state: ProviderState) -> NSImage {
    menuBarImage(display(state, providerID: "claude", settings: Settings(showPercentage: false), now: now).menuBar)
}
