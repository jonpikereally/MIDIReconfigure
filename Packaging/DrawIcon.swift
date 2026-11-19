import AppKit
import CoreGraphics
import UniformTypeIdentifiers
import ImageIO

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

let tile = CGRect(x: 102, y: 106, width: 820, height: 820)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 180, cornerHeight: 180, transform: nil)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -15), blur: 35, color: color(0, 0, 0, 0.44))
context.setFillColor(color(0.06, 0.08, 0.12))
context.addPath(tilePath)
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(tilePath)
context.clip()
let background = CGGradient(colorsSpace: colorSpace, colors: [
    color(0.15, 0.22, 0.29), color(0.07, 0.11, 0.17), color(0.045, 0.065, 0.11)
] as CFArray, locations: [0, 0.49, 1])!
context.drawLinearGradient(background, start: CGPoint(x: 240, y: 920), end: CGPoint(x: 820, y: 163),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
context.setStrokeColor(color(0.56, 0.73, 0.86, 0.11))
context.setLineWidth(2)
for line in stride(from: 242, through: 782, by: 54) {
    let coordinate = CGFloat(line)
    context.move(to: CGPoint(x: 206, y: coordinate))
    context.addLine(to: CGPoint(x: 818, y: coordinate))
    context.move(to: CGPoint(x: coordinate, y: 206))
    context.addLine(to: CGPoint(x: coordinate, y: 818))
}
context.strokePath()
context.restoreGState()

context.setStrokeColor(color(0.62, 0.77, 0.88, 0.24))
context.setLineWidth(4)
context.addPath(tilePath)
context.strokePath()

let left: CGFloat = 263
let right: CGFloat = 761
let upper: CGFloat = 671
let lower: CGFloat = 357
let teal = color(0.33, 0.97, 0.79)
let blue = color(0.53, 0.65, 1)
let dark = color(0.067, 0.105, 0.16)

func cable(from start: CGFloat, to end: CGFloat, stroke: CGColor, width: CGFloat) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: left, y: start))
    path.addLine(to: CGPoint(x: 374, y: start))
    path.addCurve(to: CGPoint(x: 650, y: end),
                  control1: CGPoint(x: 495, y: start), control2: CGPoint(x: 529, y: end))
    path.addLine(to: CGPoint(x: right, y: end))
    context.setStrokeColor(stroke)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.addPath(path)
    context.strokePath()
}

func jack(at x: CGFloat, _ y: CGFloat, stroke: CGColor) {
    let ring = CGRect(x: x - 31, y: y - 31, width: 62, height: 62)
    context.setFillColor(dark)
    context.fillEllipse(in: ring.insetBy(dx: -12, dy: -12))
    context.setStrokeColor(stroke)
    context.setLineWidth(22)
    context.strokeEllipse(in: ring)
}

cable(from: lower, to: upper, stroke: blue, width: 29)
cable(from: upper, to: lower, stroke: dark, width: 65)
cable(from: upper, to: lower, stroke: teal, width: 29)
jack(at: left, lower, stroke: blue)
jack(at: right, upper, stroke: blue)
jack(at: left, upper, stroke: teal)
jack(at: right, lower, stroke: teal)

let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
precondition(CGImageDestinationFinalize(destination))
