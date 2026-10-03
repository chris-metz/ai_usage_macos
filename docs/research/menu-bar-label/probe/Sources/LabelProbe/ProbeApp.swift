import AppKit
import Observation
import SwiftUI

// Throwaway probe for "Can the menu bar item show a red or dimmed percentage?" (#17).
// Usage: LabelProbe <batch>   (FORCE_LIGHT=1 forces .vibrantLight on the status windows, BACKDROP=1 adds a light window)
//   s1  SwiftUI MenuBarExtra: baseline, foregroundStyle/foregroundColor/AttributedString red, opacity
//   s2  SwiftUI MenuBarExtra: secondary, red on HStack, dynamic non-template image, template image with alpha, tertiary
//   a   AppKit NSStatusItem: baseline, attributedTitle red / tertiary / secondary / red+alpha, appearsDisabled
//   a2  AppKit: eagerly resolved dim colours, disabledControlTextColor, highlight(true)
//   a3  AppKit: dim colours resolved at draw time (dynamic NSColor)
//   a4  AppKit: the four states with dimming at 0.3, dimmed red at 0.3 and 0.5
//   a5  AppKit: the four states with dimming at 0.4
//   c   SwiftUI MenuBarExtra with the whole label drawn as one non-template image
//   ax  accessibility of drawn image labels
//   h   SwiftUI MenuBarExtra whose button gets an attributedTitle patched in from outside
// Every item shows a distinct percentage so it can be told apart in the dump and the screenshot.
let batch = CommandLine.arguments.dropFirst().first ?? "s1"

let glyph = "gauge.with.needle"

@Observable
final class Ticker {
    var count = 0
}

@main
struct ProbeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var ticker = Ticker()

    var body: some Scene {
        // Batch s1
        extra("s1", "40% baseline") {
            HStack { Image(systemName: glyph); Text("40%") }
        }
        extra("s1", "41% Text.foregroundStyle(.red)") {
            HStack { Image(systemName: glyph); Text("41%").foregroundStyle(.red) }
        }
        extra("s1", "42% Text.foregroundColor(.red)") {
            HStack { Image(systemName: glyph); Text("42%").foregroundColor(.red) }
        }
        extra("s1", "43% Text(AttributedString red)") {
            HStack { Image(systemName: glyph); Text(redAttributed("43%")) }
        }
        extra("s1", "44% Text.opacity(0.4)") {
            HStack { Image(systemName: glyph); Text("44%").opacity(0.4) }
        }
        // Batch s2
        extra("s2", "45% Text.foregroundStyle(.secondary)") {
            HStack { Image(systemName: glyph); Text("45%").foregroundStyle(.secondary) }
        }
        extra("s2", "46% HStack.foregroundStyle(.red)") {
            HStack { Image(systemName: glyph); Text("46%") }.foregroundStyle(.red)
        }
        extra("s2", "47% Image(nsImage: dynamic, non-template, red text)") {
            Image(nsImage: LabelImage.make(text: "47%", textColor: .systemRed, template: false))
        }
        extra("s2", "48% Image(nsImage: template, text alpha 0.4)") {
            Image(nsImage: LabelImage.make(text: "48%", textColor: NSColor.black.withAlphaComponent(0.4), template: true))
        }
        extra("s2", "49% Text.foregroundStyle(tertiaryLabelColor)") {
            HStack { Image(systemName: glyph); Text("49%").foregroundStyle(Color(nsColor: .tertiaryLabelColor)) }
        }
        // Batch c: the whole label drawn as one non-template image, in every state.
        extra("c", "30% system label (reference)") {
            HStack { Image(systemName: glyph); Text("30%") }
        }
        extra("c", "31% drawn, regular") {
            Image(nsImage: DrawnLabel.make(text: "31%", tone: .normal, weight: .regular))
        }
        extra("c", "32% drawn, medium") {
            Image(nsImage: DrawnLabel.make(text: "32%", tone: .normal, weight: .medium))
        }
        extra("c", "93% drawn, red") {
            Image(nsImage: DrawnLabel.make(text: "93%", tone: .red, weight: .regular))
        }
        extra("c", "72% drawn, dimmed") {
            Image(nsImage: DrawnLabel.make(text: "72%", tone: .dimmed, weight: .regular))
        }
        // Batch ax: accessibility of a drawn label
        extra("ax", "33% drawn, NSImage.accessibilityDescription") {
            Image(nsImage: {
                let i = DrawnLabel.make(text: "33%", tone: .normal, weight: .regular)
                i.accessibilityDescription = "Session limit 33 percent (NSImage)"
                return i
            }())
        }
        extra("ax", "34% drawn, SwiftUI accessibilityLabel") {
            Image(nsImage: DrawnLabel.make(text: "34%", tone: .normal, weight: .regular))
                .accessibilityLabel("Session limit 34 percent (SwiftUI)")
        }
        extra("ax", "35% system label") {
            HStack { Image(systemName: glyph); Text("35%") }
        }
        // Batch h: the label changes every 3 s, to see whether SwiftUI overwrites a patched attributedTitle.
        extra("h", "6x% patched attributedTitle") {
            HStack { Image(systemName: glyph); Text("6\(ticker.count % 10)%") }
        }
    }

    private func extra<L: View>(_ b: String, _ name: String, @ViewBuilder label: () -> L) -> some Scene {
        MenuBarExtra(isInserted: .constant(batch == b)) {
            Text(name).padding()
        } label: {
            label()
        }
        .menuBarExtraStyle(.window)
    }

    private func redAttributed(_ s: String) -> AttributedString {
        var a = AttributedString(s)
        a.foregroundColor = .red
        return a
    }

    init() {
        if batch == "h" {
            let t = ticker
            Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                MainActor.assumeIsolated { t.count += 1 }
            }
        }
    }
}

/// A label image (glyph plus percentage) drawn at draw time, so dynamic colours resolve
/// against the appearance of the view that draws it.
enum LabelImage {
    static func make(text: String, textColor: NSColor, template: Bool) -> NSImage {
        let font = NSFont.menuBarFont(ofSize: 0)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
        let symbol = NSImage(systemSymbolName: glyph, accessibilityDescription: nil)!
            .withSymbolConfiguration(symbolConfig)!
        let gap: CGFloat = 4
        let height = max(symbol.size.height, textSize.height)
        let size = NSSize(width: ceil(symbol.size.width + gap + textSize.width), height: ceil(height))
        let image = NSImage(size: size, flipped: false) { _ in
            let glyphColor: NSColor = template ? .black : .labelColor
            let tinted = symbol.withSymbolConfiguration(.init(paletteColors: [glyphColor]))!
            tinted.draw(in: NSRect(x: 0, y: (height - symbol.size.height) / 2, width: symbol.size.width, height: symbol.size.height))
            (text as NSString).draw(at: NSPoint(x: symbol.size.width + gap, y: (height - textSize.height) / 2), withAttributes: attrs)
            return true
        }
        image.isTemplate = template
        return image
    }
}

/// The full label drawn at draw time: glyph in the menu bar's plain foreground colour,
/// text in the colour for its tone, both resolved against the drawing appearance.
enum DrawnLabel {
    enum Tone { case normal, red, dimmed }

    static func make(text: String, tone: Tone, weight: NSFont.Weight) -> NSImage {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .regular) + 0, weight: weight)
        let symbol = NSImage(systemSymbolName: glyph, accessibilityDescription: nil)!
        let symbolSize = symbol.size
        let probeAttrs: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (text as NSString).size(withAttributes: probeAttrs)
        let gap: CGFloat = 4
        let height = max(symbolSize.height, ceil(textSize.height))
        let size = NSSize(width: ceil(symbolSize.width + gap + textSize.width), height: height)
        let image = NSImage(size: size, flipped: false) { _ in
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark]).map { $0 == .darkAqua || $0 == .vibrantDark } ?? false
            let fg: NSColor = dark ? .white : .black
            let textColor: NSColor
            switch tone {
            case .normal: textColor = fg
            case .red: textColor = NSColor(cgColor: NSColor.systemRed.cgColor) ?? .red
            case .dimmed: textColor = fg.withAlphaComponent(0.4)
            }
            let tinted = symbol.withSymbolConfiguration(.init(paletteColors: [fg]))!
            tinted.draw(in: NSRect(x: 0, y: (height - symbolSize.height) / 2, width: symbolSize.width, height: symbolSize.height))
            (text as NSString).draw(at: NSPoint(x: symbolSize.width + gap, y: (height - textSize.height) / 2),
                                    withAttributes: [.font: font, .foregroundColor: textColor])
            return true
        }
        image.isTemplate = false
        return image
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var items: [NSStatusItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if batch == "a" { makeAppKitItems() }
        if batch == "a2" { makeAppKitItems2() }
        if batch == "a3" { makeAppKitItems3() }
        if batch == "a4" { makeAppKitItems4() }
        if batch == "a5" { makeAppKitItems5() }
        let env = ProcessInfo.processInfo.environment
        if env["BACKDROP"] != nil { showBackdrop() }
        if env["FORCE_LIGHT"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                for w in self.statusWindows() { w.appearance = NSAppearance(named: .vibrantLight) }
                print("forced vibrantLight on status windows")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if batch == "h" { self.patchSwiftUIButton() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.dump(tag: "t+2.5s") }
        if batch == "h" {
            // After two label updates by SwiftUI.
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.5) { self.dump(tag: "t+8.5s") }
        }
    }

    // MARK: AppKit batch

    private func makeAppKitItems() {
        let font = NSFont.menuBarFont(ofSize: 0)
        func attributed(_ s: String, _ color: NSColor) -> NSAttributedString {
            NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        }
        add("50% baseline title") { $0.title = "50%" }
        add("51% attributedTitle systemRed") { $0.attributedTitle = attributed("51%", .systemRed) }
        add("52% attributedTitle tertiaryLabelColor") { $0.attributedTitle = attributed("52%", .tertiaryLabelColor) }
        add("53% attributedTitle secondaryLabelColor") { $0.attributedTitle = attributed("53%", .secondaryLabelColor) }
        add("54% attributedTitle systemRed alpha 0.5") { $0.attributedTitle = attributed("54%", .systemRed.withAlphaComponent(0.5)) }
        add("55% appearsDisabled") { $0.title = "55%"; $0.appearsDisabled = true }
    }

    private func makeAppKitItems2() {
        let font = NSFont.menuBarFont(ofSize: 0)
        func attributed(_ s: String, _ color: NSColor) -> NSAttributedString {
            NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        }
        add("70% attributedTitle labelColor alpha 0.4") { $0.attributedTitle = attributed("70%", .labelColor.withAlphaComponent(0.4)) }
        add("71% attributedTitle controlTextColor alpha 0.4") { $0.attributedTitle = attributed("71%", .controlTextColor.withAlphaComponent(0.4)) }
        add("72% attributedTitle disabledControlTextColor") { $0.attributedTitle = attributed("72%", .disabledControlTextColor) }
        add("73% attributedTitle systemRed, highlighted") { $0.attributedTitle = attributed("73%", .systemRed); $0.highlight(true) }
        add("74% title, highlighted") { $0.title = "74%"; $0.highlight(true) }
        print("menuBarFont: \(font)")
    }

    /// A colour resolved against the appearance it is drawn in, with a fixed alpha.
    private func dimmed(_ base: NSColor, alpha: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            var resolved = base
            appearance.performAsCurrentDrawingAppearance {
                resolved = NSColor(cgColor: base.cgColor) ?? base
            }
            return resolved.withAlphaComponent(alpha)
        }
    }

    private func makeAppKitItems3() {
        let font = NSFont.menuBarFont(ofSize: 0)
        func attributed(_ s: String, _ color: NSColor) -> NSAttributedString {
            NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        }
        add("80% attributedTitle dynamic labelColor alpha 0.4") { $0.attributedTitle = attributed("80%", self.dimmed(.labelColor, alpha: 0.4)) }
        add("81% attributedTitle dynamic controlTextColor alpha 0.5") { $0.attributedTitle = attributed("81%", self.dimmed(.controlTextColor, alpha: 0.5)) }
        add("82% attributedTitle dynamic systemRed alpha 0.5") { $0.attributedTitle = attributed("82%", self.dimmed(.systemRed, alpha: 0.5)) }
        add("83% appearsDisabled") { $0.title = "83%"; $0.appearsDisabled = true }
        add("84% baseline title") { $0.title = "84%" }
        add("85% attributedTitle systemRed") { $0.attributedTitle = attributed("85%", .systemRed) }
    }

    /// The candidate for the spec: the four menu bar states, each a template glyph plus an attributedTitle.
    private func makeAppKitItems4() {
        let font = NSFont.menuBarFont(ofSize: 0)
        func attributed(_ s: String, _ color: NSColor) -> NSAttributedString {
            NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        }
        add("71% normal (plain title)") { $0.title = "71%" }
        add("93% red: systemRed") { $0.attributedTitle = attributed("93%", .systemRed) }
        add("72% stale: labelColor at 0.3") { $0.attributedTitle = attributed("72%", self.dimmed(.labelColor, alpha: 0.3)) }
        add("94% stale red: systemRed at 0.3") { $0.attributedTitle = attributed("94%", self.dimmed(.systemRed, alpha: 0.3)) }
        add("95% stale red: systemRed at 0.5") { $0.attributedTitle = attributed("95%", self.dimmed(.systemRed, alpha: 0.5)) }
        add("73% reference: appearsDisabled") { $0.title = "73%"; $0.appearsDisabled = true }
    }

    /// One shared dimming opacity for both colours, at 0.4.
    private func makeAppKitItems5() {
        let font = NSFont.menuBarFont(ofSize: 0)
        func attributed(_ s: String, _ color: NSColor) -> NSAttributedString {
            NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        }
        add("71% normal (plain title)") { $0.title = "71%" }
        add("93% red: systemRed") { $0.attributedTitle = attributed("93%", .systemRed) }
        add("72% stale: labelColor at 0.4") { $0.attributedTitle = attributed("72%", self.dimmed(.labelColor, alpha: 0.4)) }
        add("94% stale red: systemRed at 0.4") { $0.attributedTitle = attributed("94%", self.dimmed(.systemRed, alpha: 0.4)) }
        add("73% reference: appearsDisabled") { $0.title = "73%"; $0.appearsDisabled = true }
    }

    private var backdrop: NSWindow?

    /// A plain light window behind the transparent menu bar, to approximate a light wallpaper.
    private func showBackdrop() {
        let screen = NSScreen.screens.first!
        let rect = NSRect(x: screen.frame.minX + 600, y: screen.frame.maxY - 40, width: screen.frame.width - 600, height: 40)
        let w = UnconstrainedWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        w.backgroundColor = NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)
        w.ignoresMouseEvents = true
        w.level = .normal
        w.setFrame(rect, display: true)
        w.orderFrontRegardless()
        backdrop = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { print("backdrop frame=\(w.frame)") }
    }

    private func add(_ name: String, configure: (NSStatusBarButton) -> Void) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let button = item.button!
        let image = NSImage(systemSymbolName: glyph, accessibilityDescription: nil)!
        image.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        configure(button)
        print("created: \(name)")
        items.append(item)
    }

    // MARK: Hack batch

    private func patchSwiftUIButton() {
        for button in statusButtons() {
            let font = button.font ?? NSFont.menuBarFont(ofSize: 0)
            button.attributedTitle = NSAttributedString(
                string: button.title,
                attributes: [.font: font, .foregroundColor: NSColor.systemRed]
            )
            print("patched attributedTitle on button titled \(button.title)")
        }
    }

    // MARK: Dump

    private func statusWindows() -> [NSWindow] {
        NSApp.windows.filter { String(describing: type(of: $0)).contains("StatusBar") }
    }

    private func statusButtons() -> [NSStatusBarButton] {
        statusWindows().flatMap { w in w.contentView.map { buttons(in: $0) } ?? [] }
    }

    private func buttons(in view: NSView) -> [NSStatusBarButton] {
        var found: [NSStatusBarButton] = []
        if let b = view as? NSStatusBarButton { found.append(b) }
        for sub in view.subviews { found += buttons(in: sub) }
        return found
    }

    private func dump(tag: String) {
        print("===== dump \(tag) batch=\(batch)")
        let mainHeight = NSScreen.screens.first!.frame.height
        for s in NSScreen.screens {
            print("screen \(s.localizedName) frame=\(s.frame) scale=\(s.backingScaleFactor)")
        }
        for w in statusWindows() {
            let f = w.frame
            print("--- window \(type(of: w)) frame=\(f) screen=\(w.screen?.localizedName ?? "nil") region=\(Int(f.minX)),\(Int(mainHeight - f.maxY)),\(Int(f.width)),\(Int(f.height)) appearance=\(w.effectiveAppearance.name.rawValue)")
            if let cv = w.contentView { tree(cv, depth: 0) }
        }
        fflush(stdout)
    }

    private func tree(_ v: NSView, depth: Int) {
        let pad = String(repeating: "  ", count: depth)
        var line = "\(pad)\(type(of: v)) frame=\(v.frame) alpha=\(v.alphaValue)"
        if let b = v as? NSStatusBarButton {
            line += "\n\(pad)  title=\"\(b.title)\" appearsDisabled=\(b.appearsDisabled) enabled=\(b.isEnabled) imagePosition=\(b.imagePosition.rawValue) contentTintColor=\(String(describing: b.contentTintColor)) font=\(String(describing: b.font))"
            if let img = b.image {
                line += "\n\(pad)  image size=\(img.size) isTemplate=\(img.isTemplate) reps=\(img.representations.map { String(describing: type(of: $0)) })"
            } else {
                line += "\n\(pad)  image=nil"
            }
            let at = b.attributedTitle
            at.enumerateAttributes(in: NSRange(location: 0, length: at.length)) { attrs, range, _ in
                let desc = attrs.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: "; ")
                line += "\n\(pad)  attributedTitle\(range): \(desc)"
            }
            line += "\n\(pad)  appearance=\(b.effectiveAppearance.name.rawValue)"
            line += "\n\(pad)  ax role=\(String(describing: b.accessibilityRole())) title=\(String(describing: b.accessibilityTitle())) label=\(String(describing: b.accessibilityLabel())) imageDesc=\(String(describing: b.image?.accessibilityDescription))"
        }
        print(line)
        if depth < 6 { for sub in v.subviews { tree(sub, depth: depth + 1) } }
    }
}

final class UnconstrainedWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
