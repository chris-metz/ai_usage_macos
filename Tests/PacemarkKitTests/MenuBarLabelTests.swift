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
        let display = MenuBarDisplay(content: .glyph, accessibilityText: "Pacemark")

        expectLabelSnapshot(menuBarImage(display))
    }

    @Test func imageCarriesTheAccessibilityText() {
        let display = MenuBarDisplay(content: .percentage("14%", isRed: false, isDimmed: false), accessibilityText: "Session limit 14%")

        #expect(menuBarImage(display).accessibilityDescription == "Session limit 14%")
    }
}
