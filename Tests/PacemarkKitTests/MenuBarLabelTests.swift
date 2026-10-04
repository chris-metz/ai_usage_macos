import AppKit
import PacemarkKit
import Testing

/// The menu bar label image (§2 Drawing), drawn the way a light and a dark
/// menu bar would.
@Suite struct MenuBarLabelTests {
    @Test func labelPercentage() {
        let display = MenuBarDisplay(content: .percentage("14%", isRed: false), accessibilityText: "Session limit 14%")

        expectLabelSnapshot(menuBarImage(display))
    }

    @Test func labelGlyphOnly() {
        let display = MenuBarDisplay(content: .glyph, accessibilityText: "Pacemark")

        expectLabelSnapshot(menuBarImage(display))
    }

    @Test func imageCarriesTheAccessibilityText() {
        let display = MenuBarDisplay(content: .percentage("14%", isRed: false), accessibilityText: "Session limit 14%")

        #expect(menuBarImage(display).accessibilityDescription == "Session limit 14%")
    }
}
