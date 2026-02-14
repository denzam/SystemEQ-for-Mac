#!/usr/bin/env swift

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// App icon generator - creates the sound wave icon in blue color
// Run: swift generate_app_icon.swift

let sizes: [(name: String, size: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024)
]

// Blue color (RGB: 51, 133, 255 - nice vibrant blue)
let blueColor = CGColor(red: 0.2, green: 0.52, blue: 1.0, alpha: 1.0)

func drawIcon(in context: CGContext, size: CGFloat) {
    let center = CGPoint(x: size / 2, y: size / 2)
    let outerRadius = size * 0.40
    let strokeWidth = size * 0.035
    
    // Background - dark gradient
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let darkColor1 = CGColor(colorSpace: colorSpace, components: [0.12, 0.12, 0.14, 1.0])!
    let darkColor2 = CGColor(colorSpace: colorSpace, components: [0.08, 0.08, 0.10, 1.0])!
    
    let backgroundGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [darkColor1, darkColor2] as CFArray,
        locations: [0.0, 1.0]
    )!
    
    // Draw rounded rectangle background
    let cornerRadius = size * 0.22
    let bgRect = CGRect(x: 0, y: 0, width: size, height: size)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    
    context.saveGState()
    context.addPath(bgPath)
    context.clip()
    context.drawLinearGradient(backgroundGradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
    context.restoreGState()
    
    // Circle outline
    context.setStrokeColor(blueColor)
    context.setLineWidth(strokeWidth)
    context.addArc(center: center, radius: outerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.strokePath()
    
    // Sound wave bars - 5 bars with varying heights
    let barWidth = size * 0.055
    let barSpacing = size * 0.09
    let barHeights: [CGFloat] = [0.14, 0.26, 0.38, 0.26, 0.14]
    
    let totalWidth = CGFloat(barHeights.count - 1) * barSpacing
    let startX = center.x - totalWidth / 2
    
    context.setFillColor(blueColor)
    
    for (index, relativeHeight) in barHeights.enumerated() {
        let barHeight = size * relativeHeight
        let x = startX + CGFloat(index) * barSpacing - barWidth / 2
        let y = center.y - barHeight / 2
        
        let barRect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
        let barPath = CGPath(roundedRect: barRect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
        context.addPath(barPath)
        context.fillPath()
    }
}

func generateAndSaveIcon(size: Int, to path: String) -> Bool {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        print("Failed to create context for size \(size)")
        return false
    }
    
    drawIcon(in: context, size: CGFloat(size))
    
    guard let image = context.makeImage() else {
        print("Failed to create image for size \(size)")
        return false
    }
    
    let url = URL(fileURLWithPath: path)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        print("Failed to create destination for \(path)")
        return false
    }
    
    CGImageDestinationAddImage(destination, image, nil)
    
    if CGImageDestinationFinalize(destination) {
        print("✅ Saved: \(path)")
        return true
    } else {
        print("❌ Failed to save: \(path)")
        return false
    }
}

// Main
let scriptPath = URL(fileURLWithPath: #file).deletingLastPathComponent().path
let outputDir = "\(scriptPath)/../SystemEQ for Mac/Assets.xcassets/AppIcon.appiconset"

// Create output directory if needed
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

print("🎨 Generating app icons...")
print("📁 Output directory: \(outputDir)\n")

var successCount = 0
for (name, size) in sizes {
    let path = "\(outputDir)/\(name).png"
    if generateAndSaveIcon(size: size, to: path) {
        successCount += 1
    }
}

// Update Contents.json
let contentsJson = """
{
  "images" : [
    {
      "filename" : "icon_16x16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_16x16@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_32x32@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_128x128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_128x128@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_256x256@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_512x512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

let contentsPath = "\(outputDir)/Contents.json"
try? contentsJson.write(toFile: contentsPath, atomically: true, encoding: .utf8)
print("Updated: \(contentsPath)")

print("\n✅ App icons generated successfully!")
print("Rebuild the project in Xcode to see the new icon.")
