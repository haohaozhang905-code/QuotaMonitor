#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

private let canvasSize = 1024
private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let resources = root.appendingPathComponent("Sources/QuotaMonitor/Resources", isDirectory: true)
private let pngURL = resources.appendingPathComponent("AppIcon.png")
private let icnsURL = resources.appendingPathComponent("AppIcon.icns")

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

private func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

private func drawArc(
    in context: CGContext,
    center: CGPoint,
    radius: CGFloat,
    startDegrees: CGFloat,
    endDegrees: CGFloat,
    width: CGFloat,
    color: CGColor
) {
    context.setStrokeColor(color)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.addArc(
        center: center,
        radius: radius,
        startAngle: startDegrees * .pi / 180,
        endAngle: endDegrees * .pi / 180,
        clockwise: false
    )
    context.strokePath()
}

private func makeIcon(size: Int) -> NSBitmapImageRep {
    let scale = CGFloat(size) / CGFloat(canvasSize)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Unable to create \(size)px bitmap")
    }
    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    defer { NSGraphicsContext.restoreGraphicsState() }

    let context = graphics.cgContext
    context.scaleBy(x: scale, y: scale)
    context.setAllowsAntialiasing(true)
    context.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

    let tile = CGRect(x: 58, y: 58, width: 908, height: 908)
    let tilePath = roundedRect(tile, radius: 224)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -26), blur: 46, color: color(0x08111F, alpha: 0.34))
    context.addPath(tilePath)
    context.setFillColor(color(0x0C1526))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let background = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0x314A70), color(0x172A48), color(0x0B1425)] as CFArray,
        locations: [0, 0.48, 1]
    )!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: 165, y: 895),
        end: CGPoint(x: 865, y: 120),
        options: []
    )

    let glow = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0xB9E7FF, alpha: 0.28), color(0xB9E7FF, alpha: 0)] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: 246, y: 824),
        startRadius: 0,
        endCenter: CGPoint(x: 246, y: 824),
        endRadius: 520,
        options: []
    )
    context.restoreGState()

    context.addPath(tilePath)
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.28))
    context.setLineWidth(5)
    context.strokePath()

    let center = CGPoint(x: 512, y: 522)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, alpha: 0.34))
    drawArc(in: context, center: center, radius: 274, startDegrees: -34, endDegrees: 126, width: 92, color: color(0x5795FF))
    drawArc(in: context, center: center, radius: 274, startDegrees: 146, endDegrees: 306, width: 92, color: color(0xFF795A))
    context.restoreGState()

    drawArc(in: context, center: center, radius: 274, startDegrees: -30, endDegrees: 80, width: 14, color: color(0xFFFFFF, alpha: 0.38))
    drawArc(in: context, center: center, radius: 274, startDegrees: 150, endDegrees: 248, width: 14, color: color(0xFFFFFF, alpha: 0.25))

    let coreRect = CGRect(x: 346, y: 356, width: 332, height: 332)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: color(0x000000, alpha: 0.35))
    context.addEllipse(in: coreRect)
    context.setFillColor(color(0x101D32, alpha: 0.90))
    context.fillPath()
    context.restoreGState()

    context.addEllipse(in: coreRect.insetBy(dx: 3, dy: 3))
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.17))
    context.setLineWidth(6)
    context.strokePath()

    context.setStrokeColor(color(0xF6FAFF, alpha: 0.96))
    context.setLineWidth(42)
    context.setLineCap(.round)
    context.addEllipse(in: CGRect(x: 422, y: 432, width: 180, height: 180))
    context.strokePath()
    context.move(to: CGPoint(x: 570, y: 456))
    context.addLine(to: CGPoint(x: 638, y: 388))
    context.strokePath()

    context.setFillColor(color(0xFFFFFF, alpha: 0.82))
    context.fillEllipse(in: CGRect(x: 770, y: 760, width: 28, height: 28))

    return bitmap
}

private func pngData(for bitmap: NSBitmapImageRep) -> Data? {
    return bitmap.representation(using: .png, properties: [:])
}

try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
guard let masterData = pngData(for: makeIcon(size: canvasSize)) else {
    fatalError("Unable to encode AppIcon.png")
}
try masterData.write(to: pngURL, options: .atomic)

let temporaryRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("QuotaMonitor-AppIcon-\(UUID().uuidString)", isDirectory: true)
let iconset = temporaryRoot.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let representations: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in representations {
    guard let data = pngData(for: makeIcon(size: size)) else { fatalError("Unable to encode \(name)") }
    try data.write(to: iconset.appendingPathComponent(name), options: .atomic)
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", iconset.path, "--output", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

try? FileManager.default.removeItem(at: temporaryRoot)
print("Generated \(pngURL.path) and \(icnsURL.path)")
