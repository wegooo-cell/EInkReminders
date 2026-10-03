import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO

// Layout study for a third 400×300 NOTE4 standby view. The photo is sample
// content only; the eventual on-device image will come from the user's upload.
private let width = 400
private let height = 300
private let sampleURL = URL(fileURLWithPath: CommandLine.arguments[1])
private let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
private let imageSource = CGImageSourceCreateWithURL(sampleURL as CFURL, nil)!
private let photo = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)!
private let smallFontName: String = {
    guard let path = ProcessInfo.processInfo.environment["EINK_PIXEL_FONT_16_PATH"],
          FileManager.default.fileExists(atPath: path) else { return "HiraginoSansGB-W3" }
    let url = URL(fileURLWithPath: path) as CFURL
    guard CTFontManagerRegisterFontsForURL(url, .process, nil) else { return "HiraginoSansGB-W3" }
    return "WenQuanYiBitmapSong16px"
}()

private func draw(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat,
                  fontName: String, in context: CGContext) {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String):
            CTFontCreateWithName(fontName as CFString, size, nil),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String):
            CGColor(gray: 1, alpha: 1)
    ]))
    context.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, context)
}

var pixels = [UInt8](repeating: 0, count: width * height)
let context = CGContext(data: &pixels, width: width, height: height,
                        bitsPerComponent: 8, bytesPerRow: width,
                        space: CGColorSpaceCreateDeviceGray(),
                        bitmapInfo: CGImageAlphaInfo.none.rawValue)!
context.setShouldAntialias(false)
context.setShouldSmoothFonts(false)
context.setAllowsFontSmoothing(false)
context.interpolationQuality = .high
context.setFillColor(gray: 0, alpha: 1)
context.fill(CGRect(x: 0, y: 0, width: width, height: height))

// The image top aligns with the city heading; its bottom aligns with the
// reminder due line. Extra space above and below makes it less portrait-like.
let tile = CGRect(x: 15, y: 41, width: 184, height: 216)
let corner: CGFloat = 18
context.saveGState()
context.addPath(CGPath(roundedRect: tile, cornerWidth: corner,
                       cornerHeight: corner, transform: nil))
context.clip()
let scale = max(tile.width / CGFloat(photo.width), tile.height / CGFloat(photo.height))
let drawn = CGRect(x: tile.midX - CGFloat(photo.width) * scale / 2,
                   y: tile.midY - CGFloat(photo.height) * scale / 2,
                   width: CGFloat(photo.width) * scale,
                   height: CGFloat(photo.height) * scale)
context.draw(photo, in: drawn)
context.restoreGState()

draw("广州", x: 210, y: 234, size: 26,
     fontName: "PingFangSC-Semibold", in: context)
draw("29°", x: 207, y: 139, size: 101,
     fontName: "HelveticaNeue-Medium", in: context)
draw("下一个提醒 写视频脚本", x: 210, y: 66, size: 16,
     fontName: smallFontName, in: context)
draw("今天 14:30", x: 210, y: 41, size: 16,
     fontName: smallFontName, in: context)

// Match the device's one-bit image path: ordered dither is confined to the
// photograph while exact white typography stays crisp on the black panel.
let bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
for y in 0..<height {
    for x in 0..<width {
        let index = y * width + x
        let threshold = x < 202
            ? (CGFloat(bayer[(y % 4) * 4 + x % 4]) + 0.5) * 255 / 16
            : 128
        pixels[index] = CGFloat(pixels[index]) >= threshold ? 255 : 0
    }
}
let provider = CGDataProvider(data: Data(pixels) as CFData)!
let result = CGImage(width: width, height: height,
                     bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                     space: CGColorSpaceCreateDeviceGray(),
                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                     provider: provider, decode: nil, shouldInterpolate: false,
                     intent: .defaultIntent)!
let png = NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:])!
try png.write(to: outputURL, options: .atomic)
print("Wrote 400×300 monochrome standby preview to \(outputURL.path)")
