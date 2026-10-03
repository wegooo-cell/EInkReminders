import AppKit
import CoreGraphics
import Foundation

// Reconstruct exactly what the firmware composes from the on-device asset and
// Mac-generated patches, without relying on the old hand-drawn proposal.
let photo = [UInt8](try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let weather = [UInt8](try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
let reminder = [UInt8](try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])))
let due = [UInt8](try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[4])))
let output = URL(fileURLWithPath: CommandLine.arguments[5])
let width = 400, height = 300
var pixels = [UInt8](repeating: 0, count: width * height)
func draw(_ packed: [UInt8], width patchWidth: Int, height patchHeight: Int,
          x: Int, y: Int, text: Bool = false) {
    precondition(packed.count == patchWidth * patchHeight / 8)
    for row in 0..<patchHeight {
        for column in 0..<patchWidth {
            let bit = row * patchWidth + column
            let set = packed[bit / 8] & (0x80 >> (bit % 8)) != 0
            if set != text { pixels[(y + row) * width + x + column] = 255 }
        }
    }
}
draw(photo, width: 184, height: 216, x: 15, y: 43)
draw(weather, width: 190, height: 140, x: 207, y: 40)
draw(reminder, width: 184, height: 22, x: 210, y: 216, text: true)
draw(due, width: 112, height: 22, x: 210, y: 242, text: true)
let provider = CGDataProvider(data: Data(pixels) as CFData)!
let image = CGImage(width: width, height: height, bitsPerComponent: 8,
                    bitsPerPixel: 8, bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: false,
                    intent: .defaultIntent)!
let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
try png.write(to: output, options: .atomic)
print(output.path)
