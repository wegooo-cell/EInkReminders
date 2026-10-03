import AppKit
import CoreGraphics
import Foundation
import ImageIO

// Convert the supplied default picture to the exact same 184×216 1-bit,
// rounded-corner format that the phone upload page generates.
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let binaryOutput = URL(fileURLWithPath: CommandLine.arguments[2])
let previewOutput = URL(fileURLWithPath: CommandLine.arguments[3])
guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
    fatalError("Cannot read source photo")
}
let width = 184, height = 216
var grayscale = [UInt8](repeating: 0, count: width * height)
let context = CGContext(data: &grayscale, width: width, height: height,
                        bitsPerComponent: 8, bytesPerRow: width,
                        space: CGColorSpaceCreateDeviceGray(),
                        bitmapInfo: CGImageAlphaInfo.none.rawValue)!
let factor = max(CGFloat(width) / CGFloat(image.width),
                 CGFloat(height) / CGFloat(image.height))
let drawnWidth = CGFloat(image.width) * factor
let drawnHeight = CGFloat(image.height) * factor
context.interpolationQuality = .high
context.draw(image, in: CGRect(x: (CGFloat(width) - drawnWidth) / 2,
                               y: (CGFloat(height) - drawnHeight) / 2,
                               width: drawnWidth, height: drawnHeight))
let matrix = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
var packed = [UInt8](repeating: 0, count: width * height / 8)
for y in 0..<height {
    for x in 0..<width {
        let cx = x < 18 ? 18 : width - 19
        let cy = y < 18 ? 18 : height - 19
        let inside = (x >= 18 && x < width - 18) ||
            (y >= 18 && y < height - 18) ||
            hypot(Double(x - cx), Double(y - cy)) < 18
        let index = y * width + x
        let contrast = max(0, min(255, (Double(grayscale[index]) - 105) * 2.3))
        let threshold = (Double(matrix[(y % 4) * 4 + x % 4]) + 0.5) * 16
        let white = inside && contrast >= threshold
        if white { packed[index / 8] |= 0x80 >> (index % 8) }
        grayscale[index] = white ? 255 : 0
    }
}
try Data(packed).write(to: binaryOutput, options: .atomic)
let provider = CGDataProvider(data: Data(grayscale) as CFData)!
let result = CGImage(width: width, height: height,
                     bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                     space: CGColorSpaceCreateDeviceGray(),
                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                     provider: provider, decode: nil, shouldInterpolate: false,
                     intent: .defaultIntent)!
let png = NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:])!
try png.write(to: previewOutput, options: .atomic)
print("Wrote \(packed.count) bytes to \(binaryOutput.path)")
