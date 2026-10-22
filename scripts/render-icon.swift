// Draws an SVG at 1024 pixels on an opaque ground, for the iOS app icon. From the repository root:
// swiftc -O scripts/render-icon.swift -o /tmp/render-icon && /tmp/render-icon design/logo.svg App/Assets.xcassets/AppIcon.appiconset/icon-1024.png 101010
import AppKit
let args = CommandLine.arguments
guard let image = NSImage(contentsOfFile: args[1]) else { fatalError("can't read \(args[1])") }
let hex = Int(args[3], radix: 16)!
let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
var rect = CGRect(x: 0, y: 0, width: size, height: size)
let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
context.draw(cg, in: rect)
let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
