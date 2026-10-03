import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// Draws directly at the ZECTRIX NOTE4 native 400×300 resolution.
/// The wire format is MSB first, where 1 is white and 0 is black.
enum ZectrixDisplayRenderer {
    static let width = 400
    static let height = 300
    static let packedByteCount = width * height / 8
    static let alertPatchWidth = 280
    static let alertPatchHeight = 78
    /// 4× supersampling provides coverage-based antialiasing before the image
    /// is quantized to the NOTE4 panel's native 1-bit pixels. The device still
    /// receives the same 15 KB frame, so this adds no radio or display-power
    /// cost; only the Mac performs the higher-resolution rasterization.
    private static let renderScale = 4

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
        context.setShouldSmoothFonts(false)
        context.setAllowsFontSmoothing(false)
        context.interpolationQuality = .none
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
        draw(clipped(titleWithoutEmoji(title), maxWidth: 112, size: 14, weight: .semibold),
             at: CGPoint(x: 64, y: 25), size: 14, weight: .semibold, in: context)
        // The device draws the three interactive controls and the snooze menu.
        // Keeping them out of the synced bitmap lets it update selection and
        // menu state without another Mac sync.
        return packSupersampledWhitePixels(
            grayscale,
            outputWidth: alertPatchWidth,
            outputHeight: alertPatchHeight
        )
    }

    private static let standbyPixelFontReady: Bool = {
        let bundled = Bundle.main.url(forResource: "WenQuanYiBitmapSong16px", withExtension: "ttf")
        let development = ProcessInfo.processInfo.environment["EINK_PIXEL_FONT_16_PATH"].map {
            URL(fileURLWithPath: $0)
        }
        guard let url = bundled ?? development else { return false }
        var error: Unmanaged<CFError>?
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    }()

    /// Pixel-font labels for the two approved black StandBy screens. The
    /// device inverts the black glyphs to white when composing its 1-bit UI.
    static func renderStandbyTitlePatch(_ title: String) throws -> Data {
        try renderStandbyTextPatch(titleWithoutEmoji(title), size: 18, tracking: 2)
    }

    static func renderPhotoReminderPatch(_ title: String) throws -> Data {
        try renderStandbyTextPatch("下一个提醒 \(titleWithoutEmoji(title))",
                                   size: 16, tracking: 1, patchWidth: 184)
    }

    /// Black-background 190×140, 1 means white ink. The firmware positions
    /// this patch at (207, 40), matching the approved third StandBy preview.
    static func renderWeatherPatch(city: String, celsius: Double) throws -> Data {
        let patchWidth = 190, patchHeight = 140, scale = 4
        let width = patchWidth * scale, height = patchHeight * scale
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            throw DisplayRenderer.RenderError.contextCreationFailed
        }
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(false)
        context.setAllowsFontSmoothing(false)
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        let white = CGColor(gray: 1, alpha: 1)
        func line(_ text: String, font: String, size: CGFloat) -> CTLine {
            CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String):
                    CTFontCreateWithName(font as CFString, size, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): white
            ]))
        }
        var visibleCity = city
        while !visibleCity.isEmpty,
              CTLineGetTypographicBounds(line(visibleCity, font: "PingFangSC-Semibold", size: 26),
                                         nil, nil, nil) > 184 {
            visibleCity.removeLast()
        }
        context.textPosition = CGPoint(x: 3, y: 114)
        CTLineDraw(line(visibleCity, font: "PingFangSC-Semibold", size: 26), context)
        let temperature = "\(Int(celsius.rounded()))°"
        var temperatureSize: CGFloat = 101
        while temperatureSize > 54,
              CTLineGetTypographicBounds(line(temperature, font: "HelveticaNeue-Medium",
                                             size: temperatureSize), nil, nil, nil) > 188 {
            temperatureSize -= 2
        }
        context.textPosition = CGPoint(x: 0, y: 19)
        CTLineDraw(line(temperature, font: "HelveticaNeue-Medium", size: temperatureSize), context)
        var packed = [UInt8](repeating: 0, count: patchWidth * patchHeight / 8)
        for y in 0..<patchHeight {
            for x in 0..<patchWidth {
                var coverage = 0
                for sy in 0..<scale {
                    for sx in 0..<scale where pixels[(y * scale + sy) * width + x * scale + sx] >= 128 {
                        coverage += 1
                    }
                }
                if coverage >= 7 {
                    let bit = y * patchWidth + x
                    packed[bit / 8] |= 0x80 >> (bit % 8)
                }
            }
        }
        return Data(packed)
    }

    static func renderStandbyDuePatch(_ dueAt: Date, now: Date = Date()) throws -> Data {
        let calendar = Calendar.current
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = "HH:mm"
        let prefix: String
        if calendar.isDate(dueAt, inSameDayAs: now) {
            prefix = "今天"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1,
                                               to: calendar.startOfDay(for: now)),
                  calendar.isDate(dueAt, inSameDayAs: tomorrow) {
            prefix = "明天"
        } else {
            let date = DateFormatter()
            date.locale = Locale(identifier: "en_US_POSIX")
            date.dateFormat = "M/d"
            prefix = date.string(from: dueAt)
        }
        return try renderStandbyTextPatch("\(prefix) \(clock.string(from: dueAt))", size: 16, tracking: 1)
    }

    private static func renderStandbyTextPatch(
        _ value: String, size: CGFloat, tracking: CGFloat, patchWidth: Int = 112
    ) throws -> Data {
        let patchHeight = 22
        var pixels = [UInt8](repeating: 255, count: patchWidth * patchHeight)
        guard let context = CGContext(data: &pixels, width: patchWidth, height: patchHeight,
                                      bitsPerComponent: 8, bytesPerRow: patchWidth,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            throw DisplayRenderer.RenderError.contextCreationFailed
        }
        _ = standbyPixelFontReady
        let pixelFont = CTFontCreateWithName(
            (standbyPixelFontReady ? "WenQuanYiBitmapSong16px" : "PingFangSC-Regular") as CFString,
            size, nil)
        func makeLine(_ text: String) -> CTLine {
            CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): pixelFont,
                .kern: tracking,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
            ]))
        }
        var clipped = value
        while !clipped.isEmpty,
              CTLineGetTypographicBounds(makeLine(clipped), nil, nil, nil) > Double(patchWidth - 2) {
            clipped.removeLast()
        }
        context.setShouldAntialias(false)
        context.setShouldSmoothFonts(false)
        context.setAllowsFontSmoothing(false)
        context.textPosition = CGPoint(x: 0, y: size >= 18 ? 2 : 3)
        CTLineDraw(makeLine(clipped), context)
        var packed = [UInt8](repeating: 0xFF, count: patchWidth * patchHeight / 8)
        for pixel in pixels.indices where pixels[pixel] < 128 {
            packed[pixel / 8] &= ~UInt8(0x80 >> (pixel % 8))
        }
        return Data(packed)
    }

    private static let headerBottom: CGFloat = 244
    private static let contentBottom: CGFloat = 27
    private static let rowHeight: CGFloat = 32
    private static let todaySectionHeight: CGFloat = 33
    private static let todayRowHeight: CGFloat = 29

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
        context.setShouldSmoothFonts(false)
        context.setAllowsFontSmoothing(false)
        context.interpolationQuality = .none
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
            draw("上下选择 · OK确认", at: CGPoint(x: 12, y: 8), size: 14, weight: .semibold, in: context)
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
            draw("上下选择 · 长按上键设置", at: CGPoint(x: 12, y: 8), size: 14, weight: .semibold, in: context)
            drawRightAligned(
                "\(completed.count) 项完成", rightEdge: 388, y: 8,
                size: 14, weight: .semibold, in: context
            )
            return packSupersampledWhitePixels(grayscale, outputWidth: width, outputHeight: height)
        }

        let pending = reminders.filter { !$0.completed }

        // 还有待办时，已完成行最多占 4 行，始终给选中的待办留一行：
        // 否则本地连续完成 5 项后选中行不再绘制，OK 会完成一个看不见的事项。
        let hasTodayPeriods = view == .today && pending.contains {
            DisplayRenderer.dayPeriod(for: $0, relativeTo: generatedAt) != nil
        }
        let completedItems = Array(
            reminders
                .filter(\.completed)
                .prefix(pending.isEmpty ? 5 : (hasTodayPeriods ? 3 : 4))
        )
        let pendingCapacity = max(0, (hasTodayPeriods ? 4 : 5) - completedItems.count)
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
        let usesTodayPeriods = hasTodayPeriods && visiblePending.contains {
            DisplayRenderer.dayPeriod(for: $0, relativeTo: generatedAt) != nil
        }
        if usesTodayPeriods {
            // Three headings and four rows must fit between the header and
            // footer. Give empty headings genuine whitespace below their
            // glyphs; compact only the row height, not the text size.
            // Keep undated and overdue rows outside the three time sections.
            // This is also a defensive fallback: every item that cannot be
            // classified into a period must still be rendered.
            for item in visiblePending where DisplayRenderer.dayPeriod(for: item, relativeTo: generatedAt) == nil {
                top = drawRow(item, below: top, selected: item.syncId == selected?.syncId, generatedAt: generatedAt, height: todayRowHeight, in: context)
            }
            for period in DisplayRenderer.DayPeriod.allCases {
                let items = visiblePending.filter { DisplayRenderer.dayPeriod(for: $0, relativeTo: generatedAt) == period }
                top = drawSection(
                    period.title,
                    below: top,
                    in: context
                )
                for item in items {
                    top = drawRow(item, below: top, selected: item.syncId == selected?.syncId, generatedAt: generatedAt, height: todayRowHeight, in: context)
                }
                drawSeparator(at: top, in: context)
            }
        } else {
            for item in visiblePending {
                top = drawRow(item, below: top, selected: item.syncId == selected?.syncId, generatedAt: generatedAt, in: context)
            }
        }

        for completedItem in completedItems.prefix(max(0, 5 - visiblePending.count)) {
            top = drawRow(completedItem, below: top, selected: false, generatedAt: generatedAt,
                          height: usesTodayPeriods ? todayRowHeight : rowHeight, in: context)
        }

        draw("上下选择 · OK确认", at: CGPoint(x: 12, y: 8), size: 14, weight: .semibold, in: context)
        drawRightAligned(
            "\(pending.count) 项待办", rightEdge: 388, y: 8,
            size: 14, weight: .semibold, in: context
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

    static func renderNotesList(
        _ notes: [NoteSummary], selectedIndex: Int? = nil,
        generatedAt: Date = Date()
    ) throws -> Data {
        var grayscale = [UInt8](repeating: 255, count: width * renderScale * height * renderScale)
        let sourceWidth = width * renderScale
        guard let context = CGContext(
            data: &grayscale, width: sourceWidth, height: height * renderScale,
            bitsPerComponent: 8, bytesPerRow: sourceWidth,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { throw DisplayRenderer.RenderError.contextCreationFailed }
        configure(context)
        draw("备忘录", at: CGPoint(x: 13, y: 257), size: 39, weight: .bold, in: context)
        drawRightAligned(dateLabel(generatedAt), rightEdge: 387, y: 269, size: 18, weight: .semibold, in: context)
        context.fill(CGRect(x: 8, y: contentBottom, width: 384, height: 1))

        guard !notes.isEmpty else {
            let message = "目前没有备忘录"
            draw(message, at: CGPoint(x: (CGFloat(width) - measure(message, size: 22, weight: .semibold)) / 2, y: 143), size: 22, weight: .semibold, in: context)
            draw("上下选择 · OK打开", at: CGPoint(x: 12, y: 8), size: 14, weight: .semibold, in: context)
            return packSupersampledWhitePixels(grayscale, outputWidth: width, outputHeight: height)
        }

        let selected = selectedIndex.map { min(max($0, 0), notes.count - 1) }
        // Apple Notes uses a spacious two-line row. Keep the selected note near
        // the middle while limiting the 400x300 display to four visible rows.
        let start = selected.map { min(max(0, $0 - 2), max(0, notes.count - 4)) } ?? 0
        var top = headerBottom
        for index in start..<min(start + 4, notes.count) {
            let beginsGroup = index == 0 || notes[index - 1].modifiedLabel != notes[index].modifiedLabel
            let itemHeight: CGFloat = 50
            if beginsGroup {
                // Never leave an orphan group heading at the bottom: reserve
                // enough room for the first two-line note row as well.
                guard top - 26 - itemHeight >= contentBottom + 4 else { break }
                let groupBottom = top - 26
                draw(notes[index].modifiedLabel, at: CGPoint(x: 12, y: groupBottom + 6), size: 18, weight: .semibold, in: context)
                context.fill(CGRect(x: 8, y: groupBottom, width: 384, height: 1))
                top = groupBottom
            }

            guard top - itemHeight >= contentBottom + 4 else { break }
            let bottom = top - itemHeight
            if selected == index {
                fillLightDither(CGRect(x: 20, y: bottom + 2, width: 372, height: itemHeight - 4), in: context)
            }
            let title = clipped(titleWithoutEmoji(notes[index].title), maxWidth: 352, size: 17, weight: .semibold)
            draw(title, at: CGPoint(x: 28, y: bottom + 28), size: 17, weight: .semibold, in: context)
            let metadata = notes[index].previewText.isEmpty
                ? notes[index].modifiedText
                : "\(notes[index].modifiedText)  \(notes[index].previewText)"
            let metadataLine = clipped(textWithoutEmoji(metadata), maxWidth: 352, size: 14, weight: .semibold)
            draw(metadataLine, at: CGPoint(x: 28, y: bottom + 9), size: 14, weight: .semibold, in: context)
            context.fill(CGRect(x: 28, y: bottom, width: 360, height: 1))
            top = bottom
        }
        draw("上下选择 · OK打开", at: CGPoint(x: 12, y: 8), size: 14, weight: .semibold, in: context)
        drawRightAligned("\(notes.count) 项", rightEdge: 388, y: 8, size: 14, weight: .semibold, in: context)
        return packSupersampledWhitePixels(grayscale, outputWidth: width, outputHeight: height)
    }

    static func renderCalendar(
        _ items: [ReminderItem], monthOffset: Int, selectedDay: Int,
        selectingDay: Bool, dayDetail: Bool, detailPage: Int,
        generatedAt: Date = Date()
    ) throws -> Data {
        let sourceWidth = width * renderScale
        var grayscale = [UInt8](repeating: 255, count: sourceWidth * height * renderScale)
        guard let context = CGContext(
            data: &grayscale, width: sourceWidth, height: height * renderScale,
            bitsPerComponent: 8, bytesPerRow: sourceWidth,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { throw DisplayRenderer.RenderError.contextCreationFailed }
        configure(context)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: generatedAt))!
        let month = calendar.date(byAdding: .month, value: max(-120, min(120, monthOffset)), to: currentMonth)!
        let components = calendar.dateComponents([.year, .month], from: month)
        let year = components.year!, monthNumber = components.month!
        let dayCount = calendar.range(of: .day, in: .month, for: month)!.count
        let day = max(1, min(dayCount, selectedDay))
        // Monday is the first column, matching the approved calendar preview.
        let firstWeekday = (calendar.component(.weekday, from: month) + 5) % 7
        let monthItems = items.filter { item in
            guard let dueAt = item.dueAt else { return false }
            return calendar.isDate(dueAt, equalTo: month, toGranularity: .month)
        }
        let datesWithItems = Set(monthItems.map { item in
            calendar.component(.day, from: item.dueAt!)
        })

        if dayDetail {
            let date = calendar.date(byAdding: .day, value: day - 1, to: month)!
            let events = monthItems.filter { calendar.isDate($0.dueAt!, inSameDayAs: date) }
                .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            let weekday = weekdays[calendar.component(.weekday, from: date) - 1]
            // Match the existing Reminders view: a large title, a compact
            // date label, the same circular row markers and the same footer.
            draw("\(monthNumber)月\(day)日", at: CGPoint(x: 13, y: 257),
                 size: 39, weight: .bold, in: context)
            drawRightAligned(weekday, rightEdge: 387, y: 269,
                             size: 17, weight: .semibold, in: context)
            context.fill(CGRect(x: 8, y: contentBottom, width: 384, height: 1))
            if events.isEmpty {
                let message = "当天没有事项"
                let textWidth = measure(message, size: 22, weight: .semibold)
                draw(message, at: CGPoint(x: floor((CGFloat(width) - textWidth) / 2), y: 143),
                     size: 22, weight: .semibold, in: context)
            } else {
                let pageCount = max(1, (events.count + 5) / 6)
                let page = min(max(0, detailPage), pageCount - 1)
                var top = headerBottom
                for event in events.dropFirst(page * 6).prefix(6) {
                    top = drawRow(event, below: top, selected: false, generatedAt: date, in: context)
                }
                if pageCount > 1 {
                    drawRightAligned("\(page + 1)/\(pageCount)",
                                     rightEdge: 388, y: 8, size: 14, weight: .semibold, in: context)
                }
            }
            draw("上下翻页 · OK返回 · 长按OK今天", at: CGPoint(x: 12, y: 8),
                 size: 14, weight: .semibold, in: context)
            return packSupersampledWhitePixels(grayscale, outputWidth: width, outputHeight: height)
        }

        draw("\(year)年\(monthNumber)月", at: CGPoint(x: 12, y: 264),
             size: 28, weight: .bold, in: context)
        drawRightAligned(monthOffset == 0 ? "今天" : "切回今天", rightEdge: 387, y: 270,
                         size: 14, weight: .semibold, in: context)
        let weekdays = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        for (column, name) in weekdays.enumerated() {
            let columnLeft = CGFloat(8 + column * 55)
            let textWidth = measure(name, size: 14, weight: .semibold)
            draw(name, at: CGPoint(x: columnLeft + floor((55 - textWidth) / 2), y: 238),
                 size: 14, weight: .semibold, in: context)
        }
        let weekCount = (firstWeekday + dayCount + 6) / 7
        let gridTop: CGFloat = 224
        let gridBottom: CGFloat = 26
        let rowSpacing = (gridTop - gridBottom) / CGFloat(weekCount)
        let circleSize: CGFloat = weekCount == 6 ? 28 : 34
        let today = calendar.dateComponents([.year, .month, .day], from: generatedAt)
        for dateNumber in 1...dayCount {
            let cell = firstWeekday + dateNumber - 1
            let column = cell % 7, row = cell / 7
            let centerX = CGFloat(8 + column * 55) + 27.5
            let top = gridTop - CGFloat(row) * rowSpacing
            let circle = CGRect(x: floor(centerX - circleSize / 2),
                                y: floor(top - circleSize - 2),
                                width: circleSize, height: circleSize)
            let hasItems = datesWithItems.contains(dateNumber)
            let isToday = year == today.year && monthNumber == today.month && dateNumber == today.day
            let isSelected = selectingDay ? dateNumber == day : isToday
            let dateText = "\(dateNumber)"
            let dateSize: CGFloat = weekCount == 6 ? 16 : 18
            let dateWidth = measure(dateText, size: dateSize, weight: .semibold)
            context.setFillColor(gray: hasItems ? 0 : 0.70, alpha: 1)
            context.fillEllipse(in: circle)
            if isSelected {
                context.setStrokeColor(gray: 0, alpha: 1)
                context.setLineWidth(1.5)
                context.strokeEllipse(in: circle.insetBy(dx: -2, dy: -2))
            }
            // The panel is 1-bit: a fixed ordered dither below represents
            // gray without triggering an unstable per-refresh pattern.
            let textY = circle.minY + (weekCount == 6 ? 10 : 12)
            let textX = floor(centerX - dateWidth / 2)
            draw(dateText, at: CGPoint(x: textX, y: textY),
                 size: dateSize, weight: .semibold, gray: hasItems ? 1 : 0, in: context)
        }
        draw(selectingDay ? "上下选日 · OK打开 · 长按OK今天" : "上下切月 · OK选日 · 长按OK今天",
             at: CGPoint(x: 10, y: 6), size: 14, weight: .semibold, in: context)
        return packSupersampledWhitePixels(grayscale, outputWidth: width, outputHeight: height,
                                           ditheredGray: true)
    }

    static func notePageCount(_ note: NoteDocument) -> Int {
        max(1, textPages(note.text).count) + note.imageURLs.count
    }

    static func renderNoteDetail(_ note: NoteDocument, page: Int) throws -> Data {
        var grayscale = [UInt8](repeating: 255, count: width * renderScale * height * renderScale)
        let sourceWidth = width * renderScale
        guard let context = CGContext(
            data: &grayscale, width: sourceWidth, height: height * renderScale,
            bitsPerComponent: 8, bytesPerRow: sourceWidth,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { throw DisplayRenderer.RenderError.contextCreationFailed }
        configure(context)
        let pages = textPages(note.text)
        let total = max(1, pages.count) + note.imageURLs.count
        let current = min(max(page, 0), total - 1)
        draw(clipped(titleWithoutEmoji(note.summary.title), maxWidth: 290, size: 22, weight: .semibold), at: CGPoint(x: 13, y: 264), size: 22, weight: .semibold, in: context)
        drawRightAligned("\(current + 1)/\(total)", rightEdge: 387, y: 268, size: 14, weight: .semibold, in: context)
        context.fill(CGRect(x: 10, y: 250, width: 380, height: 1))
        context.fill(CGRect(x: 8, y: contentBottom, width: 384, height: 1))

        if current < max(1, pages.count) {
            let value = pages.isEmpty ? "（空白备忘录）" : pages[current]
            var y: CGFloat = 225
            for row in wrappedRows(value, maxWidth: 360, size: 16, weight: .medium).prefix(10) {
                // An empty paragraph is intentional spacing in the note. The
                // title helper has a "未命名事项" fallback, so it must never be
                // used for note-body rows.
                let visibleRow = textWithoutEmoji(row)
                if !visibleRow.isEmpty {
                    draw(visibleRow, at: CGPoint(x: 16, y: y), size: 16, weight: .medium, in: context)
                }
                y -= 21
            }
        } else {
            let imageIndex = current - max(1, pages.count)
            if note.imageURLs.indices.contains(imageIndex),
               let source = CGImageSourceCreateWithURL(note.imageURLs[imageIndex] as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                let available = CGRect(x: 14, y: 35, width: 372, height: 207)
                let ratio = min(available.width / CGFloat(image.width), available.height / CGFloat(image.height))
                let size = CGSize(width: CGFloat(image.width) * ratio, height: CGFloat(image.height) * ratio)
                let rect = CGRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2, width: size.width, height: size.height)
                context.interpolationQuality = .high
                context.draw(image, in: rect)
            } else {
                draw("图片无法显示", at: CGPoint(x: 140, y: 145), size: 18, weight: .semibold, in: context)
            }
        }
        draw("上下翻页 · OK返回", at: CGPoint(x: 12, y: 8), size: 14, weight: .semibold, in: context)
        return packSupersampledWhitePixels(grayscale, outputWidth: width, outputHeight: height, threshold: 144)
    }

    static func previewNotes(_ notes: [NoteSummary], selectedIndex: Int? = nil) throws -> CGImage {
        try image(fromPacked: renderNotesList(notes, selectedIndex: selectedIndex))
    }

    private static func configure(_ context: CGContext) {
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(false)
        context.setAllowsFontSmoothing(false)
        context.interpolationQuality = .none
        context.scaleBy(x: CGFloat(renderScale), y: CGFloat(renderScale))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 0, alpha: 1)
    }

    private static func image(fromPacked packed: Data) throws -> CGImage {
        let bytes = [UInt8](packed)
        var grayscale = [UInt8](repeating: 255, count: width * height)
        for pixel in grayscale.indices where bytes[pixel / 8] & UInt8(0x80 >> (pixel % 8)) == 0 { grayscale[pixel] = 0 }
        guard let provider = CGDataProvider(data: Data(grayscale) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw DisplayRenderer.RenderError.contextCreationFailed
        }
        return image
    }

    private static func textPages(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard !normalized.isEmpty else { return [] }
        let rows = wrappedRows(normalized, maxWidth: 360, size: 16, weight: .medium)
        return stride(from: 0, to: rows.count, by: 10).map { index in
            rows[index..<min(index + 10, rows.count)].joined(separator: "\n")
        }
    }

    private static func wrappedRows(
        _ text: String,
        maxWidth: CGFloat,
        size: CGFloat,
        weight: FontWeight
    ) -> [String] {
        var result: [String] = []
        for paragraph in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var row = ""
            for character in paragraph {
                let candidate = row + String(character)
                if !row.isEmpty && measure(candidate, size: size, weight: weight) > maxWidth {
                    result.append(row)
                    row = String(character)
                } else {
                    row = candidate
                }
            }
            result.append(row)
        }
        return result
    }

    private static func drawSection(
        _ title: String,
        below top: CGFloat,
        in context: CGContext
    ) -> CGFloat {
        let bottom = top - todaySectionHeight
        // 14 px preserves fine Chinese strokes after 1-bit conversion.
        draw(title, at: CGPoint(x: 12, y: bottom + 12), size: 14, weight: .semibold, in: context)
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
        height: CGFloat = rowHeight,
        in context: CGContext
    ) -> CGFloat {
        let bottom = top - height
        let rowRect = CGRect(x: 7, y: bottom + 1, width: 386, height: height - 2)
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
            y: bottom + (height - circleSize) / 2,
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
        threshold: UInt8 = 148,
        ditheredGray: Bool = false
    ) -> Data {
        let sourceWidth = outputWidth * renderScale
        let sourceHeight = outputHeight * renderScale
        precondition(grayscale.count == sourceWidth * sourceHeight)
        var packed = [UInt8](repeating: 0xFF, count: outputWidth * outputHeight / 8)
        let samplesPerPixel = renderScale * renderScale
        let bayer4 = [
            [0, 8, 2, 10], [12, 4, 14, 6],
            [3, 11, 1, 9], [15, 7, 13, 5]
        ]
        for y in 0..<outputHeight {
            for x in 0..<outputWidth {
                var sum = 0
                for sampleY in 0..<renderScale {
                    let row = (y * renderScale + sampleY) * sourceWidth
                    for sampleX in 0..<renderScale {
                        sum += Int(grayscale[row + x * renderScale + sampleX])
                    }
                }
                let average = sum / samplesPerPixel
                // Ordered 4×4 pattern is anchored to absolute panel pixels;
                // it never shimmers as a date is selected or pages refresh.
                let isBlack = ditheredGray && (165...195).contains(average)
                    ? bayer4[y & 3][x & 3] < 4
                    : average < Int(threshold)
                if isBlack {
                    let index = y * outputWidth + x
                    packed[index / 8] &= ~UInt8(0x80 >> (index % 8))
                }
            }
        }
        return Data(packed)
    }

    static func titleWithoutEmoji(_ value: String) -> String {
        let normalized = textWithoutEmoji(value)
        return normalized.isEmpty ? "未命名事项" : normalized
    }

    /// Removes unsupported emoji without replacing intentional blank content.
    /// Titles add their own fallback; note body lines must remain blank.
    private static func textWithoutEmoji(_ value: String) -> String {
        let filtered = value.filter { character in
            !character.unicodeScalars.contains { scalar in
                scalar.properties.isEmojiPresentation ||
                    (scalar.properties.isEmoji && scalar.value > 0x238C) ||
                    scalar.value == 0x20E3
            }
        }
        return filtered
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEE"
        return formatter.string(from: date)
    }

    private enum FontWeight { case medium, semibold, bold }

    private static let registerSourceHanSans: Void = {
        for resource in ["SourceHanSansSC-Regular", "SourceHanSansSC-Bold"] {
            guard let url = Bundle.main.url(forResource: resource, withExtension: "otf") else {
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    private static func font(size: CGFloat, weight: FontWeight) -> CTFont {
        // Quellog's 400x300 renderer uses Source Han Sans SC Regular at 16 px
        // as a pre-rasterized 1-bpp LVGL font. Bundle the same face so output
        // does not depend on which fonts happen to be installed on the Mac.
        if size <= 16 {
            _ = registerSourceHanSans
            // Quellog renders its 16 px body copy with the regular face. UI
            // labels below that size need a heavier face so their stems remain
            // at least one physical pixel wide on the monochrome panel.
            let sourceHanName = weight == .medium
                ? "SourceHanSansSC-Regular"
                : "SourceHanSansSC-Bold"
            let sourceHan = CTFontCreateWithName(sourceHanName as CFString, size, nil)
            if CTFontCopyPostScriptName(sourceHan) as String == sourceHanName {
                return sourceHan
            }
        }
        let name: String
        switch weight {
        case .medium: name = "PingFangSC-Regular"
        case .semibold:
            name = "PingFangSC-Medium"
        case .bold: name = "PingFangSC-Medium"
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
        // Small text is rasterized once at the panel's native pixel size and
        // copied as whole pixels. This follows the bitmap-font approach used
        // by the NOTE4 reference firmware and TransitInk: it keeps stems on
        // the pixel grid and avoids the fuzzy or merged strokes produced when
        // a supersampled CJK outline is thresholded as a complete frame.
        // The reference font only has a native 16 px regular face. Smaller
        // labels stay on the 4x coverage renderer; forcing 9–13 px outlines
        // through a 1x threshold was the source of the thin, broken preview.
        if size >= 14, size <= 18, gray == 0,
           drawNativePixelLine(text, at: point, size: size, weight: weight, in: context) {
            return
        }
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
        let textWidth = measure(text, size: size, weight: weight)
        draw(
            text,
            at: CGPoint(x: floor(rightEdge - textWidth), y: y),
            size: size,
            weight: weight,
            gray: gray,
            in: context
        )
    }

    /// Draw a CoreText line as a native-resolution binary glyph mask.
    ///
    /// The main canvas is 4x for large-title antialiasing. Each filled 1pt
    /// rectangle here therefore becomes one exact 4x4 source block and one
    /// exact physical E Ink pixel after packing—there is no second resample.
    @discardableResult
    private static func drawNativePixelLine(
        _ text: String,
        at point: CGPoint,
        size: CGFloat,
        weight: FontWeight,
        in context: CGContext
    ) -> Bool {
        guard !text.isEmpty else { return true }
        let textLine = line(text, size: size, weight: weight)
        let textWidth = CGFloat(CTLineGetTypographicBounds(textLine, nil, nil, nil))
        let textFont = font(size: size, weight: weight)
        let ascent = CTFontGetAscent(textFont)
        let descent = CTFontGetDescent(textFont)
        let padding = 2
        let bitmapWidth = max(1, Int(ceil(textWidth)) + padding * 2)
        let bitmapHeight = max(1, Int(ceil(ascent + descent)) + padding * 2)
        var pixels = [UInt8](repeating: 255, count: bitmapWidth * bitmapHeight)
        guard let bitmap = CGContext(
            data: &pixels,
            width: bitmapWidth,
            height: bitmapHeight,
            bitsPerComponent: 8,
            bytesPerRow: bitmapWidth,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return false }

        bitmap.setFillColor(gray: 1, alpha: 1)
        bitmap.fill(CGRect(x: 0, y: 0, width: bitmapWidth, height: bitmapHeight))
        bitmap.setShouldAntialias(true)
        bitmap.setAllowsAntialiasing(true)
        bitmap.setShouldSmoothFonts(false)
        bitmap.setAllowsFontSmoothing(false)
        bitmap.textPosition = CGPoint(x: CGFloat(padding), y: CGFloat(padding) + descent)
        CTLineDraw(textLine, bitmap)

        context.saveGState()
        context.setFillColor(gray: 0, alpha: 1)
        let originX = floor(point.x) - CGFloat(padding)
        let originY = floor(point.y - descent) - CGFloat(padding)
        // A neutral 50% cutoff produces the same deterministic 1-bit mask as
        // the open-source NOTE4 glyph generator (threshold 128).
        for row in 0..<bitmapHeight {
            for column in 0..<bitmapWidth where pixels[row * bitmapWidth + column] < 128 {
                context.fill(CGRect(
                    x: originX + CGFloat(column),
                    // Bitmap memory is top-to-bottom while the renderer's
                    // Quartz coordinates are bottom-to-top.
                    y: originY + CGFloat(bitmapHeight - 1 - row),
                    width: 1,
                    height: 1
                ))
            }
        }
        context.restoreGState()
        return true
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
