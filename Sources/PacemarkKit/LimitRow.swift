import AppKit
import SwiftUI

/// One limit in the dropdown (§3 Layout): the title and `{U}%`, the bar with
/// the pace marker, and the reset line with the pace text. VoiceOver reads it
/// as one element.
struct LimitRow: View {
    let display: LimitDisplay

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(display.title)
                Spacer()
                Text(display.percentText)
                    .monospacedDigit()
            }
            .font(.system(size: 13, weight: .semibold))

            LimitBar(
                fillFraction: display.fillFraction,
                fillColor: display.fillColor.color,
                paceMarker: display.paceMarker
            )

            HStack {
                Text(display.resetLine)
                    .foregroundStyle(.secondary)
                Spacer()
                if let paceText = display.paceText {
                    Text(paceText)
                        .foregroundStyle(display.paceTextColor.textColor)
                }
            }
            .font(.system(size: 11))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(display.accessibilityText)
    }
}

/// A capsule 6 pt high with the fill from the left and the pace marker
/// reaching 3 pt above and below it.
private struct LimitBar: View {
    let fillFraction: Double
    let fillColor: Color
    let paceMarker: Double?

    private let barHeight: CGFloat = 6
    private let paceMarkerOverhang: CGFloat = 3
    private let paceMarkerWidth: CGFloat = 2
    private let paceMarkerOutline: CGFloat = 1.5

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(fillColor)
                        .frame(width: width * fillFraction)
                    if let paceMarker {
                        // The outline: a gap cut out of the bar, so the
                        // dropdown's background shows around the pace marker.
                        Rectangle()
                            .frame(width: paceMarkerWidth + 2 * paceMarkerOutline)
                            .offset(x: width * paceMarker - paceMarkerWidth / 2 - paceMarkerOutline)
                            .blendMode(.destinationOut)
                    }
                }
                .frame(height: barHeight)
                .compositingGroup()

                if let paceMarker {
                    Rectangle()
                        .fill(.primary)
                        .frame(width: paceMarkerWidth, height: barHeight + 2 * paceMarkerOverhang)
                        .offset(x: width * paceMarker - paceMarkerWidth / 2)
                }
            }
            .frame(height: geometry.size.height)
        }
        .frame(height: barHeight + 2 * paceMarkerOverhang)
    }
}

extension LimitColor {
    /// The macOS system colours; they adapt to light and dark. Blue is fixed
    /// and doesn't follow the accent colour.
    var color: Color {
        switch self {
        case .blue: Color(nsColor: .systemBlue)
        case .orange: Color(nsColor: .systemOrange)
        case .red: Color(nsColor: .systemRed)
        case .green: Color(nsColor: .systemGreen)
        case .secondary: Color(nsColor: .secondaryLabelColor)
        }
    }

    /// `color` for the pace text. The system green and orange are hard to
    /// read as small text on a light background, so in light they are darker.
    var textColor: Color {
        switch self {
        case .green: Color(nsColor: .darkerInLight(.systemGreen))
        case .orange: Color(nsColor: .darkerInLight(.systemOrange))
        case .blue, .red, .secondary: color
        }
    }
}

private extension NSColor {
    /// `color` in dark; in light, `color` at 70% brightness.
    static func darkerInLight(_ color: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            guard appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua else { return color }
            var darker = color
            appearance.performAsCurrentDrawingAppearance {
                let light = color.usingColorSpace(.sRGB)!
                darker = NSColor(
                    srgbRed: light.redComponent * 0.7,
                    green: light.greenComponent * 0.7,
                    blue: light.blueComponent * 0.7,
                    alpha: light.alphaComponent
                )
            }
            return darker
        }
    }
}
