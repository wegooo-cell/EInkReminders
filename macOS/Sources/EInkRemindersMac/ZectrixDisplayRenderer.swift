import CoreGraphics
import CoreText
import Foundation

/// Draws directly at the ZECTRIX NOTE4 native 400×300 resolution.
/// The wire format is MSB first, where 1 is white and 0 is black.
enum ZectrixDisplayRenderer {
    static let width = 400
    static let height = 300
    static let packedByteCount = width * height / 8
    static let alertPatchWidth = 280
    static let alertPatchHeight = 78
    /// Draw at twice the panel resolution and resolve coverage back to one bit.
    /// The NOTE4 still receives the same 15 KB frame, so this costs no device
    /// RAM, radio time, or display power; only the Mac does a little more work.
    private static let renderScale = 2

    /// Artwork for the user's 70% × 26%, centered popup layout. The NOTE4
    /// draws the rounded card locally; this patch supplies crisp Chinese text
    /// and monochrome 👀-style eyes without depending on a device font.
    static func renderAlertPatch(title: String) throws -> Data {
        let sourceWidth = alertPatchWidth * renderScale
        let sourceHeight = alertPatchHeight * renderScale
        var grayscale = [UInt8](repeating: 255, count: sourceWidth * sourceHeight)
        guard let context = CGContext(
            data: &grayscale, width: sourceWidth, height: sourceHeight,
            bitsPerComponent: 8, bytesPerRow: sourceWidth,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { throw DisplayRenderer.RenderError.contextCreationFailed }
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(true)
        context.setAllowsFontSmoothing(true)
        context.scaleBy(x: CGFloat(renderScale), y: CGFloat(renderScale))
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setFillColor(gray: 0, alpha: 1)

        // 57 px eyes in the editor maps to ~37 physical pixels.
        for (x, pupilX) in [(12.0, 22.0), (31.0, 39.0)] {
            context.setLineWidth(1.5)
            context.strokeEllipse(in: CGRect(x: x, y: 23, width: 19, height: 34))
            context.fillEllipse(in: CGRect(x: pupilX, y: 35, width: 7, height: 11))
        }
        draw("到点提醒", at: CGPoint(x: 64, y: 46), size: 14, weight: .bold, in: context)
        draw(clipped(titleWithoutEmoji(title), maxWidth: 134, size: 13, weight: .semibold),
             at: CGPoint(x: 64, y: 25), size: 13, weight: .semibold, in: context)

        // The editor's 30 px circles, 5 px gap, X +4, Y +20 become
        // approximately 20 px circles, 3 px gap and a 3/13 px shift here.
        let centers: [CGFloat] = [225, 252]
        context.setLineWidth(1.4)
        for x in centers {
            context.strokeEllipse(in: CGRect(x: x - 11, y: 18, width: 22, height: 22))
        }
        context.setLineWidth(2)
        context.move(to: CGPoint(x: 220, y: 25)); context.addLine(to: CGPoint(x: 230, y: 35))
        context.move(to: CGPoint(x: 230, y: 25)); context.addLine(to: CGPoint(x: 220, y: 35))
        context.move(to: CGPoint(x: 246, y: 29)); context.addLine(to: CGPoint(x: 251, y: 24))
        context.addLine(to: CGPoint(x: 259, y: 36)); context.strokePath()
        draw("5分钟", at: CGPoint(x: 211, y: 7), size: 8, weight: .medium, in: context)
        draw("完成", at: CGPoint(x: 245, y: 7), size: 8, weight: .medium, in: context)
        return packSupersampledWhitePixels(
            grayscale,
            outputWidth: alertPatchWidth,
            outputHeight: alertPatchHeight
        )
    }

    private static let headerBottom: CGFloat = 244
    private static let contentBottom: CGFloat = 27
    private static let rowHeight: CGFloat = 32
    private static let sectionHeight: CGFloat = 18

    static func render(
        _ reminders: [ReminderItem],
        selectedIndex: Int? = nil,
        view: DeviceReminderView = .today,
        emptyState: ReminderEmptyState = .noItems,
        generatedAt: Date = Date()
    ) throws -> Data {
        // Supersample on the Mac, then resolve glyph coverage to the panel's
        // native 1-bit pixels. This keeps diagonal and curved strokes balanced
        // without sending grayscale or dither noise to the E Ink panel.
        let sourceWidth = width * renderScale
        let sourceHeight = height * renderScale
        var grayscale = [UInt8](repeating: 255, count: sourceWidth * sourceHeight)
        guard let context = CGContext(
            data: &grayscale,
            width: sourceWidth,
            height: sourceHeight,
            bitsPerComponent: 8,
            bytesPerRow: sourceWidth,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { throw DisplayRenderer.RenderError.contextCreationFailed }

        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(true)
        context.setAllowsFontSmoothing(true)
        context.scaleBy(x: CGFloat(renderScale), y: CGFloat(renderScale))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        draw(view.title, at: CGPoint(x: 13, y: 257), size: 39, weight: .bold, in: context)
        drawRightAligned(
            dateLabel(generatedAt), rightEdge: 387, y: 269,
            size: 18, weight: .semibold, in: context
        )

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 8, y: contentBottom, width: 384, height: 1))

        guard !reminders.isEmpty else {
            let message = emptyState.message
            let textWidth = measure(message, size: 22, weight: .semibold)
            draw(message, at: CGPoint(x: floor((CGFloat(width) - textWidth) / 2), y: 143),
                 size: 22, weight: .semibold, in: context)
            draw("上/下选择 · OK 确认", at: CGPoint(x: 12, y: 8), size: 11, weight: .medium, in: context)
            return packSupersampledWhitePixels(grayscale, outputWidth: width, outputHeight: height)
        }

        if view == .completed {
            let completed = reminders.filter(\.completed)
            let visible = DisplayRenderer.visiblePendingItems(
                completed,
                selectedIndex: selectedIndex ?? 0,
                capacity: 6
            )
            let selected = selectedIndex.flatMap { index in
                completed.isEmpty ? nil : completed[min(max(index, 0), completed.count - 1)]
            }
            var top = headerBottom
            for item in visible {
                top = drawRow(
                    item,
                    below: top,
                    selected: item.syncId == selected?.syncId,
                    generatedAt: generatedAt,
                    in: context
                )
            }
            draw("上/下选择 · 长按上键设置", at: CGPoint(x: 12, y: 8), size: 11, weight: .medium, in: context)
            drawRightAligned(
                "\(completed.count) 项完成", rightEdge: 388, y: 8,
                size: 11, weight: .semibold, in: context
            )
            return packSupersampledWhitePixels(grayscale, outputWidth: width, outputHeight: height)
        }

        let pending = reminders.filter { !$0.completed }

        // 还有待办时，已完成行最多占 4 行，始终给选中的待办留一行：
        // 否则本地连续完成 5 项后选中行不再绘制，OK 会完成一个看不见的事项。
        let completedItems = Array(
            reminders
                .filter(\.completed)
                .prefix(pending.isEmpty ? 5 : 4)
        )
        let pendingCapacity = max(0, 5 - completedItems.count)
        let visiblePending = DisplayRenderer.visiblePendingItems(
            pending,
            selectedIndex: selectedIndex ?? 0,
            capacity: pendingCapacity
        )
        let selected = selectedIndex.flatMap { index in
            pending.isEmpty ? nil : pending[min(max(index, 0), pending.count - 1)]
        }

        var top = headerBottom
        // Morning/afternoon/evening are sections of Apple's Today view. The
        // Scheduled and All views can contain reminders from many dates, so
        // grouping them into today's periods would silently drop tomorrow and
        // later timed reminders. Those views stay in EventKit's chronological
        // order and use the date-aware label drawn at the right of each row.
        let usesTodayPeriods = view == .today && visiblePending.contains {
            DisplayRenderer.dayPeriod(for: $0, relativeTo: generatedAt) != nil
        }
        if usesTodayPeriods {
            // Keep undated and overdue rows outside the three time sections.
            // This is also a defensive fallback: every item that cannot be
            // classified into a period must still be rendered.
            for item in visiblePending where DisplayRenderer.dayPeriod(for: item, relativeTo: generatedAt) == nil {
                top = drawRow(item, below: top, selected: item.syncId == selected?.syncId, generatedAt: generatedAt, in: context)
            }
            for period in DisplayRenderer.DayPeriod.allCases {
                let items = visiblePending.filter { DisplayRenderer.dayPeriod(for: $0, relativeTo: generatedAt) == period }
                top = drawSection(
                    period.title,
                    below: top,
                    drawsTopSeparator: period != .morning,
                    in: context
                )
                for item in items {
                    top = drawRow(item, below: top, selected: item.syncId == selected?.syncId, generatedAt: generatedAt, in: context)
                }
            }
            drawSeparator(at: top, in: context)
        } else {
            for item in visiblePending {
                top = drawRow(item, below: top, selected: item.syncId == selected?.syncId, generatedAt: generatedAt, in: context)
            }
        }

        for completedItem in completedItems.prefix(max(0, 5 - visiblePending.count)) {
            top = drawRow(completedItem, below: top, selected: false, generatedAt: generatedAt, in: context)
        }

        draw("上/下选择 · OK 确认", at: CGPoint(x: 12, y: 8), size: 11, weight: .medium, in: context)
        drawRightAligned(
            "\(pending.count) 项待办", rightEdge: 388, y: 8,
            size: 11, weight: .semibold, in: context
        )
        return packSupersampledWhitePixels(grayscale, outputWidth: width, outputHeight: height)
    }

    static func previewImage(
        _ reminders: [ReminderItem],
        selectedIndex: Int? = nil,
        view: DeviceReminderView = .today,
        emptyState: ReminderEmptyState = .noItems,
        generatedAt: Date = Date()
    ) throws -> CGImage {
        let packed = try render(
            reminders, selectedIndex: selectedIndex, view: view,
            emptyState: emptyState, generatedAt: generatedAt
        )
        let bytes = [UInt8](packed)
        var grayscale = [UInt8](repeating: 255, count: width * height)
        for pixel in grayscale.indices where bytes[pixel / 8] & UInt8(0x80 >> (pixel % 8)) == 0 {
            grayscale[pixel] = 0
        }
        guard let provider = CGDataProvider(data: Data(grayscale) as CFData),
              let image = CGImage(
                width: width, height: height,
                bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw DisplayRenderer.RenderError.contextCreationFailed
        }
        return image
    }

    private static func drawSection(
        _ title: String,
        below top: CGFloat,
        drawsTopSeparator: Bool,
        in context: CGContext
    ) -> CGFloat {
        let bottom = top - sectionHeight
        if drawsTopSeparator {
            drawSeparator(at: top, in: context)
        }
        draw(title, at: CGPoint(x: 12, y: bottom + 3), size: 10, weight: .semibold, in: context)
        return bottom
    }

    private static func drawSeparator(at top: CGFloat, in context: CGContext) {
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 8, y: top - 1, width: 384, height: 1))
    }

    @discardableResult
    private static func drawRow(
        _ reminder: ReminderItem,
        below top: CGFloat,
        selected: Bool,
        generatedAt: Date,
        in context: CGContext
    ) -> CGFloat {
        let bottom = top - rowHeight
        let rowRect = CGRect(x: 7, y: bottom + 1, width: 386, height: rowHeight - 2)
        let foreground: CGFloat

        if selected {
            fillLightDither(rowRect, in: context)
            foreground = 0
        } else {
            foreground = 0
        }

        let circleSize: CGFloat = 22
        let circle = CGRect(
            x: 14,
            y: bottom + (rowHeight - circleSize) / 2,
            width: circleSize,
            height: circleSize
        )
        context.setStrokeColor(gray: foreground, alpha: 1)
        context.setLineWidth(2)
        context.strokeEllipse(in: circle.insetBy(dx: 1, dy: 1))
        if reminder.completed {
            context.setFillColor(gray: foreground, alpha: 1)
            context.fillEllipse(in: circle.insetBy(dx: 5, dy: 5))
        }

        let dueLabel = DisplayRenderer.displayDueLabel(for: reminder, relativeTo: generatedAt)
        let title = clipped(titleWithoutEmoji(reminder.title), maxWidth: 245, size: 18, weight: .semibold)
        let titlePoint = CGPoint(x: 50, y: bottom + 7)
        draw(title, at: titlePoint, size: 18, weight: .semibold, gray: foreground, in: context)
        drawRightAligned(
            dueLabel, rightEdge: 384, y: bottom + 8,
            size: 16, weight: .semibold, gray: foreground, in: context
        )

        if reminder.completed {
            let textWidth = min(measure(title, size: 18, weight: .semibold), 245)
            context.setFillColor(gray: foreground, alpha: 1)
            context.fill(CGRect(x: titlePoint.x, y: titlePoint.y + 9, width: textWidth, height: 2))
        }
        return bottom
    }

    private static func fillLightDither(_ rect: CGRect, in context: CGContext) {
        context.saveGState()
        context.setFillColor(gray: 0, alpha: 1)
        let minX = Int(rect.minX)
        let maxX = Int(rect.maxX)
        let minY = Int(rect.minY)
        let maxY = Int(rect.maxY)
        for y in stride(from: minY, to: maxY, by: 4) {
            let offset = ((y - minY) / 4 % 2) * 2
            for x in stride(from: minX + offset, to: maxX, by: 4) {
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        context.restoreGState()
    }

    private static func packSupersampledWhitePixels(
        _ grayscale: [UInt8],
        outputWidth: Int,
        outputHeight: Int,
        threshold: UInt8 = 176
    ) -> Data {
        let sourceWidth = outputWidth * renderScale
        let sourceHeight = outputHeight * renderScale
        precondition(grayscale.count == sourceWidth * sourceHeight)
        var packed = [UInt8](repeating: 0xFF, count: outputWidth * outputHeight / 8)
        let samplesPerPixel = renderScale * renderScale
        for y in 0..<outputHeight {
            for x in 0..<outputWidth {
                var sum = 0
                for sampleY in 0..<renderScale {
                    let row = (y * renderScale + sampleY) * sourceWidth
                    for sampleX in 0..<renderScale {
                        sum += Int(grayscale[row + x * renderScale + sampleX])
                    }
                }
                if sum / samplesPerPixel < Int(threshold) {
                    let index = y * outputWidth + x
                    packed[index / 8] &= ~UInt8(0x80 >> (index % 8))
                }
            }
        }
        return Data(packed)
    }

    static func titleWithoutEmoji(_ value: String) -> String {
        let filtered = value.filter { character in
            !character.unicodeScalars.contains { scalar in
                scalar.properties.isEmojiPresentation ||
                    (scalar.properties.isEmoji && scalar.value > 0x238C) ||
                    scalar.value == 0x20E3
            }
        }
        let normalized = filtered
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "未命名事项" : normalized
    }

    private static func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEE"
        return formatter.string(from: date)
    }

    private enum FontWeight { case medium, semibold, bold }

    private static func font(size: CGFloat, weight: FontWeight) -> CTFont {
        let name: String
        switch weight {
        case .medium: name = "PingFangSC-Medium"
        case .semibold, .bold: name = "PingFangSC-Semibold"
        }
        return CTFontCreateWithName(name as CFString, size, nil)
    }

    private static func line(
        _ text: String,
        size: CGFloat,
        weight: FontWeight,
        gray: CGFloat = 0
    ) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font(size: size, weight: weight),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: gray, alpha: 1)
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    private static func draw(
        _ text: String,
        at point: CGPoint,
        size: CGFloat,
        weight: FontWeight,
        gray: CGFloat = 0,
        in context: CGContext
    ) {
        context.textPosition = point
        CTLineDraw(line(text, size: size, weight: weight, gray: gray), context)
    }

    private static func drawRightAligned(
        _ text: String,
        rightEdge: CGFloat,
        y: CGFloat,
        size: CGFloat,
        weight: FontWeight,
        gray: CGFloat = 0,
        in context: CGContext
    ) {
        let textLine = line(text, size: size, weight: weight, gray: gray)
        let textWidth = CGFloat(CTLineGetTypographicBounds(textLine, nil, nil, nil))
        context.textPosition = CGPoint(x: floor(rightEdge - textWidth), y: y)
        CTLineDraw(textLine, context)
    }

    private static func measure(_ text: String, size: CGFloat, weight: FontWeight) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line(text, size: size, weight: weight), nil, nil, nil))
    }

    private static func clipped(
        _ value: String,
        maxWidth: CGFloat,
        size: CGFloat,
        weight: FontWeight
    ) -> String {
        guard measure(value, size: size, weight: weight) > maxWidth else { return value }
        var result = value
        while !result.isEmpty {
            result.removeLast()
            let candidate = result + "…"
            if measure(candidate, size: size, weight: weight) <= maxWidth { return candidate }
        }
        return "…"
    }
}
