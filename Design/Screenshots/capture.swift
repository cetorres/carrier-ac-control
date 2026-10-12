#!/usr/bin/env swift
// Captures the CarrierBar menu bar item and its open panel, and nothing else, into one PNG.
//
// The panel and the menu bar item are captured on their own and placed on a clean background
// with a plain menu bar strip, at their real positions. Other menu bar items, the clock, and
// the desktop never appear.
//
// Usage, from the repository root, with CarrierBar running (the "CarrierBar Demo" scheme
// shows made-up data):
//
//   swift Design/Screenshots/capture.swift [output.png] [delay in seconds]
//
// Then click the CarrierBar item in the menu bar before the countdown ends, and leave the
// pointer on it until the capture finishes. The default output is Design/Screenshots/panel.png,
// and the default delay is 5 seconds.
//
// Permissions for Terminal (System Settings › Privacy & Security):
//   Screen & System Audio Recording  required, macOS asks the first time
//   Accessibility                    optional, lets the script locate the menu bar item exactly
//
// If the menu bar item can't be found, a report of what's on screen is saved next to the
// output as capture-debug.txt.

import ApplicationServices
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
let outputPath = arguments.count > 1 ? arguments[1] : "Design/Screenshots/panel.png"
let delay = arguments.count > 2 ? max(0, Int(arguments[2]) ?? 5) : 5
let appName = "CarrierBar"
let outputURL = URL(fileURLWithPath: outputPath)
let debugURL = outputURL.deletingLastPathComponent().appendingPathComponent("capture-debug.txt")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

// MARK: - Windows

struct Window: CustomStringConvertible {
    let id: CGWindowID
    let owner: String
    let pid: pid_t
    let name: String
    let layer: Int
    let bounds: CGRect   // points, top-left origin, global screen coordinates

    var description: String {
        let b = bounds
        return "window \(id)  owner \"\(owner)\" (pid \(pid))  name \"\(name)\"  layer \(layer)  "
            + "x \(Int(b.minX)) y \(Int(b.minY)) w \(Int(b.width)) h \(Int(b.height))"
    }
}

func onScreenWindows() -> [Window] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
    return list.compactMap { info in
        guard let number = info[kCGWindowNumber as String] as? Int,
              let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
              bounds.width > 2, bounds.height > 2
        else { return nil }
        return Window(
            id: CGWindowID(number),
            owner: info[kCGWindowOwnerName as String] as? String ?? "",
            pid: pid_t(info[kCGWindowOwnerPID as String] as? Int ?? 0),
            name: info[kCGWindowName as String] as? String ?? "",
            layer: info[kCGWindowLayer as String] as? Int ?? 0,
            bounds: bounds
        )
    }
}

/// The frame of the app's menu bar item, from the accessibility interface. Needs Accessibility
/// permission for Terminal. Returns nil without it.
func accessibilityItemFrame(pid: pid_t) -> CGRect? {
    guard pid > 0, AXIsProcessTrusted() else { return nil }
    let app = AXUIElementCreateApplication(pid)

    var barValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &barValue) == .success,
          let barValue, CFGetTypeID(barValue) == AXUIElementGetTypeID()
    else { return nil }
    let bar = barValue as! AXUIElement

    var childrenValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &childrenValue) == .success,
          let children = childrenValue as? [AXUIElement], let element = children.first
    else { return nil }

    var positionValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
          let positionValue, let sizeValue,
          CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
    else { return nil }

    var position = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    let frame = CGRect(origin: position, size: size)
    return frame.width > 2 && frame.height > 2 ? frame : nil
}

// MARK: - Capturing

func runScreencapture(_ captureArguments: [String], to url: URL) -> CGImage {
    try? FileManager.default.removeItem(at: url)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x"] + captureArguments + [url.path]   // -x: no sound
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        fail("couldn't run screencapture: \(error.localizedDescription)")
    }
    guard process.terminationStatus == 0,
          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fail("screencapture failed. Give Terminal Screen Recording permission and try again.") }
    return image
}

/// One window by itself, with transparent corners and no shadow.
func captureWindow(_ window: Window, to url: URL) -> CGImage {
    runScreencapture(["-o", "-l", String(window.id)], to: url)
}

/// A rectangle of the screen, including whatever is behind it.
func captureRegion(_ rect: CGRect, to url: URL) -> CGImage {
    let r = rect.integral
    return runScreencapture(["-R", "\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))"], to: url)
}

// MARK: - Drawing helpers

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// Draws an image into a context whose coordinates are flipped to a top-left origin.
func draw(_ image: CGImage, in rect: CGRect, on context: CGContext) {
    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: 1, y: -1)
    context.draw(image, in: CGRect(origin: .zero, size: rect.size))
    context.restoreGState()
}

/// Average color of an image's leftmost pixel columns, used to match a region capture's background.
func edgeColor(of image: CGImage) -> CGColor? {
    guard let edge = image.cropping(to: CGRect(x: 0, y: 0, width: min(3, image.width), height: image.height)),
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let data = context.data
    else { return nil }
    context.interpolationQuality = .high
    context.draw(edge, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    let pixel = data.bindMemory(to: UInt8.self, capacity: 4)
    let alpha = CGFloat(pixel[3]) / 255
    guard alpha > 0 else { return nil }
    return color(CGFloat(pixel[0]) / 255 / alpha, CGFloat(pixel[1]) / 255 / alpha, CGFloat(pixel[2]) / 255 / alpha)
}

// MARK: - Wait for the panel

print("Click the \(appName) item in the menu bar, and leave the pointer on it.")
for remaining in stride(from: delay, to: 0, by: -1) {
    print("  capturing in \(remaining)…")
    Thread.sleep(forTimeInterval: 1)
}

let pointer = CGEvent(source: nil)?.location ?? .zero   // global, top-left origin
let windows = onScreenWindows()

guard let panel = windows
    .filter({ $0.owner == appName && $0.bounds.height > 100 })
    .max(by: { $0.bounds.height < $1.bounds.height })
else { fail("the panel isn't open. Run the script again and click the \(appName) item before the countdown ends.") }

// MARK: - Find the menu bar item

/// Short windows above the panel, on the same display. On recent macOS versions menu bar items
/// can be owned by the system rather than the app, so every owner is considered.
let menuBarWindows = windows.filter {
    $0.id != panel.id
        && $0.bounds.height <= 60
        && $0.bounds.width <= 600
        && $0.bounds.minY < panel.bounds.minY
        && $0.bounds.minY >= panel.bounds.minY - 80
        && abs($0.bounds.midX - panel.bounds.midX) < 1200
}
func closestToPanel(_ a: Window, _ b: Window) -> Bool {
    abs(a.bounds.midX - panel.bounds.midX) < abs(b.bounds.midX - panel.bounds.midX)
}
func smallest(_ a: Window, _ b: Window) -> Bool {
    a.bounds.width * a.bounds.height < b.bounds.width * b.bounds.height
}
func nearlyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) <= 3 && abs(a.minY - b.minY) <= 3 && abs(a.width - b.width) <= 6 && abs(a.height - b.height) <= 6
}

let axFrame = accessibilityItemFrame(pid: panel.pid)

enum ItemSource {
    case window(Window, how: String)
    case region(CGRect)
}

let itemSource: ItemSource
if let owned = menuBarWindows.filter({ $0.owner == appName }).min(by: closestToPanel) {
    itemSource = .window(owned, how: "owned by \(appName)")
} else if let named = menuBarWindows.filter({ $0.name.localizedCaseInsensitiveContains(appName) }).min(by: closestToPanel) {
    itemSource = .window(named, how: "named after \(appName)")
} else if let axFrame, let matching = windows.filter({ nearlyEqual($0.bounds, axFrame) }).min(by: smallest) {
    itemSource = .window(matching, how: "matched to the accessibility frame")
} else if let axFrame {
    itemSource = .region(axFrame)
} else if let underPointer = menuBarWindows
    .filter({ $0.bounds.insetBy(dx: -2, dy: -2).contains(pointer) })
    .min(by: smallest) {
    itemSource = .window(underPointer, how: "under the pointer")
} else {
    var report = ["CarrierBar capture report", ""]
    report.append("pointer: x \(Int(pointer.x)) y \(Int(pointer.y))")
    report.append("accessibility permission for Terminal: \(AXIsProcessTrusted() ? "yes" : "no")")
    report.append("accessibility item frame: \(axFrame.map { "\($0)" } ?? "none")")
    report.append("panel: \(panel)")
    report.append("")
    report.append("\(appName) windows:")
    report += windows.filter { $0.owner == appName }.map { "  \($0)" }
    report.append("")
    report.append("windows near the top of the panel's display (any owner):")
    report += windows
        .filter { $0.bounds.minY < panel.bounds.minY + 10 && abs($0.bounds.midX - panel.bounds.midX) < 2000 }
        .sorted { $0.bounds.minX < $1.bounds.minX }
        .map { "  \($0)" }
    let text = report.joined(separator: "\n") + "\n"
    try? FileManager.default.createDirectory(at: debugURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? text.write(to: debugURL, atomically: true, encoding: .utf8)
    print("\n" + text)
    fail("""
    couldn't find the \(appName) menu bar item. A report was saved to \(debugURL.path).
    Giving Terminal Accessibility permission usually fixes this (System Settings › Privacy & Security › Accessibility).
    """)
}

let temporary = FileManager.default.temporaryDirectory
let itemFrame: CGRect
let itemImage: CGImage
var itemBackground: CGColor? = nil

switch itemSource {
case .window(let window, let how):
    print("Menu bar item: \(window), \(how)")
    itemFrame = window.bounds
    itemImage = captureWindow(window, to: temporary.appendingPathComponent("carrierbar-item.png"))
case .region(let frame):
    // No separate window to capture. Take that exact rectangle of the menu bar, and match the
    // strip's color to what's behind it.
    print("Menu bar item: region x \(Int(frame.minX)) y \(Int(frame.minY)) w \(Int(frame.width)) h \(Int(frame.height)), from accessibility")
    itemFrame = frame
    itemImage = captureRegion(frame, to: temporary.appendingPathComponent("carrierbar-item.png"))
    itemBackground = edgeColor(of: itemImage)
}
print("Panel: \(panel)")
let panelImage = captureWindow(panel, to: temporary.appendingPathComponent("carrierbar-panel.png"))
try? FileManager.default.removeItem(at: debugURL)

// MARK: - Compose

let scale = CGFloat(panelImage.width) / panel.bounds.width   // 2 on Retina displays
let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"

let padding: CGFloat = 40
let menuBarTop = itemFrame.minY
let menuBarHeight = max(itemFrame.height, 24)
let content = itemFrame.union(panel.bounds)
let canvas = CGRect(
    x: content.minX - padding,
    y: menuBarTop,
    width: content.width + padding * 2,
    height: content.maxY - menuBarTop + padding
)
func local(_ rect: CGRect) -> CGRect {
    rect.offsetBy(dx: -canvas.minX, dy: -canvas.minY)
}

let pixelWidth = Int((canvas.width * scale).rounded())
let pixelHeight = Int((canvas.height * scale).rounded())
guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fail("couldn't create an image context") }

context.scaleBy(x: scale, y: scale)
context.translateBy(x: 0, y: canvas.height)
context.scaleBy(x: 1, y: -1)   // from here on, points with a top-left origin

// Background
let backgroundColors = isDark
    ? [color(0.15, 0.18, 0.28), color(0.07, 0.08, 0.13)]
    : [color(0.80, 0.86, 0.95), color(0.94, 0.95, 0.98)]
if let gradient = CGGradient(colorsSpace: space, colors: backgroundColors as CFArray, locations: [0, 1]) {
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: canvas.height), options: [])
}

// Menu bar strip with only the CarrierBar item in it
let stripColor = itemBackground ?? (isDark ? color(0.09, 0.10, 0.13, 0.82) : color(1, 1, 1, 0.78))
context.setFillColor(stripColor)
context.fill(CGRect(x: 0, y: 0, width: canvas.width, height: menuBarHeight))
context.setFillColor(isDark ? color(1, 1, 1, 0.06) : color(0, 0, 0, 0.08))
context.fill(CGRect(x: 0, y: menuBarHeight - 0.5, width: canvas.width, height: 0.5))
draw(itemImage, in: local(itemFrame), on: context)

// Panel with a soft shadow. Shadow offsets are in pixels, with y pointing up.
context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -10 * scale),
    blur: 30 * scale,
    color: color(0, 0, 0, isDark ? 0.55 : 0.28)
)
draw(panelImage, in: local(panel.bounds), on: context)
context.restoreGState()

// MARK: - Save

guard let result = context.makeImage() else { fail("couldn't render the image") }
try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fail("couldn't write \(outputPath)")
}
let dpi = 72 * scale
let properties: [String: Any] = [
    kCGImagePropertyDPIWidth as String: dpi,
    kCGImagePropertyDPIHeight as String: dpi,
]
CGImageDestinationAddImage(destination, result, properties as CFDictionary)
guard CGImageDestinationFinalize(destination) else { fail("couldn't write \(outputPath)") }

print("Saved \(outputPath) (\(pixelWidth) × \(pixelHeight) px, \(isDark ? "dark" : "light") appearance)")
