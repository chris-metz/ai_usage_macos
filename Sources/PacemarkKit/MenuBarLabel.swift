import AppKit
import SwiftUI

/// The `MenuBarExtra` label: one drawn image, since SwiftUI drops colour,
/// opacity and accessibility modifiers on the label.
public struct MenuBarLabel: View {
    let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Image(nsImage: menuBarImage(model.display.menuBar))
    }
}

/// What the menu bar item shows (§2 States).
public nonisolated struct MenuBarDisplay: Equatable, Sendable {
    /// What the item shows.
    public var content: Content
    /// What VoiceOver reads for the item.
    public var accessibilityText: String

    public init(content: Content, accessibilityText: String) {
        self.content = content
        self.accessibilityText = accessibilityText
    }

    public enum Content: Equatable, Sendable {
        /// The glyph alone.
        case glyph
        /// The glyph and the menu bar limit's displayed utilization, e.g.
        /// `14%`, in red from 90%.
        case percentage(String, isRed: Bool)
        /// The glyph and `⚠︎`: a persistent error.
        case warning
    }

    /// The text right of the glyph, if any.
    var percentText: String? {
        switch content {
        case .glyph, .warning: nil
        case .percentage(let text, _): text
        }
    }
}

/// The menu bar item as one non-template image: the gauge glyph, then the
/// percentage 4 pt to its right (§2 Drawing).
///
/// Colours resolve inside the drawing handler, from the appearance the image
/// is drawn in, so the menu bar's own appearance decides them. Nonisolated
/// because AppKit may run the handler on any thread.
public nonisolated func menuBarImage(_ display: MenuBarDisplay) -> NSImage {
    let glyph = NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: nil)!
    let glyphSize = glyph.size
    let font = NSFont.menuBarFont(ofSize: 0)
    let textSize = display.percentText.map { ($0 as NSString).size(withAttributes: [.font: font]) } ?? .zero
    let gap: CGFloat = display.percentText == nil ? 0 : 4
    let size = NSSize(
        width: ceil(glyphSize.width + gap + textSize.width),
        height: ceil(max(glyphSize.height, textSize.height))
    )

    let image = NSImage(size: size, flipped: false) { rect in
        let foreground = foregroundColor()
        glyph.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [foreground]))!.draw(
            in: NSRect(
                x: 0,
                y: (rect.height - glyphSize.height) / 2,
                width: glyphSize.width,
                height: glyphSize.height
            )
        )
        if let text = display.percentText {
            (text as NSString).draw(
                at: NSPoint(x: glyphSize.width + gap, y: (rect.height - textSize.height) / 2),
                withAttributes: [.font: font, .foregroundColor: foreground]
            )
        }
        return true
    }
    image.isTemplate = false
    image.accessibilityDescription = display.accessibilityText
    return image
}

/// Pure white on a dark menu bar, pure black on a light one. Semantic
/// colours like `labelColor` render grey on the vibrant menu bar.
private nonisolated func foregroundColor() -> NSColor {
    let match = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
    return match == .darkAqua || match == .vibrantDark ? .white : .black
}
