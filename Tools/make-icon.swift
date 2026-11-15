import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let iconset = root.appendingPathComponent("dist/s-mpc.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
NSColor(calibratedRed: 0.72, green: 0.95, blue: 0.42, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 30, y: 30, width: 964, height: 964),
             xRadius: 225, yRadius: 225).fill()
NSColor(calibratedRed: 0.09, green: 0.15, blue: 0.12, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 120, y: 120, width: 784, height: 784),
             xRadius: 184, yRadius: 184).fill()

let letter = "m" as NSString
let font = NSFont.systemFont(ofSize: 700, weight: .heavy)
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor(calibratedRed: 0.72, green: 0.95, blue: 0.42, alpha: 1)
]
let bounds = letter.size(withAttributes: attributes)
letter.draw(at: NSPoint(x: (size - bounds.width) / 2 - 18,
                         y: (size - bounds.height) / 2 - 2), withAttributes: attributes)
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let representation = NSBitmapImageRep(data: tiff),
      let png = representation.representation(using: .png, properties: [:]) else {
    fatalError("Could not render app icon")
}
let base = root.appendingPathComponent("dist/s-mpc-icon-1024.png")
try png.write(to: base)

for (pixels, name) in [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")
] {
    let destination = iconset.appendingPathComponent(name)
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    task.arguments = ["-z", String(pixels), String(pixels), base.path, "--out", destination.path]
    task.standardOutput = FileHandle.nullDevice
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else { fatalError("sips failed for \(name)") }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
try FileManager.default.removeItem(at: iconset)
