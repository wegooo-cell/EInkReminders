import AppKit
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let referenceDir = root.appendingPathComponent("previews/approval-2026-09-23")
let patchDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let width = 112, height = 22

for (style, imageName, locations) in [
    ("large", "04-standby-large-pixel.png", [("standby-title.bin", 128, 268), ("standby-due.bin", 280, 268)]),
    ("tall", "05-standby-tall-pixel.png", [("standby-title.bin", 282, 237), ("standby-due.bin", 285, 267)])
] {
    let source = NSBitmapImageRep(data: try Data(contentsOf: referenceDir.appendingPathComponent(imageName)))!
    for (file, originX, originY) in locations {
        let bits = [UInt8](try Data(contentsOf: patchDir.appendingPathComponent(file)))
        var candidates: [(Int, Int, Int)] = []
        for dy in -14...5 { for dx in -4...4 {
            let x = originX + dx, y = originY + dy
            var mismatch = 0
            for row in 0..<height { for column in 0..<width {
                guard x + column >= 0, x + column < 400,
                      y + row >= 0, y + row < 300 else { continue }
                let bit = row * width + column
                let painted = bits[bit / 8] & UInt8(0x80 >> (bit % 8)) == 0
                let reference = (source.colorAt(x: x + column, y: y + row)?.whiteComponent ?? 0) >= 0.5
                if painted != reference { mismatch += 1 }
            }}
            candidates.append((mismatch, x, y))
        }}
        let best = candidates.sorted { $0.0 < $1.0 }.prefix(5)
        print("\(style) \(file): \(best.map { "\($0.0)@\($0.1),\($0.2)" }.joined(separator: ", "))")
    }
    if CommandLine.arguments.count > 2 {
        let generated = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
            .appendingPathComponent(style == "large"
                ? "device-complete-large-13-31.png" : "device-complete-tall-13-31.png")
        let result = NSBitmapImageRep(data: try Data(contentsOf: generated))!
        var mismatches = 0
        for y in 0..<300 { for x in 0..<400 {
            let expected = (source.colorAt(x: x, y: y)?.whiteComponent ?? 0) >= 0.5
            let actual = (result.colorAt(x: x, y: y)?.whiteComponent ?? 0) >= 0.5
            if expected != actual {
                mismatches += 1
                if mismatches <= 10 { print("\(style) mismatch at \(x),\(y)") }
            }
        }}
        print("\(style) complete preview mismatches: \(mismatches) / 120000 pixels")
    }
}
