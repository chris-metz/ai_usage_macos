import AppKit
// sample.swift <png> <x0> <x1> ... : for each [x0,x1) column range in the menu bar strip (y 2..24),
// prints background luminance (median) and peak luminance, plus the implied alpha of white text.
let args = CommandLine.arguments
let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: args[1])))!
var i = 2
while i + 1 < args.count {
    let x0 = Int(args[i])!, x1 = Int(args[i + 1])!
    var lums: [Double] = []
    for x in x0..<x1 { for y in 4..<22 {
        let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        lums.append(0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent)
    } }
    lums.sort()
    let bg = lums[lums.count / 2], peak = lums[lums.count - 3]
    print(String(format: "x %d-%d  bg %.3f  peak %.3f  implied white alpha %.2f", x0, x1, bg, peak, (peak - bg) / (1 - bg)))
    i += 2
}
