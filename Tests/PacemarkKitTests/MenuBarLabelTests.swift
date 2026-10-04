import AppKit
import PacemarkKit
import Testing

/// The menu bar label image (§2 Drawing), drawn the way a light and a dark
/// menu bar would.
@Suite struct MenuBarLabelTests {
    @Test func labelPercentage() {
        let display = MenuBarDisplay(percentText: "14%", accessibilityText: "Session limit 14%")

        expectLabelSnapshot(menuBarImage(display))
    }
}
