#!/usr/bin/env swift
import AppKit

let size = NSSize(width: 600, height: 400)
let image = NSImage(size: size)
image.lockFocus()

let bgGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.14, alpha: 1.0),
    NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.24, alpha: 1.0)
])!
bgGradient.draw(in: NSRect(origin: .zero, size: size), angle: 270)

func draw(
    _ text: String,
    at point: NSPoint,
    size fontSize: CGFloat,
    color: NSColor,
    bold: Bool = false,
    align: NSTextAlignment = .left
) {
    let style = NSMutableParagraphStyle()
    style.alignment = align
    let attrs: [NSAttributedString.Key: Any] = [
        .font: bold ? NSFont.boldSystemFont(ofSize: fontSize) : NSFont.systemFont(ofSize: fontSize),
        .foregroundColor: color,
        .paragraphStyle: style
    ]
    (text as NSString).draw(at: point, withAttributes: attrs)
}

let white = NSColor.white
let dim = NSColor(white: 0.75, alpha: 1.0)
let accent = NSColor(calibratedRed: 0.40, green: 0.70, blue: 1.0, alpha: 1.0)
let warn = NSColor(calibratedRed: 1.0, green: 0.75, blue: 0.30, alpha: 1.0)

draw("SystemEQ for Mac", at: NSPoint(x: 30, y: 360), size: 22, color: white, bold: true)
draw("Drag the app to Applications -->", at: NSPoint(x: 30, y: 330), size: 13, color: dim)

let arrowY: CGFloat = 250
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 235, y: arrowY))
arrow.line(to: NSPoint(x: 380, y: arrowY))
arrow.move(to: NSPoint(x: 365, y: arrowY + 12))
arrow.line(to: NSPoint(x: 385, y: arrowY))
arrow.line(to: NSPoint(x: 365, y: arrowY - 12))
accent.setStroke()
arrow.lineWidth = 3
arrow.stroke()

draw("AFTER INSTALL — first launch:", at: NSPoint(x: 30, y: 130), size: 12, color: warn, bold: true)
draw("Right-click the app -> Open -> Open (confirm Gatekeeper)", at: NSPoint(x: 30, y: 108), size: 11, color: white)
draw(
    "If blocked: System Settings -> Privacy & Security -> Open Anyway",
    at: NSPoint(x: 30, y: 90),
    size: 11,
    color: white
)
draw(
    "Read \"README - HOW TO OPEN.txt\" inside this window for details (EN/IT/UK)",
    at: NSPoint(x: 30, y: 65),
    size: 10,
    color: dim
)

draw("Open-source, unsigned. github.com/denzam/SystemEQ-for-Mac", at: NSPoint(x: 30, y: 25), size: 9, color: dim)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to render\n", stderr)
    exit(1)
}

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.png"
try png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
