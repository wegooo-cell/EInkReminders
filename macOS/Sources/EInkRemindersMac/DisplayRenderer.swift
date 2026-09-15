import CoreGraphics
import CoreText
import Foundation

enum DisplayRenderer {
    static let width = 648
    static let height = 480
    static let packedByteCount = width * height / 8
    private static let rowHeight: CGFloat = 64
    private static let firstRowBottom: CGFloat = 319

    enum DayPeriod: Int, CaseIterable, Hashable {
        case morning
        case afternoon
        case evening

        var title: String {
            switch self {
            case .morning: return "上午"
            case .afternoon: return "下午"
            case .evening: return "今晚"
            }
        }
    }

    static func render(
        _ reminders: [ReminderItem],
        selectedIndex: Int = 0,
        generatedAt: Date = Date()
    ) throws -> Data {
        var grayscale = [UInt8](repeating: 255, count: width * height)
        guard let context = CGContext(
            data: &grayscale,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { throw RenderError.contextCreationFailed }

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw("今天", at: CGPoint(x: 28, y: 405), size: 58, emphasized: true, in: context)
        drawRightAligned(dateLabel(generatedAt), rightEdge: 620, y: 420, size: 25, in: context)

        guard !reminders.isEmpty else {
            draw("没有待办事项", at: CGPoint(x: 205, y: 232), size: 30, emphasized: true, in: context)
            draw("可在 Apple 提醒事项或设备网页中添加", at: CGPoint(x: 28, y: 19), size: 16, gray: 0.32, in: context)
            return packBlackPixels(grayscale)
        }

        let pending = reminders.filter { !$0.completed }
        let completed = reminders.filter(\.completed)
        let selected = pending.isEmpty ? nil : pending[min(max(selectedIndex, 0), min(pending.count, 5) - 1)]
        let completedItem = completed.last
        let pendingCapacity = completedItem == nil ? 5 : 4
        let visiblePending = visiblePendingItems(
            pending,
            selectedIndex: selectedIndex,
            capacity: pendingCapacity
        )
        let completedBottom = drawReminderList(
            visiblePending,
            selectedSyncId: selected?.syncId,
            availableHeight: completedItem == nil ? 320 : 256,
            generatedAt: generatedAt,
            in: context
        )
        if let completedItem {
            drawReminderRow(
                completedItem,
                bottom: completedBottom,
                selected: false,
                generatedAt: generatedAt,
                context: context
            )
        }

        draw(
            "单击下一项 · 双击确认",
            at: CGPoint(x: 28, y: 19), size: 16, gray: 0.30, in: context
        )
        drawRightAligned(
            "\(pending.count) 项待办", rightEdge: 620, y: 19,
            size: 18, gray: 0.30, in: context
        )
        return packBlackPixels(grayscale)
    }

    static func packBlackPixels(_ grayscale: [UInt8], threshold: UInt8 = 128) -> Data {
        precondition(grayscale.count == width * height)
        var packed = [UInt8](repeating: 0, count: packedByteCount)
        for index in grayscale.indices where grayscale[index] < threshold {
            packed[index / 8] |= UInt8(0x80 >> (index % 8))
        }
        return Data(packed)
    }

    static func pbmPreview(_ packed: Data) -> Data {
        var result = Data("P4\n\(width) \(height)\n".utf8)
        result.append(packed)
        return result
    }

    static func previewImage(
        _ reminders: [ReminderItem],
        selectedIndex: Int = 0,
        generatedAt: Date = Date()
    ) throws -> CGImage {
        let packed = try render(reminders, selectedIndex: selectedIndex, generatedAt: generatedAt)
        var grayscale = [UInt8](repeating: 255, count: width * height)
        packed.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            for pixel in grayscale.indices {
                if bytes[pixel / 8] & UInt8(0x80 >> (pixel % 8)) != 0 {
                    grayscale[pixel] = 0
                }
            }
        }
        let data = Data(grayscale) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw RenderError.contextCreationFailed
        }
        return image
    }

    private static func drawReminderRow(
        _ reminder: ReminderItem,
        bottom: CGFloat,
        height: CGFloat = rowHeight,
        selected: Bool,
        generatedAt: Date,
        context: CGContext
    ) {
        if selected {
            fillLightDither(CGRect(x: 12, y: bottom, width: 624, height: height), in: context)
        }
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setLineWidth(selected ? 3 : 2)
        let circleSize = min(30, height - 18)
        let circle = CGRect(x: 29, y: bottom + (height - circleSize) / 2, width: circleSize, height: circleSize)
        context.strokeEllipse(in: circle)
        if reminder.completed {
            // Match Apple's completed indicator proportions: a large solid
            // center separated from the outer ring by a narrow white halo.
            let inset = max(4, circleSize * 0.13)
            context.setFillColor(gray: 0, alpha: 1)
            context.fillEllipse(in: circle.insetBy(dx: inset, dy: inset))
        }
        let title = clipped(reminder.title, limit: 16)
        let titlePoint = CGPoint(x: 81, y: bottom + (height - 26) / 2 + 4)
        draw(title, at: titlePoint, size: 26, emphasized: selected, in: context)
        if reminder.completed {
            let line = makeLine(title, size: 26, emphasized: false, gray: 0)
            let textWidth = min(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)), 410)
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: titlePoint.x, y: titlePoint.y + 12, width: textWidth, height: 2))
        }
        drawRightAligned(
            displayDueLabel(for: reminder, relativeTo: generatedAt), rightEdge: 620, y: bottom + (height - 22) / 2 + 4,
            size: 22, emphasized: selected, in: context
        )
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 12, y: bottom, width: 624, height: 1))
    }

    private static func drawReminderList(
        _ reminders: [ReminderItem],
        selectedSyncId: String?,
        availableHeight: CGFloat,
        generatedAt: Date,
        in context: CGContext
    ) -> CGFloat {
        let timedPeriods = Set(reminders.compactMap { dayPeriod(for: $0, relativeTo: generatedAt) })
        guard timedPeriods.count > 1 else {
            for (index, reminder) in reminders.enumerated() {
                let bottom = firstRowBottom - CGFloat(index) * rowHeight
                drawReminderRow(reminder, bottom: bottom, selected: reminder.syncId == selectedSyncId, generatedAt: generatedAt, context: context)
            }
            return firstRowBottom - CGFloat(reminders.count) * rowHeight
        }

        let untimed = reminders.filter { !$0.hasDueTime }
        let timedSections = DayPeriod.allCases.compactMap { period -> (DayPeriod, [ReminderItem])? in
            let items = reminders.filter { dayPeriod(for: $0, relativeTo: generatedAt) == period }
            return items.isEmpty ? nil : (period, items)
        }
        let sectionCount = timedSections.count
        let sectionHeight: CGFloat = 24
        let groupedRowHeight = min(rowHeight, (availableHeight - CGFloat(sectionCount) * sectionHeight) / CGFloat(reminders.count))
        var top: CGFloat = 383

        for item in untimed {
            let bottom = top - groupedRowHeight
            drawReminderRow(item, bottom: bottom, height: groupedRowHeight, selected: item.syncId == selectedSyncId, generatedAt: generatedAt, context: context)
            top = bottom
        }

        for (period, items) in timedSections {
            draw(period.title, at: CGPoint(x: 28, y: top - 18), size: 16, emphasized: true, gray: 0.36, in: context)
            context.setFillColor(gray: 0.72, alpha: 1)
            context.fill(CGRect(x: 12, y: top - sectionHeight, width: 624, height: 1))
            top -= sectionHeight
            for item in items {
                let bottom = top - groupedRowHeight
                drawReminderRow(item, bottom: bottom, height: groupedRowHeight, selected: item.syncId == selectedSyncId, generatedAt: generatedAt, context: context)
                top = bottom
            }
        }
        return top - rowHeight
    }

    static func visiblePendingItems(
        _ pending: [ReminderItem],
        selectedIndex: Int,
        capacity: Int
    ) -> [ReminderItem] {
        guard capacity > 0, !pending.isEmpty else { return [] }
        guard pending.count > capacity else { return pending }
        let selected = min(max(selectedIndex, 0), pending.count - 1)
        let start = min(max(0, selected - capacity + 1), pending.count - capacity)
        return Array(pending[start..<(start + capacity)])
    }

    private static func fillLightDither(_ rect: CGRect, in context: CGContext) {
        context.saveGState()
        context.setFillColor(gray: 0, alpha: 1)
        let minX = Int(rect.minX)
        let maxX = Int(rect.maxX)
        let minY = Int(rect.minY)
        let maxY = Int(rect.maxY)
        for y in stride(from: minY, to: maxY, by: 4) {
            let offset = ((y / 4) % 2) * 2
            for x in stride(from: minX + offset, to: maxX, by: 4) {
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        context.restoreGState()
    }

    private static func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEE"
        return formatter.string(from: date)
    }

    static func displayDueLabel(for reminder: ReminderItem, relativeTo reference: Date = Date()) -> String {
        guard let dueAt = reminder.dueAt else { return "今天" }
        let calendar = Calendar.current
        let time = DateFormatter()
        time.dateFormat = "HH:mm"
        if calendar.isDate(dueAt, inSameDayAs: reference) {
            return reminder.hasDueTime ? time.string(from: dueAt) : "今天"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: reference)),
           calendar.isDate(dueAt, inSameDayAs: tomorrow) {
            return reminder.hasDueTime ? "明天 \(time.string(from: dueAt))" : "明天"
        }
        let date = DateFormatter()
        date.dateFormat = reminder.hasDueTime ? "M/d HH:mm" : "M月d日"
        return date.string(from: dueAt)
    }

    static func dayPeriod(for reminder: ReminderItem, relativeTo reference: Date = Date()) -> DayPeriod? {
        guard reminder.hasDueTime, let dueAt = reminder.dueAt,
              Calendar.current.isDate(dueAt, inSameDayAs: reference) else { return nil }
        switch Calendar.current.component(.hour, from: dueAt) {
        case ..<12: return .morning
        case 12..<17: return .afternoon
        default: return .evening
        }
    }

    private static func draw(
        _ text: String,
        at point: CGPoint,
        size: CGFloat,
        emphasized: Bool = false,
        gray: CGFloat = 0,
        in context: CGContext
    ) {
        let line = makeLine(text, size: size, emphasized: emphasized, gray: gray)
        context.textPosition = point
        CTLineDraw(line, context)
    }

    private static func drawRightAligned(
        _ text: String,
        rightEdge: CGFloat,
        y: CGFloat,
        size: CGFloat,
        emphasized: Bool = false,
        gray: CGFloat = 0,
        in context: CGContext
    ) {
        let line = makeLine(text, size: size, emphasized: emphasized, gray: gray)
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.textPosition = CGPoint(x: rightEdge - lineWidth, y: y)
        CTLineDraw(line, context)
    }

    private static func makeLine(_ text: String, size: CGFloat, emphasized: Bool, gray: CGFloat) -> CTLine {
        let fontName = emphasized ? "PingFangSC-Semibold" : "PingFangSC-Regular"
        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: gray, alpha: 1)
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    private static func clipped(_ value: String, limit: Int) -> String {
        value.count > limit ? String(value.prefix(limit - 1)) + "…" : value
    }

    enum RenderError: Error { case contextCreationFailed }
}
