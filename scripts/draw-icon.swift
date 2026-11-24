import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

let sizes = [16, 32, 128, 256, 512]
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let top = CGColor(gray: 1, alpha: 1)
let bottom = CGColor(gray: 0.92, alpha: 1)

func icon(pixels: Int) -> Data {
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                            bytesPerRow: 0, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)

    let bounds = CGRect(x: 104, y: 104, width: 816, height: 816)
    let tile = CGPath(roundedRect: bounds, cornerWidth: 192, cornerHeight: 192, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -16), blur: 34,
                      color: CGColor(gray: 0, alpha: 0.28))
    context.addPath(tile)
    context.setFillColor(bottom)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tile)
    context.clip()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: [top, bottom] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 380, y: 925), end: CGPoint(x: 668, y: 100),
                               options: [.drawsAfterEndLocation, .drawsBeforeStartLocation])
    context.addPath(tile)
    context.setStrokeColor(CGColor(gray: 0, alpha: 0.10))
    context.setLineWidth(5)
    context.strokePath()
    context.restoreGState()

    context.setStrokeColor(CGColor(gray: 0.10, alpha: 1))
    context.setLineWidth(60)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: 322, y: 545))
    context.addLine(to: CGPoint(x: 456, y: 414))
    context.addLine(to: CGPoint(x: 695, y: 661))
    context.strokePath()

    context.setStrokeColor(CGColor(gray: 0.10, alpha: 0.76))
    context.setLineWidth(31)
    context.move(to: CGPoint(x: 446, y: 321))
    context.addLine(to: CGPoint(x: 693, y: 321))
    context.strokePath()

    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    return bitmap.representation(using: .png, properties: [:])!
}

for size in sizes {
    for scale in 1...2 {
        let suffix = scale == 2 ? "@2x" : ""
        try icon(pixels: size * scale).write(to: directory.appending(path: "icon_\(size)x\(size)\(suffix).png"))
    }
}
