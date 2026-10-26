import CoreGraphics
import ImageIO
import Foundation

// InkNote App Icon, drawn in code (original artwork, no copied icon).
// Headless-safe: pure CoreGraphics bitmap + ImageIO PNG, no AppKit
// window server needed, so it runs over SSH.
// Composition, 1024x1024: blue-to-teal gradient field, a white ruled
// paper sheet, and an amber pencil leaning across it.
let size = 1024
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

guard let ctx = CGContext(
    data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fputs("no bitmap context\n", stderr); exit(1) }

// Background gradient: deep blue (top) to teal (bottom).
let top = CGColor(red: 0.11, green: 0.32, blue: 0.86, alpha: 1)
let bottom = CGColor(red: 0.03, green: 0.64, blue: 0.62, alpha: 1)
if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top, bottom] as CFArray, locations: [0, 1]) {
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
}

// White paper sheet with rounded corners.
let paper = CGRect(x: 192, y: 128, width: 640, height: 768)
let paperPath = CGPath(roundedRect: paper, cornerWidth: 48, cornerHeight: 48, transform: nil)
ctx.addPath(paperPath)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fillPath()

// Ruled lines on the paper, clipped to the sheet.
ctx.saveGState()
ctx.addPath(paperPath)
ctx.clip()
ctx.setStrokeColor(CGColor(red: 0.82, green: 0.85, blue: 0.89, alpha: 1))
ctx.setLineWidth(3)
for y in stride(from: 300, through: 780, by: 96) {
    ctx.move(to: CGPoint(x: 256, y: y))
    ctx.addLine(to: CGPoint(x: 768, y: y))
}
ctx.strokePath()
ctx.restoreGState()

// Pencil, rotated -45 degrees around the sheet centre.
ctx.saveGState()
ctx.translateBy(x: 512, y: 512)
ctx.rotate(by: -CGFloat.pi / 4)
// Body (amber).
ctx.setFillColor(CGColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1))
ctx.fill(CGRect(x: -70, y: -180, width: 140, height: 430))
// Eraser (rose) and ferrule (light grey) at the top.
ctx.setFillColor(CGColor(red: 0.96, green: 0.44, blue: 0.58, alpha: 1))
ctx.fill(CGRect(x: -70, y: 250, width: 140, height: 80))
ctx.setFillColor(CGColor(red: 0.82, green: 0.84, blue: 0.87, alpha: 1))
ctx.fill(CGRect(x: -70, y: 230, width: 140, height: 20))
// Wood tip (pale) and graphite point (dark).
let wood = CGMutablePath()
wood.move(to: CGPoint(x: -70, y: -180))
wood.addLine(to: CGPoint(x: 70, y: -180))
wood.addLine(to: CGPoint(x: 0, y: -330))
wood.closeSubpath()
ctx.addPath(wood)
ctx.setFillColor(CGColor(red: 0.99, green: 0.88, blue: 0.70, alpha: 1))
ctx.fillPath()
let graphite = CGMutablePath()
graphite.move(to: CGPoint(x: -26, y: -236))
graphite.addLine(to: CGPoint(x: 26, y: -236))
graphite.addLine(to: CGPoint(x: 0, y: -330))
graphite.closeSubpath()
ctx.addPath(graphite)
ctx.setFillColor(CGColor(red: 0.20, green: 0.22, blue: 0.26, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

guard let image = ctx.makeImage() else { fputs("no image\n", stderr); exit(1) }
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
    fputs("no image destination\n", stderr); exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fputs("png write failed\n", stderr); exit(1) }
print("wrote \(outPath)")
