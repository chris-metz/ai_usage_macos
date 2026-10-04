import AppKit
import SwiftUI
import Testing

// Snapshot tests (§10.2). References are PNGs in `__Snapshots__/` next to
// this file, named `<test>-<variant>.png` and read via `#filePath`, not as
// resources. A missing reference is written and the test fails; so does
// every snapshot with `PACEMARK_RECORD_SNAPSHOTS=1`. On a mismatch the actual
// image and a diff go to `.build/snapshot-failures/`.

/// Draws a menu bar label image the way a light and a dark menu bar would:
/// under `.vibrantLight` onto a light background (`<test>-light.png`) and
/// under `.vibrantDark` onto a dark one (`<test>-dark.png`), at 2×.
func expectLabelSnapshot(
    _ image: NSImage,
    test: String = #function,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    for variant in Snapshot.Variant.allCases {
        let pixels = Snapshot.render(
            size: image.size,
            appearance: variant.menuBarAppearance,
            background: variant.menuBarBackground
        ) { rect in
            image.draw(in: rect)
        }
        expectSnapshot(pixels, named: Snapshot.name(test, variant), sourceLocation: sourceLocation)
    }
}

/// Renders a view through `NSHostingView` at a fixed width, under `.aqua`
/// (`<test>-light.png`) and `.darkAqua` (`<test>-dark.png`), onto the opaque
/// window background colour, at 2×. The height follows the content.
func expectViewSnapshot(
    _ view: some View,
    width: CGFloat,
    test: String = #function,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    for variant in Snapshot.Variant.allCases {
        let pixels = Snapshot.render(view, width: width, appearance: variant.windowAppearance)
        expectSnapshot(pixels, named: Snapshot.name(test, variant), sourceLocation: sourceLocation)
    }
}

/// Compares `actual` with the reference `<name>.png`, allowing 3/255 per
/// channel.
func expectSnapshot(_ actual: Snapshot.Pixels, named name: String, sourceLocation: SourceLocation = #_sourceLocation) {
    let reference = Snapshot.referenceDirectory.appending(path: "\(name).png")
    let path = reference.path(percentEncoded: false)

    if Snapshot.isRecording || !FileManager.default.fileExists(atPath: path) {
        let wasMissing = !FileManager.default.fileExists(atPath: path)
        do {
            try FileManager.default.createDirectory(at: Snapshot.referenceDirectory, withIntermediateDirectories: true)
            try actual.png.write(to: reference)
            let what = wasMissing ? "New reference recorded" : "Reference re-recorded"
            Issue.record("\(what), inspect it: \(path)", sourceLocation: sourceLocation)
        } catch {
            Issue.record("Couldn't write the reference \(path): \(error)", sourceLocation: sourceLocation)
        }
        return
    }

    guard let data = try? Data(contentsOf: reference), let expected = Snapshot.Pixels(png: data) else {
        Issue.record("Couldn't read the reference \(path)", sourceLocation: sourceLocation)
        return
    }
    let difference = actual.maxDifference(from: expected)
    if let difference, difference <= Snapshot.tolerance { return }

    let failures = Snapshot.failureDirectory
    let actualURL = failures.appending(path: "\(name).png")
    let diffURL = failures.appending(path: "\(name)-diff.png")
    try? FileManager.default.createDirectory(at: failures, withIntermediateDirectories: true)
    try? actual.png.write(to: actualURL)
    var message: String
    if let difference {
        try? actual.diff(from: expected, tolerance: Snapshot.tolerance).png.write(to: diffURL)
        message = "Snapshot \(name) differs by up to \(difference)/255 per channel"
        message += "; actual: \(actualURL.path(percentEncoded: false)), diff: \(diffURL.path(percentEncoded: false))"
    } else {
        message = "Snapshot \(name) is \(actual.width)×\(actual.height) px, the reference \(expected.width)×\(expected.height) px"
        message += "; actual: \(actualURL.path(percentEncoded: false))"
    }
    Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
}

enum Snapshot {
    /// The largest allowed difference per channel, out of 255.
    static let tolerance = 3
    static let scale: CGFloat = 2

    static let referenceDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "__Snapshots__", directoryHint: .isDirectory)

    /// `.build/snapshot-failures/` in the package root.
    static let failureDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent()  // PacemarkKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // package root
        .appending(path: ".build/snapshot-failures", directoryHint: .isDirectory)

    static var isRecording: Bool {
        ProcessInfo.processInfo.environment["PACEMARK_RECORD_SNAPSHOTS"] == "1"
    }

    enum Variant: String, CaseIterable {
        case light, dark

        var menuBarAppearance: NSAppearance {
            NSAppearance(named: self == .light ? .vibrantLight : .vibrantDark)!
        }

        /// Opaque stand-ins for the translucent menu bar.
        var menuBarBackground: NSColor {
            switch self {
            case .light: NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)
            case .dark: NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)
            }
        }

        var windowAppearance: NSAppearance {
            NSAppearance(named: self == .light ? .aqua : .darkAqua)!
        }
    }

    /// `<test>-<variant>`, where `<test>` is the test function's name
    /// without its argument list.
    static func name(_ test: String, _ variant: Variant) -> String {
        let base = test.prefix { $0 != "(" }
        return "\(base)-\(variant.rawValue)"
    }

    /// Fills a 2× bitmap of `size` points with `background` and runs `draw`,
    /// both with `appearance` as the current drawing appearance.
    static func render(
        size: NSSize,
        appearance: NSAppearance,
        background: NSColor,
        draw: (NSRect) -> Void
    ) -> Pixels {
        let rep = bitmap(size: size)
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        appearance.performAsCurrentDrawingAppearance {
            let rect = NSRect(origin: .zero, size: size)
            background.setFill()
            rect.fill()
            draw(rect)
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return Pixels(cgImage: rep.cgImage!)
    }

    /// Renders `view` in a bare `NSHostingView`. Not in a window: an
    /// offscreen window draws controls in their inactive style.
    static func render(_ view: some View, width: CGFloat, appearance: NSAppearance) -> Pixels {
        pinAccentColor
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        let size = NSSize(width: width, height: host.fittingSize.height)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let rep = bitmap(size: size)
        host.cacheDisplay(in: host.bounds, to: rep)
        return render(size: size, appearance: appearance, background: .windowBackgroundColor) { rect in
            rep.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    /// Controls follow the system accent colour; pin it to blue so the
    /// references don't depend on the Mac's setting.
    private static let pinAccentColor: Void = {
        UserDefaults.standard.setVolatileDomain(["AppleAccentColor": 4], forName: UserDefaults.argumentDomain)
    }()

    private static func bitmap(size: NSSize) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((size.width * scale).rounded(.up)),
            pixelsHigh: Int((size.height * scale).rounded(.up)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = size
        return rep
    }

    /// A bitmap in one fixed format, whether rendered or read from a PNG:
    /// sRGB, 8-bit RGBA, premultiplied, rows top to bottom.
    struct Pixels {
        let width: Int
        let height: Int
        var bytes: [UInt8]

        init(cgImage: CGImage) {
            width = cgImage.width
            height = cgImage.height
            bytes = [UInt8](repeating: 0, count: width * height * 4)
            let (width, height) = (width, height)
            bytes.withUnsafeMutableBytes { buffer in
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )!
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }

        init?(png: Data) {
            guard let source = CGImageSourceCreateWithData(png as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return nil }
            self.init(cgImage: image)
        }

        var png: Data {
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: CGDataProvider(data: Data(bytes) as CFData)!,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )!
            return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
        }

        /// The largest difference of any channel of any pixel; nil when the
        /// sizes differ.
        func maxDifference(from other: Pixels) -> Int? {
            guard width == other.width, height == other.height else { return nil }
            var largest = 0
            for index in bytes.indices {
                largest = max(largest, abs(Int(bytes[index]) - Int(other.bytes[index])))
            }
            return largest
        }

        /// This image darkened, with every pixel that differs by more than
        /// `tolerance` painted red.
        func diff(from other: Pixels, tolerance: Int) -> Pixels {
            var result = self
            for pixel in stride(from: 0, to: bytes.count, by: 4) {
                let differs = (0..<4).contains { abs(Int(bytes[pixel + $0]) - Int(other.bytes[pixel + $0])) > tolerance }
                result.bytes[pixel] = differs ? 255 : bytes[pixel] / 4
                result.bytes[pixel + 1] = differs ? 0 : bytes[pixel + 1] / 4
                result.bytes[pixel + 2] = differs ? 0 : bytes[pixel + 2] / 4
                result.bytes[pixel + 3] = 255
            }
            return result
        }
    }
}
