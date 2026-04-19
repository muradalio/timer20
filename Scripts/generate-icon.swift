#!/usr/bin/env swift

import AppKit
import Foundation

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesURL = rootURL.appendingPathComponent("Resources", isDirectory: true)
let iconsetURL = resourcesURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns")

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let icons: [(name: String, size: Int)] = [
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

for icon in icons {
    let image = drawIcon(size: CGFloat(icon.size))
    let fileURL = iconsetURL.appendingPathComponent(icon.name)
    try writePNG(image: image, to: fileURL)
}

try? FileManager.default.removeItem(at: icnsURL)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    throw NSError(
        domain: "Timer20Icon",
        code: Int(process.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: "iconutil failed"]
    )
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSGraphicsContext.current?.imageInterpolation = .high

    let radius = size * 0.22
    let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.06, green: 0.47, blue: 0.78, alpha: 1),
        NSColor(calibratedRed: 0.05, green: 0.73, blue: 0.61, alpha: 1)
    ])
    gradient?.draw(in: backgroundPath, angle: 135)

    NSColor(calibratedWhite: 1, alpha: 0.16).setFill()
    NSBezierPath(ovalIn: NSRect(x: size * 0.58, y: size * 0.58, width: size * 0.42, height: size * 0.42)).fill()
    NSColor(calibratedWhite: 0, alpha: 0.10).setFill()
    NSBezierPath(ovalIn: NSRect(x: -size * 0.16, y: -size * 0.18, width: size * 0.62, height: size * 0.62)).fill()

    drawEye(in: rect, size: size)
    drawTwenty(in: rect, size: size)

    image.unlockFocus()
    return image
}

func drawEye(in rect: NSRect, size: CGFloat) {
    let eyeRect = NSRect(x: size * 0.19, y: size * 0.33, width: size * 0.62, height: size * 0.32)
    let eyePath = NSBezierPath()
    eyePath.move(to: NSPoint(x: eyeRect.minX, y: eyeRect.midY))
    eyePath.curve(
        to: NSPoint(x: eyeRect.maxX, y: eyeRect.midY),
        controlPoint1: NSPoint(x: eyeRect.minX + eyeRect.width * 0.24, y: eyeRect.maxY),
        controlPoint2: NSPoint(x: eyeRect.minX + eyeRect.width * 0.76, y: eyeRect.maxY)
    )
    eyePath.curve(
        to: NSPoint(x: eyeRect.minX, y: eyeRect.midY),
        controlPoint1: NSPoint(x: eyeRect.minX + eyeRect.width * 0.76, y: eyeRect.minY),
        controlPoint2: NSPoint(x: eyeRect.minX + eyeRect.width * 0.24, y: eyeRect.minY)
    )
    eyePath.close()

    NSColor(calibratedWhite: 1, alpha: 0.94).setFill()
    eyePath.fill()

    let pupilSize = size * 0.17
    let pupilRect = NSRect(
        x: rect.midX - pupilSize / 2,
        y: eyeRect.midY - pupilSize / 2,
        width: pupilSize,
        height: pupilSize
    )
    NSColor(calibratedRed: 0.04, green: 0.21, blue: 0.25, alpha: 1).setFill()
    NSBezierPath(ovalIn: pupilRect).fill()

    NSColor(calibratedWhite: 1, alpha: 0.86).setFill()
    NSBezierPath(ovalIn: NSRect(
        x: pupilRect.minX + pupilSize * 0.55,
        y: pupilRect.minY + pupilSize * 0.56,
        width: pupilSize * 0.22,
        height: pupilSize * 0.22
    )).fill()
}

func drawTwenty(in rect: NSRect, size: CGFloat) {
    guard size >= 64 else {
        return
    }

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let fontSize = size * 0.19
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
        .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.94),
        .paragraphStyle: paragraph,
        .kern: -fontSize * 0.02
    ]

    let textRect = NSRect(x: 0, y: size * 0.13, width: size, height: fontSize * 1.35)
    NSString(string: "20").draw(in: textRect, withAttributes: attributes)
}

func writePNG(image: NSImage, to url: URL) throws {
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(
            domain: "Timer20Icon",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"]
        )
    }

    try pngData.write(to: url)
}
