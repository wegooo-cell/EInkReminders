import AppKit
import CoreGraphics
import CoreText
import Foundation

private let panelWidth = 400
private let panelHeight = 300
private let frameBytes = panelWidth * panelHeight / 8
private let referenceClockFont: String? = {
    guard let path = ProcessInfo.processInfo.environment["EINK_REFERENCE_FONT_PATH"],
          FileManager.default.fileExists(atPath: path) else { return nil }
    var error: Unmanaged<CFError>?
    let url = URL(fileURLWithPath: path) as NSURL
    guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else { return nil }
    // Preview reference only. The source font is copyrighted and is not bundled.
    return "AFCamberwell-One"
}()
private let pixelFontsAvailable: Bool = {
    let variables = ["EINK_PIXEL_FONT_14_PATH", "EINK_PIXEL_FONT_16_PATH"]
    for variable in variables {
        guard let path = ProcessInfo.processInfo.environment[variable],
              FileManager.default.fileExists(atPath: path) else { return false }
        var error: Unmanaged<CFError>?
        let url = URL(fileURLWithPath: path) as NSURL
        guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else { return false }
    }
    return true
}()

private func font(_ size: CGFloat, bold: Bool = false, italic: Bool = false,
                  monospace: Bool = false, condensed: Bool = false) -> CTFont {
    if condensed {
        return CTFontCreateWithName((referenceClockFont ?? "HelveticaNeue-CondensedBlack") as CFString, size, nil)
    }
    if monospace {
        // FreeMonoBold is used by the referenced Raspberry Pi clock. Courier
        // New Bold provides a locally available, similarly spaced preview.
        return CTFontCreateWithName("CourierNewPS-BoldMT" as CFString, size, nil)
    }
    if italic {
        let base = NSFont.systemFont(ofSize: size, weight: .black)
        let rounded = base.fontDescriptor.withDesign(.rounded)!
        return NSFont(descriptor: rounded, size: size)! as CTFont
    }
    let name = bold ? "PingFangSC-Semibold" : "PingFangSC-Regular"
    return CTFontCreateWithName(name as CFString, size, nil)
}

private func textWidth(_ value: String, size: CGFloat, bold: Bool = false,
                       italic: Bool = false, monospace: Bool = false,
                       condensed: Bool = false) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font(size, bold: bold, italic: italic, monospace: monospace, condensed: condensed)]
    return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes)), nil, nil, nil))
}

private func draw(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat,
                  bold: Bool = false, italic: Bool = false, monospace: Bool = false,
                  condensed: Bool = false,
                  white: Bool = false, gray: CGFloat? = nil, in context: CGContext) {
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font(size, bold: bold, italic: italic, monospace: monospace, condensed: condensed),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: gray ?? (white ? 1 : 0), alpha: 1)
    ]
    context.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes)), context)
}

private func drawSmall(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat,
                       tracking: CGFloat = 1.5, pixel: Bool = false,
                       in context: CGContext) {
    let fontName = pixel
        ? (size >= 16 ? "WenQuanYiBitmapSong16px" : "WenQuanYiBitmapSong14px")
        : "HiraginoSansGB-W3"
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(fontName as CFString, size, nil),
        .kern: tracking,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
    ]
    context.saveGState()
    context.setShouldAntialias(false)
    context.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes)), context)
    context.restoreGState()
}

private func drawCentered(_ value: String, centerX: CGFloat, y: CGFloat, size: CGFloat,
                          bold: Bool = false, italic: Bool = false, in context: CGContext) {
    draw(value, x: centerX - textWidth(value, size: size, bold: bold, italic: italic) / 2,
         y: y, size: size, bold: bold, italic: italic, in: context)
}

private func save(_ pixels: [UInt8], as name: String, in directory: URL,
                  dither: Bool = false) throws {
    var binary = pixels
    let bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
    for index in binary.indices {
        let threshold = dither
            ? (CGFloat(bayer[(index / panelWidth % 4) * 4 + index % panelWidth % 4]) + 0.5) * 255 / 16
            : 128
        binary[index] = CGFloat(binary[index]) < threshold ? 0 : 255
    }
    let provider = CGDataProvider(data: Data(binary) as CFData)!
    let image = CGImage(width: panelWidth, height: panelHeight,
                        bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: panelWidth,
                        space: CGColorSpaceCreateDeviceGray(),
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: false,
                        intent: .defaultIntent)!
    let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try png.write(to: directory.appendingPathComponent(name), options: .atomic)
}

private func withFrame(_ allFrames: Data, index: Int, name: String, directory: URL,
                       dither: Bool = false,
                       drawing: (CGContext) -> Void) throws {
    let frame = allFrames.subdata(in: index * frameBytes..<(index + 1) * frameBytes)
    // CGContext uses caller-owned bytes. Keep the buffer alive until export.
    var pixels = [UInt8](repeating: 255, count: panelWidth * panelHeight)
    let packed = [UInt8](frame)
    for position in pixels.indices where packed[position / 8] & UInt8(0x80 >> (position % 8)) == 0 {
        pixels[position] = 0
    }
    let context = CGContext(data: &pixels, width: panelWidth, height: panelHeight,
                            bitsPerComponent: 8, bytesPerRow: panelWidth,
                            space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    context.setShouldAntialias(false)
    context.setShouldSmoothFonts(false)
    context.setAllowsFontSmoothing(false)
    context.interpolationQuality = .none
    drawing(context)
    try save(pixels, as: name, in: directory, dither: dither)
}

let framesURL = URL(fileURLWithPath: CommandLine.arguments[1])
let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let allFrames = try Data(contentsOf: framesURL)
precondition(allFrames.count == 50 * frameBytes)

let now = Date()
let calendar = Calendar.current
let today = calendar.component(.day, from: now)
let month = calendar.component(.month, from: now)
let year = calendar.component(.year, from: now)
let monthNames = ["一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月"]
let weekdayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
let weekday = weekdayNames[calendar.component(.weekday, from: now) - 1]
let timeFormatter = DateFormatter()
timeFormatter.locale = Locale(identifier: "en_US_POSIX")
timeFormatter.dateFormat = "HH:mm"
let currentTime = ProcessInfo.processInfo.environment["EINK_PREVIEW_TIME"] ?? timeFormatter.string(from: now)

try withFrame(allFrames, index: 11, name: "01-view-picker.png", directory: directory) { _ in }
try withFrame(allFrames, index: 10, name: "09-settings-standby-black.png", directory: directory) { _ in }
try withFrame(allFrames, index: 49, name: "10-settings-standby-white.png", directory: directory) { _ in }

try withFrame(allFrames, index: 39, name: "02-reminders-picker.png", directory: directory) { context in
    for (value, x, y) in [("3", CGFloat(177), CGFloat(183)), ("8", 371, 183), ("6", 177, 86)] {
        draw(value, x: x - textWidth(value, size: 22, bold: true), y: y, size: 22, bold: true, in: context)
    }
}

func drawStandbyClock(_ value: String, centerX: CGFloat, baseline: CGFloat,
                      size: CGFloat, white: Bool = false, gray: CGFloat? = nil,
                      visiblePositions: Set<Int>? = nil,
                      context: CGContext) {
    if size <= 100 {
        let targetWidth: CGFloat = 120
        let naturalWidth = textWidth(value, size: size, monospace: true)
        context.saveGState()
        context.translateBy(x: centerX - targetWidth / 2, y: baseline)
        context.scaleBy(x: targetWidth / naturalWidth, y: 1)
        draw(value, x: 0, y: 0, size: size, monospace: true, white: white, gray: gray, in: context)
        context.restoreGState()
        return
    }

    // The linked StandBy clock uses SF Pro Rounded Black with independently
    // rotated and vertically stretched digits. Recreate that optical rhythm
    // rather than shearing the whole number as a single line.
    let glyphs = value.map(String.init)
    let widths = glyphs.map { textWidth($0, size: size, italic: true) }
    // Clock masks are stored independently for hours and minutes. Keep every
    // character's origin fixed to the approved 13:31 layout; otherwise the
    // proportional font moves a digit across the atlas boundary when its
    // neighbor changes, cutting off its edge on the device.
    let slotWidths = "13:31".map { textWidth(String($0), size: size, italic: true) }
    let tracking: CGFloat = -14
    let naturalWidth = slotWidths.reduce(0, +) + CGFloat(glyphs.count - 1) * tracking
    let targetWidth: CGFloat = 340
    context.saveGState()
    context.translateBy(x: centerX - targetWidth / 2, y: baseline)
    context.scaleBy(x: targetWidth / naturalWidth, y: 1)
    var cursor: CGFloat = 0
    var digitIndex = 0
    let angles: [CGFloat] = [-5, 1, 5, -2]
    let verticalScales: [CGFloat] = [1.20, 1.10, 1.15, 1.15]
    for (index, glyph) in glyphs.enumerated() {
        context.saveGState()
        if glyph != ":" {
            let transformIndex = digitIndex % angles.count
            let pivotX = cursor + widths[index] / 2
            let pivotY = size * 0.43
            context.translateBy(x: pivotX, y: pivotY)
            context.rotate(by: angles[transformIndex] * .pi / 180)
            context.scaleBy(x: 1, y: verticalScales[transformIndex])
            context.translateBy(x: -pivotX, y: -pivotY)
            digitIndex += 1
        }
        if visiblePositions?.contains(index) ?? true {
            draw(glyph, x: cursor, y: 0, size: size, italic: true,
                 white: white, gray: gray, in: context)
        }
        context.restoreGState()
        cursor += slotWidths[index] + tracking
    }
    context.restoreGState()
}

func drawBlackClock(_ context: CGContext, pixel: Bool = false,
                    time value: String = currentTime,
                    clockPositions: Set<Int>? = nil) {
    context.setFillColor(gray: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
    context.saveGState()
    context.translateBy(x: 6, y: -4)
    drawStandbyClock(value, centerX: 200, baseline: 100, size: 180,
                     gray: 0.68, visiblePositions: clockPositions, context: context)
    context.restoreGState()
    drawStandbyClock(value, centerX: 200, baseline: 100, size: 180,
                     white: true, visiblePositions: clockPositions, context: context)
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 20, y: 43, width: 360, height: 1))
    if pixel {
        drawSmall("下一个提醒", x: 20, y: 13, size: 18, tracking: 1, pixel: true, in: context)
        drawSmall("写视频脚本", x: 128, y: 13, size: 18, tracking: 2, pixel: true, in: context)
        drawSmall("今天 14:30", x: 280, y: 14, size: 16, tracking: 1, pixel: true, in: context)
    } else {
        drawSmall("下一个提醒", x: 20, y: 14, size: 15, in: context)
        drawSmall("写视频脚本", x: 126, y: 13, size: 18, in: context)
        drawSmall("今天 14:30", x: 285, y: 14, size: 15, in: context)
    }
}

try withFrame(allFrames, index: 43, name: "04-standby-large.png", directory: directory, dither: true) { context in
    drawBlackClock(context)
}

func drawTallClock(_ context: CGContext, pixel: Bool = false, time value: String = currentTime,
                   day: Int = today, weekdayText: String = weekday,
                   clockPositions: Set<Int>? = nil) {
    context.setFillColor(gray: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
    let clockFont = font(240, condensed: true)
    context.saveGState()
    context.translateBy(x: 0, y: 22)
    context.scaleBy(x: 1, y: 1.35)
    // The reference's 20:24 has five distinct optical columns. Keep their
    // centers fixed across all times, and size the *visible ink* of each glyph
    // independently. That preserves the open gaps even for wide pairs (20,
    // 88, etc.) while leaving the narrower "1" narrow.
    let centers: [CGFloat] = [35, 95, 140, 187, 249]
    let digitWidths: [Character: CGFloat] = [
        "0": 49, "1": 35, "2": 54, "3": 51, "4": 52,
        "5": 51, "6": 50, "7": 48, "8": 50, "9": 50, ":": 20
    ]
    for (index, character) in value.enumerated() where clockPositions?.contains(index) ?? true {
        var utf16 = UniChar(character.utf16.first!)
        var glyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(clockFont, &utf16, &glyph, 1) else { continue }
        let bounds = CTFontGetBoundingRectsForGlyphs(clockFont, .horizontal, &glyph, nil, 1)
        guard bounds.width > 0, let width = digitWidths[character] else { continue }
        let scale = width / bounds.width
        context.saveGState()
        context.translateBy(x: centers[index] - width / 2 - bounds.minX * scale, y: 0)
        context.scaleBy(x: scale, y: 1)
        draw(String(character), x: 0, y: 0, size: 240,
             condensed: true, white: true, in: context)
        context.restoreGState()
    }
    context.restoreGState()
    draw("\(day)", x: 285, y: 239, size: 30, white: true, in: context)
    if pixel {
        drawSmall(weekdayText, x: 329, y: 240, size: 16, tracking: 1, pixel: true, in: context)
    } else {
        draw(weekdayText, x: 329, y: 239, size: 18, white: true, in: context)
    }
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 285, y: 101, width: 94, height: 1))
    if pixel {
        drawSmall("下一个提醒", x: 285, y: 77, size: 18, tracking: 1, pixel: true, in: context)
        drawSmall("写视频脚本", x: 282, y: 47, size: 18, tracking: 2, pixel: true, in: context)
        drawSmall("今天 14:30", x: 285, y: 23, size: 16, tracking: 1, pixel: true, in: context)
    } else {
        drawSmall("下一个提醒", x: 285, y: 78, size: 14, in: context)
        drawSmall("写视频脚本", x: 285, y: 46, size: 18, in: context)
        drawSmall("今天 14:30", x: 285, y: 23, size: 14, in: context)
    }
}

try withFrame(allFrames, index: 44, name: "05-standby-calendar.png", directory: directory) { context in
    drawTallClock(context)
}

try withFrame(allFrames, index: 45, name: "06-standby-hours.png", directory: directory, dither: true) { context in
    drawBlackClock(context)
}

if pixelFontsAvailable {
    try withFrame(allFrames, index: 43, name: "04-standby-large-pixel.png", directory: directory, dither: true) { context in
        drawBlackClock(context, pixel: true)
    }
    try withFrame(allFrames, index: 44, name: "05-standby-tall-pixel.png", directory: directory) { context in
        drawTallClock(context, pixel: true)
    }
}

print("Wrote \(pixelFontsAvailable ? "eight" : "six") 400×300 1-bit approval previews to \(directory.path)")

if CommandLine.arguments.count > 3 {
    // Device clock assets use the *same* drawing functions, fonts, transforms,
    // and dithering as the approved screenshots. Separate hour/minute masks
    // keep the complete 24-hour clock below the firmware partition limit.
    struct Region { let x: Int; let y: Int; let width: Int; let height: Int }
    let regions: [(Region, Region)] = [
        (Region(x: 20, y: 40, width: 200, height: 200),
         Region(x: 184, y: 40, width: 216, height: 200)),
        (Region(x: 0, y: 16, width: 160, height: 268),
         Region(x: 152, y: 16, width: 128, height: 268))
    ]
    let bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
    func mask(style: Int, value: String, region: Region,
              clockPositions: Set<Int>? = nil,
              day: Int = today, weekdayText: String = weekday) -> Data {
        var pixels = [UInt8](repeating: 0, count: panelWidth * panelHeight)
        let context = CGContext(data: &pixels, width: panelWidth, height: panelHeight,
                                bitsPerComponent: 8, bytesPerRow: panelWidth,
                                space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setShouldAntialias(false)
        context.setShouldSmoothFonts(false)
        context.setAllowsFontSmoothing(false)
        context.interpolationQuality = .none
        if style == 0 {
            drawBlackClock(context, pixel: true, time: value,
                           clockPositions: clockPositions)
        }
        else { drawTallClock(context, pixel: true, time: value,
                             day: day, weekdayText: weekdayText,
                             clockPositions: clockPositions) }
        var packed = [UInt8](repeating: 0, count: region.width * region.height / 8)
        for row in 0..<region.height { for column in 0..<region.width {
            let x = region.x + column, y = region.y + row
            let threshold: CGFloat = style == 0
                ? (CGFloat(bayer[(y % 4) * 4 + x % 4]) + 0.5) * 255 / 16 : 128
            if CGFloat(pixels[y * panelWidth + x]) >= threshold {
                let bit = row * region.width + column
                packed[bit / 8] |= UInt8(0x80 >> (bit % 8))
            }
        }}
        return Data(packed)
    }
    var atlas = Data()
    for style in 0..<2 {
        for hour in 0..<24 {
            atlas.append(mask(style: style, value: String(format: "%02d:31", hour),
                              region: regions[style].0,
                              clockPositions: [0, 1, 2]))
        }
        for minute in 0..<60 {
            atlas.append(mask(style: style, value: String(format: "13:%02d", minute),
                              region: regions[style].1,
                              clockPositions: [3, 4]))
        }
    }
    let dateRegion = Region(x: 282, y: 28, width: 48, height: 48)
    let weekdayRegion = Region(x: 329, y: 28, width: 48, height: 48)
    for day in 1...31 {
        atlas.append(mask(style: 1, value: "13:31", region: dateRegion,
                          day: day, weekdayText: ""))
    }
    for label in weekdayNames {
        atlas.append(mask(style: 1, value: "13:31", region: weekdayRegion,
                          weekdayText: label))
    }
    let output = URL(fileURLWithPath: CommandLine.arguments[3])
    try atlas.write(to: output, options: .atomic)
    print("Wrote approved standby clock masks (\(atlas.count) bytes) to \(output.path)")

    let atlasBytes = [UInt8](atlas)
    for style in 0..<2 {
        let frame = [UInt8](allFrames.subdata(in: (43 + style) * frameBytes..<(44 + style) * frameBytes))
        var composite = [UInt8](repeating: 0, count: panelWidth * panelHeight)
        for pixel in composite.indices where frame[pixel / 8] & UInt8(0x80 >> (pixel % 8)) != 0 {
            composite[pixel] = 255
        }
        let styleOffset = style == 0 ? 0 : 24 * 5000 + 60 * 5400
        let hourBytes = regions[style].0.width * regions[style].0.height / 8
        let minuteBytes = regions[style].1.width * regions[style].1.height / 8
        let sampleHour = Int(currentTime.prefix(2)) ?? 13
        let sampleMinute = Int(currentTime.suffix(2)) ?? 31
        let selectedMasks = [
            (regions[style].0, styleOffset + sampleHour * hourBytes),
            (regions[style].1, styleOffset + 24 * hourBytes + sampleMinute * minuteBytes)
        ]
        var clockLeft = panelWidth
        var clockRight = -1
        if style == 0 {
            for (region, offset) in selectedMasks {
                for row in 0..<region.height { for column in 0..<region.width {
                    let bit = row * region.width + column
                    if atlasBytes[offset + bit / 8] & UInt8(0x80 >> (bit % 8)) != 0 {
                        clockLeft = min(clockLeft, region.x + column)
                        clockRight = max(clockRight, region.x + column)
                    }
                }}
            }
        }
        let shift = clockRight >= clockLeft
            ? max(-clockLeft, min(panelWidth - 1 - clockRight,
                                  (panelWidth - 1 - clockLeft - clockRight) / 2))
            : 0
        for (region, offset) in selectedMasks {
            for row in 0..<region.height { for column in 0..<region.width {
                let bit = row * region.width + column
                if atlasBytes[offset + bit / 8] & UInt8(0x80 >> (bit % 8)) != 0 {
                    composite[(region.y + row) * panelWidth + region.x + column + shift] = 255
                }
            }}
        }
        let directName = style == 0 ? "04-standby-large-pixel.png" : "05-standby-tall-pixel.png"
        if let direct = NSBitmapImageRep(data: try Data(contentsOf: directory.appendingPathComponent(directName))) {
            let clockBounds = style == 0 ? CGRect(x: 0, y: 40, width: 400, height: 200)
                                         : CGRect(x: 0, y: 16, width: 280, height: 268)
            var mismatches = 0
            for y in Int(clockBounds.minY)..<Int(clockBounds.maxY) {
                for x in Int(clockBounds.minX)..<Int(clockBounds.maxX) {
                    let sourceX = x - shift
                    let expected = sourceX >= 0 && sourceX < panelWidth &&
                        (direct.colorAt(x: sourceX, y: y)?.whiteComponent ?? 0) >= 0.5
                    let actual = composite[y * panelWidth + x] >= 128
                    if expected != actual { mismatches += 1 }
                }
            }
            print("\(style == 0 ? "large" : "tall") \(currentTime) clock shift: \(shift), mask mismatches: \(mismatches)")
            precondition(mismatches == 0, "Clock mask does not match the designed digits")
            if style == 0 {
                // Add the dynamic footer from the approved preview to the
                // exact on-device mask composite for a full-screen review.
                var full = composite
                for y in 240..<panelHeight { for x in 0..<panelWidth {
                    full[y * panelWidth + x] =
                        (direct.colorAt(x: x, y: y)?.whiteComponent ?? 0) >= 0.5 ? 255 : 0
                }}
                let suffix = currentTime.replacingOccurrences(of: ":", with: "-")
                try save(full, as: "device-clock-large-full-\(suffix).png", in: directory)
                try save(full.map { 255 - $0 },
                         as: "device-clock-large-inverted-\(suffix).png", in: directory)
            }
        }
        let suffix = currentTime.replacingOccurrences(of: ":", with: "-")
        try save(composite, as: style == 0 ? "device-clock-large-\(suffix).png" : "device-clock-tall-\(suffix).png",
                 in: directory)
        if style == 1 {
            let dateBase = 829_920
            for (offset, x) in [(dateBase + 22 * 288, 282),
                                (dateBase + (31 + 3) * 288, 329)] {
                for row in 0..<48 { for column in 0..<48 {
                    let bit = row * 48 + column
                    if atlasBytes[offset + bit / 8] & UInt8(0x80 >> (bit % 8)) != 0 {
                        composite[(28 + row) * panelWidth + x + column] = 255
                    }
                }}
            }
            if let direct = NSBitmapImageRep(data: try Data(contentsOf:
                directory.appendingPathComponent("05-standby-tall-pixel.png"))) {
                for y in 200..<panelHeight { for x in 280..<panelWidth {
                    composite[y * panelWidth + x] =
                        (direct.colorAt(x: x, y: y)?.whiteComponent ?? 0) >= 0.5 ? 255 : 0
                }}
            }
            try save(composite, as: "device-clock-tall-full-\(suffix).png", in: directory)
            try save(composite.map { 255 - $0 },
                     as: "device-clock-tall-inverted-\(suffix).png", in: directory)
        }
        if let patchDirectory = ProcessInfo.processInfo.environment["EINK_STANDBY_PATCH_PREVIEW_DIR"] {
            for (file, x, y) in [
                ("standby-title.bin", style == 0 ? 128 : 282, style == 0 ? 267 : 233),
                ("standby-due.bin", style == 0 ? 280 : 285, style == 0 ? 267 : 258)
            ] {
                let patch = [UInt8](try Data(contentsOf: URL(fileURLWithPath: patchDirectory)
                    .appendingPathComponent(file)))
                precondition(patch.count == 112 * 22 / 8)
                for row in 0..<22 { for column in 0..<112 {
                    let bit = row * 112 + column
                    if patch[bit / 8] & UInt8(0x80 >> (bit % 8)) == 0,
                       x + column < panelWidth, y + row < panelHeight {
                        composite[(y + row) * panelWidth + x + column] = 255
                    }
                }}
            }
            try save(composite,
                     as: style == 0 ? "device-complete-large-\(suffix).png" : "device-complete-tall-\(suffix).png",
                     in: directory)
        }
    }
}

// Preview-only antialiasing study for the tall clock. Keep every approved
// element except the large digits byte-for-byte identical to the reference.
do {
    let scale = 4
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("previews/approval-2026-09-23/05-standby-tall-pixel.png")
    guard let reference = NSBitmapImageRep(data: try Data(contentsOf: source)) else {
        fatalError("Missing approved tall clock reference")
    }
    var highResolution = [UInt8](repeating: 0, count: panelWidth * scale * panelHeight * scale)
    let context = CGContext(data: &highResolution, width: panelWidth * scale,
                            height: panelHeight * scale, bitsPerComponent: 8,
                            bytesPerRow: panelWidth * scale,
                            space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)
    context.setShouldSmoothFonts(false)
    context.setAllowsFontSmoothing(false)
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    drawTallClock(context, pixel: true, time: "13:31")
    var coverage = [UInt8](repeating: 0, count: panelWidth * panelHeight)
    for y in 0..<panelHeight { for x in 0..<panelWidth {
        var sum = 0
        for dy in 0..<scale { for dx in 0..<scale {
            sum += Int(highResolution[(y * scale + dy) * panelWidth * scale + x * scale + dx])
        }}
        coverage[y * panelWidth + x] = UInt8(sum / (scale * scale))
    }}
    for (name, ordered) in [("tall-aa-threshold.png", false), ("tall-aa-ordered.png", true)] {
        var pixels = [UInt8](repeating: 0, count: panelWidth * panelHeight)
        let bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
        for y in 0..<panelHeight { for x in 0..<panelWidth {
            let sourceWhite = (reference.colorAt(x: x, y: y)?.whiteComponent ?? 0) >= 0.5
            let threshold = ordered
                ? (CGFloat(bayer[(y % 4) * 4 + x % 4]) + 0.5) * 255 / 16 : 128
            let white = x < 278 && y >= 16 && y < 284
                ? CGFloat(coverage[y * panelWidth + x]) >= threshold : sourceWhite
            pixels[y * panelWidth + x] = white ? 255 : 0
        }}
        try save(pixels, as: name, in: directory)
    }
}
