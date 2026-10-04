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
        /// The glyph alone: before any values, or with the percentage off.
        /// With the percentage off, the glyph turns red from 90% and dims
        /// while the values are stale.
        case glyph(isRed: Bool = false, isDimmed: Bool = false)
        /// The glyph and the menu bar limit's displayed utilization, e.g.
        /// `14%`, in red from 90% and dimmed while the values are stale.
        case percentage(String, isRed: Bool, isDimmed: Bool)
        /// The glyph and `⚠︎`: a persistent error.
        case warning
    }
}

/// The menu bar item as one non-template image: the gauge glyph and, 4 pt to
/// its right, the percentage or the warning triangle (§2 Drawing).
///
/// Colours resolve inside the drawing handler, from the appearance the image
/// is drawn in, so the menu bar's own appearance decides them. Only the
/// element that carries the value turns red or dims: the percentage, or the
/// glyph with the percentage off. The triangle keeps the foreground colour.
/// Nonisolated because AppKit may run the handler on any thread.
public nonisolated func menuBarImage(_ display: MenuBarDisplay) -> NSImage {
    let glyph = NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: nil)!
    let glyphSize = glyph.size
    let percentageOrWarning = PercentageOrWarning(display.content)
    let percentageOrWarningSize = percentageOrWarning?.size ?? .zero
    let gap: CGFloat = percentageOrWarning == nil ? 0 : 4
    let size = NSSize(
        width: ceil(glyphSize.width + gap + percentageOrWarningSize.width),
        height: ceil(max(glyphSize.height, percentageOrWarningSize.height))
    )

    let glyphTint: (isRed: Bool, isDimmed: Bool) = switch display.content {
    case .glyph(let isRed, let isDimmed): (isRed, isDimmed)
    case .percentage, .warning: (false, false)
    }

    let image = NSImage(size: size, flipped: false) { rect in
        let foreground = foregroundColor()
        let glyphColor = glyphTint.isRed ? red() : foreground
        // Dimmed through the drawing's opacity: a palette colour's own alpha
        // comes out far fainter than 0.4 on a symbol.
        glyph.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [glyphColor]))!.draw(
            in: NSRect(
                x: 0,
                y: (rect.height - glyphSize.height) / 2,
                width: glyphSize.width,
                height: glyphSize.height
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: glyphTint.isDimmed ? dimmedAlpha : 1
        )
        percentageOrWarning?.draw(
            at: NSPoint(x: glyphSize.width + gap, y: (rect.height - percentageOrWarningSize.height) / 2),
            foreground: foreground
        )
        return true
    }
    image.isTemplate = false
    image.accessibilityDescription = display.accessibilityText
    return image
}

/// What follows the glyph: the percentage, or the warning triangle for a
/// persistent error.
private nonisolated enum PercentageOrWarning: Equatable {
    case text(String, isRed: Bool, isDimmed: Bool)
    /// `exclamationmark.triangle`, at the size of the menu bar font.
    case warning(NSImage)

    init?(_ content: MenuBarDisplay.Content) {
        switch content {
        case .glyph:
            return nil
        case .percentage(let text, let isRed, let isDimmed):
            self = .text(text, isRed: isRed, isDimmed: isDimmed)
        case .warning:
            let triangle = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)!
            self = .warning(triangle.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))!)
        }
    }

    private static var font: NSFont { NSFont.menuBarFont(ofSize: 0) }

    var size: NSSize {
        switch self {
        case .text(let text, _, _): (text as NSString).size(withAttributes: [.font: Self.font])
        case .warning(let triangle): triangle.size
        }
    }

    /// Draws at `origin`, inside the image's drawing handler.
    func draw(at origin: NSPoint, foreground: NSColor) {
        switch self {
        case .text(let text, let isRed, let isDimmed):
            let color = (isRed ? red() : foreground).withAlphaComponent(isDimmed ? dimmedAlpha : 1)
            (text as NSString).draw(at: origin, withAttributes: [.font: Self.font, .foregroundColor: color])
        case .warning(let triangle):
            triangle.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [foreground]))!
                .draw(in: NSRect(origin: origin, size: triangle.size))
        }
    }
}

/// The opacity of the element that carries the value while it is stale.
private nonisolated let dimmedAlpha: CGFloat = 0.4

/// The value from 90%. Call it inside the drawing handler, so red follows
/// the drawing appearance too.
private nonisolated func red() -> NSColor {
    NSColor.systemRed.usingColorSpace(.sRGB)!
}

/// Pure white on a dark menu bar, pure black on a light one. Semantic
/// colours like `labelColor` render grey on the vibrant menu bar.
private nonisolated func foregroundColor() -> NSColor {
    let match = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
    return match == .darkAqua || match == .vibrantDark ? .white : .black
}
