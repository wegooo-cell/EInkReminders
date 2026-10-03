import AppKit
import CoreGraphics
import CoreText
import Foundation

private let width = 400
private let height = 300
private let frameBytes = width * height / 8
private enum Weight { case medium, semibold, bold }

private func font(_ size: CGFloat, _ weight: Weight) -> CTFont {
    let name = weight == .medium ? "PingFangSC-Medium" : "PingFangSC-Semibold"
    return CTFontCreateWithName(name as CFString, size, nil)
}

private func line(_ value: String, _ size: CGFloat, _ weight: Weight) -> CTLine {
    CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font(size, weight),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
    ]))
}

private func draw(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: Weight, in context: CGContext) {
    context.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line(value, size, weight), context)
}

private func drawRight(_ value: String, right: CGFloat, y: CGFloat, size: CGFloat, weight: Weight, in context: CGContext) {
    let text = line(value, size, weight)
    let measured = CGFloat(CTLineGetTypographicBounds(text, nil, nil, nil))
    context.textPosition = CGPoint(x: floor(right - measured), y: y)
    CTLineDraw(text, context)
}

private func drawCentered(_ value: String, y: CGFloat, size: CGFloat, weight: Weight, in context: CGContext) {
    let text = line(value, size, weight)
    let measured = CGFloat(CTLineGetTypographicBounds(text, nil, nil, nil))
    context.textPosition = CGPoint(x: floor((CGFloat(width) - measured) / 2), y: y)
    CTLineDraw(text, context)
}

private func drawWhiteIconGlyph(_ value: String, centerX: CGFloat, baseline: CGFloat,
                               size: CGFloat, in context: CGContext) {
    let text = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font(size, .semibold),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
    ]))
    let measured = CGFloat(CTLineGetTypographicBounds(text, nil, nil, nil))
    context.textPosition = CGPoint(x: floor(centerX - measured / 2), y: baseline)
    CTLineDraw(text, context)
}

private func dither(_ rect: CGRect, in context: CGContext) {
    context.setFillColor(gray: 0, alpha: 1)
    for y in stride(from: Int(rect.minY), to: Int(rect.maxY), by: 4) {
        let offset = ((y - Int(rect.minY)) / 4 % 2) * 2
        for x in stride(from: Int(rect.minX) + offset, to: Int(rect.maxX), by: 4) {
            context.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }
}

private func circle(x: CGFloat, y: CGFloat, in context: CGContext) {
    context.setStrokeColor(gray: 0, alpha: 1)
    context.setLineWidth(2)
    context.strokeEllipse(in: CGRect(x: x, y: y, width: 20, height: 20).insetBy(dx: 1, dy: 1))
}

private func makeFrame(_ drawing: (CGContext) -> Void) -> Data {
    var pixels = [UInt8](repeating: 255, count: width * height)
    let context = CGContext(
        data: &pixels, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    context.setShouldAntialias(true)
    context.setShouldSmoothFonts(false)
    context.setAllowsFontSmoothing(false)
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    drawing(context)
    var packed = [UInt8](repeating: 0xFF, count: frameBytes)
    for index in pixels.indices where pixels[index] < 128 {
        packed[index / 8] &= ~UInt8(0x80 >> (index % 8))
    }
    return Data(packed)
}

private func chrome(_ rightLabel: String, footer: String = "上/下选择 · OK 确认 · 长按上键返回", in context: CGContext) {
    draw("设置", x: 13, y: 257, size: 39, weight: .bold, in: context)
    drawRight(rightLabel, right: 387, y: 269, size: 16, weight: .semibold, in: context)
    context.setFillColor(gray: 0, alpha: 1)
    context.fill(CGRect(x: 8, y: 27, width: 384, height: 1))
    draw(footer, x: 12, y: 8, size: 14, weight: .medium, in: context)
}

private let menuItems = [
    "切换视图", "立即同步", "同步状态", "Wi-Fi 与网络", "刷新屏幕", "设备信息",
    "重启设备", "清除画面缓存", "恢复出厂设置", "你想看一只狗牛吗？",
    "待机显示反色", "返回提醒事项"
]

private func menuFrame(selected: Int, standbyInverted: Bool = false) -> Data {
    makeFrame { context in
        let page = selected < 6 ? 0 : 1
        chrome("\(page + 1) / 2", in: context)
        let range = page == 0 ? 0..<6 : 6..<12
        var top: CGFloat = 244
        for index in range {
            let bottom = top - 32
            if index == selected { dither(CGRect(x: 7, y: bottom + 1, width: 386, height: 30), in: context) }
            circle(x: 15, y: bottom + 6, in: context)
            draw(menuItems[index], x: 51, y: bottom + 8, size: 18, weight: .semibold, in: context)
            if index == 10 && index == selected {
                drawRight(standbyInverted ? "白底黑字" : "黑底白字",
                          right: 383, y: bottom + 8, size: 16, weight: .medium, in: context)
            } else {
                drawRight("›", right: 383, y: bottom + 8, size: 20, weight: .semibold, in: context)
            }
            top = bottom
        }
    }
}

private let smartViews = ["提醒事项", "备忘录", "待机显示", "日历"]
private let reminderViews = ["今天", "全部", "计划", "完成"]

private let viewCards = [
    CGRect(x: 12, y: 142, width: 182, height: 84),
    CGRect(x: 206, y: 142, width: 182, height: 84),
    CGRect(x: 12, y: 45, width: 182, height: 84),
    CGRect(x: 206, y: 45, width: 182, height: 84)
]

private func stroke(_ context: CGContext, _ points: [CGPoint], width: CGFloat = 2) {
    guard let first = points.first else { return }
    context.setStrokeColor(gray: 0, alpha: 1)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: first)
    for point in points.dropFirst() { context.addLine(to: point) }
    context.strokePath()
}

private func drawIcon(_ kind: String, x: CGFloat, y: CGFloat, in context: CGContext) {
    context.setStrokeColor(gray: 0, alpha: 1)
    context.setFillColor(gray: 0, alpha: 1)
    context.setLineWidth(2)
    switch kind {
    case "today":
        // Reuse the Plan calendar unchanged, with a small clock badge at the
        // lower right. A white separation ring keeps both 1-bit shapes clear.
        drawSystemSymbol("calendar", in: CGRect(x: x, y: y, width: 32, height: 32), context: context)
        context.setFillColor(gray: 1, alpha: 1)
        context.fillEllipse(in: CGRect(x: x + 17, y: y, width: 15, height: 15))
        context.setFillColor(gray: 0, alpha: 1)
        context.fillEllipse(in: CGRect(x: x + 19, y: y + 2, width: 12, height: 12))
        context.setStrokeColor(gray: 1, alpha: 1)
        context.setLineWidth(1.4)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: x + 25, y: y + 11))
        context.addLine(to: CGPoint(x: x + 25, y: y + 8))
        context.addLine(to: CGPoint(x: x + 28, y: y + 8))
        context.strokePath()
    case "calendar":
        drawSystemSymbol("calendar", in: CGRect(x: x, y: y, width: 32, height: 32), context: context)
    case "plan":
        drawSystemSymbol("calendar", in: CGRect(x: x, y: y, width: 32, height: 32), context: context)
    case "all":
        stroke(context, [CGPoint(x: x, y: y + 15), CGPoint(x: x + 8, y: y + 27),
                         CGPoint(x: x + 23, y: y + 27), CGPoint(x: x + 30, y: y + 15),
                         CGPoint(x: x + 30, y: y + 2), CGPoint(x: x, y: y + 2),
                         CGPoint(x: x, y: y + 15)])
        stroke(context, [CGPoint(x: x, y: y + 15), CGPoint(x: x + 9, y: y + 15),
                         CGPoint(x: x + 12, y: y + 12), CGPoint(x: x + 18, y: y + 12),
                         CGPoint(x: x + 21, y: y + 15), CGPoint(x: x + 30, y: y + 15)])
    case "completed":
        stroke(context, [CGPoint(x: x + 3, y: y + 14), CGPoint(x: x + 11, y: y + 5),
                         CGPoint(x: x + 29, y: y + 27)], width: 4.2)
    case "notes":
        let shape = CGPath(roundedRect: CGRect(x: x, y: y, width: 30, height: 30),
                           cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.saveGState()
        context.addPath(shape)
        context.clip()
        context.fill(CGRect(x: x, y: y + 22, width: 30, height: 8))
        context.restoreGState()
        context.addPath(shape)
        context.strokePath()
        for yy in [7, 12, 17] { context.fill(CGRect(x: x + 6, y: y + CGFloat(yy), width: 18, height: 1)) }
    case "standby":
        context.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: 30, height: 30),
                               cornerWidth: 6, cornerHeight: 6, transform: nil))
        context.fillPath()
        context.setFillColor(gray: 1, alpha: 1)
        context.fillEllipse(in: CGRect(x: x + 4, y: y + 9, width: 11, height: 11))
        context.fill(CGRect(x: x + 18, y: y + 10, width: 8, height: 9))
        context.setFillColor(gray: 0, alpha: 1)
        stroke(context, [CGPoint(x: x + 6, y: y + 14), CGPoint(x: x + 8, y: y + 12), CGPoint(x: x + 12, y: y + 17)], width: 1)
        context.fill(CGRect(x: x + 19, y: y + 16, width: 6, height: 1))
        context.fill(CGRect(x: x + 19, y: y + 13, width: 5, height: 1))
    case "reminders":
        context.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: 30, height: 30),
                               cornerWidth: 6, cornerHeight: 6, transform: nil))
        context.strokePath()
        for yy in [7, 15, 23] {
            context.strokeEllipse(in: CGRect(x: x + 4, y: y + CGFloat(yy) - 2, width: 4, height: 4))
            // Two source pixels survive the 26/32 card-icon reduction as a
            // crisp visible line on the final 1-bit panel.
            context.fill(CGRect(x: x + 11, y: y + CGFloat(yy) - 0.5, width: 14, height: 2))
        }
    default: break
    }
}

private func drawCardIcon(_ kind: String, in card: CGRect, context: CGContext) {
    // The reference uses icons about 14% as wide as a card. Keep every icon
    // on the same 26-pixel optical grid instead of shrinking card typography.
    context.saveGState()
    context.translateBy(x: card.minX + 18, y: card.maxY - 44)
    context.scaleBy(x: 26.0 / 32.0, y: 26.0 / 32.0)
    drawIcon(kind, x: 0, y: 0, in: context)
    context.restoreGState()
}

private func drawSystemSymbol(_ name: String, in rect: CGRect, context: CGContext) {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil),
          let image = base.withSymbolConfiguration(.init(pointSize: 28, weight: .semibold)) else { return }
    var proposed = CGRect(origin: .zero, size: image.size)
    guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return }
    context.saveGState()
    context.interpolationQuality = .none
    context.draw(cgImage, in: rect)
    context.restoreGState()
}

private func viewPickerFrame(selected: Int) -> Data {
    makeFrame { context in
        draw("切换视图", x: 13, y: 257, size: 39, weight: .bold, in: context)
        drawRight("\(selected + 1) / 4", right: 387, y: 269, size: 16, weight: .semibold, in: context)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 8, y: 27, width: 384, height: 1))
        draw("上/下选择 · OK 进入 · 长按上键返回", x: 12, y: 8, size: 14, weight: .medium, in: context)
        for index in smartViews.indices {
            let card = viewCards[index]
            let path = CGPath(roundedRect: card, cornerWidth: 13, cornerHeight: 13, transform: nil)
            if index == selected {
                dither(card.insetBy(dx: 2, dy: 2), in: context)
                context.setLineWidth(3)
            } else {
                context.setLineWidth(1)
            }
            context.setStrokeColor(gray: 0, alpha: 1)
            context.addPath(path)
            context.strokePath()
            drawCardIcon(["reminders", "notes", "standby", "calendar"][index],
                         in: card, context: context)
            draw(smartViews[index], x: card.minX + 16, y: card.minY + 13,
                 size: 19, weight: .semibold, in: context)
            stroke(context, [CGPoint(x: card.maxX - 23, y: card.midY + 6),
                             CGPoint(x: card.maxX - 17, y: card.midY),
                             CGPoint(x: card.maxX - 23, y: card.midY - 6)], width: 2.5)
        }
    }
}

private func reminderPickerFrame(selected: Int) -> Data {
    makeFrame { context in
        draw("提醒事项", x: 13, y: 257, size: 34, weight: .bold, in: context)
        drawRight("1 / 4", right: 387, y: 269, size: 16, weight: .semibold, in: context)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 8, y: 27, width: 384, height: 1))
        draw("上/下选择 · OK 打开 · 长按上键返回", x: 12, y: 8, size: 14, weight: .medium, in: context)
        for index in reminderViews.indices {
            let card = viewCards[index]
            let path = CGPath(roundedRect: card, cornerWidth: 13, cornerHeight: 13, transform: nil)
            if index == selected {
                dither(card.insetBy(dx: 2, dy: 2), in: context)
                context.setLineWidth(3)
            } else { context.setLineWidth(1) }
            context.setStrokeColor(gray: 0, alpha: 1)
            context.addPath(path)
            context.strokePath()
            drawCardIcon(["today", "all", "plan", "completed"][index],
                         in: card, context: context)
            draw(reminderViews[index], x: card.minX + 16, y: card.minY + 13,
                 size: 19, weight: .semibold, in: context)
        }
    }
}

private func standbyFrame(style: Int, hoursMode: Bool) -> Data {
    // The approved screens are the source of truth for the static pixel-font
    // labels and spacing. Clear only the fields supplied by the device clock
    // and current reminder. Both former countdown frame slots use the same
    // current-time design, so switching style does not change with duration.
    let file = style == 0 ? "04-standby-large-pixel.png" : "05-standby-tall-pixel.png"
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let source = root.appendingPathComponent("previews/approval-2026-09-23/\(file)")
    guard let bitmap = NSBitmapImageRep(data: try! Data(contentsOf: source)),
          bitmap.pixelsWide == width, bitmap.pixelsHigh == height else {
        fatalError("Missing approved StandBy preview: \(source.path)")
    }
    var packed = [UInt8](repeating: 0, count: frameBytes)
    for y in 0..<height { for x in 0..<width {
        let cleared: Bool
        if style == 0 {
            cleared = (y >= 40 && y < 240)
                || (x >= 124 && x < 278 && y >= 265)
                || (x >= 278 && y >= 265)
        } else {
            cleared = (x < 280 && y >= 16 && y < 284)
                || (x >= 282 && y >= 28 && y < 78)
                || (x >= 280 && y >= 236 && y < 266)
                || (x >= 280 && y >= 266)
        }
        let isWhite = !cleared && (bitmap.colorAt(x: x, y: y)?.whiteComponent ?? 0) >= 0.5
        if isWhite { packed[(y * width + x) / 8] |= UInt8(0x80 >> ((y * width + x) % 8)) }
    }}
    return Data(packed)
}

private func calendarFrame() -> Data {
    makeFrame { context in
        draw("日历", x: 13, y: 257, size: 36, weight: .bold, in: context)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 8, y: 239, width: 384, height: 1))
        let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        for (index, label) in weekdays.enumerated() {
            draw(label, x: 17 + CGFloat(index * 55), y: 220, size: 14, weight: .semibold, in: context)
        }
        for row in 0..<6 {
            let y = 199 - CGFloat(row * 28)
            context.fill(CGRect(x: 8, y: y, width: 384, height: 1))
        }
        context.fill(CGRect(x: 8, y: 31, width: 384, height: 1))
        draw("上/下月份 · OK 今天 · 长按上键返回", x: 10, y: 8,
             size: 14, weight: .medium, in: context)
    }
}

private func detailBase(title: String, labels: [String], footer: String = "OK 执行 · 长按上键返回") -> Data {
    makeFrame { context in
        chrome(title, footer: footer, in: context)
        var y: CGFloat = 202
        for label in labels {
            draw(label, x: 24, y: y, size: 17, weight: .semibold, in: context)
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 20, y: y - 8, width: 360, height: 1))
            y -= 48
        }
    }
}

private func networkMenuFrame(selected: Int) -> Data {
    makeFrame { context in
        chrome("Wi-Fi 与网络", footer: "上/下选择 · OK 执行 · 长按上键返回", in: context)
        draw("当前网络", x: 24, y: 205, size: 16, weight: .semibold, in: context)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 20, y: 190, width: 360, height: 1))
        draw("使用保存的密码重连，或配置新的网络", x: 24, y: 166,
             size: 14, weight: .medium, in: context)

        let choices = ["重连 Wi-Fi", "重新配网"]
        for index in choices.indices {
            let bottom = CGFloat(104 - index * 43)
            if index == selected {
                dither(CGRect(x: 20, y: bottom, width: 360, height: 35), in: context)
            }
            circle(x: 31, y: bottom + 7, in: context)
            draw(choices[index], x: 70, y: bottom + 9, size: 18,
                 weight: .semibold, in: context)
        }
    }
}

private func messageFrame(
    title: String,
    detail: String,
    footer: String = "OK 返回设置 · 长按上键返回"
) -> Data {
    makeFrame { context in
        chrome("操作结果", footer: footer, in: context)
        let titleLine = line(title, 27, .semibold)
        let titleWidth = CGFloat(CTLineGetTypographicBounds(titleLine, nil, nil, nil))
        context.textPosition = CGPoint(x: floor((400 - titleWidth) / 2), y: 162)
        CTLineDraw(titleLine, context)
        let detailLine = line(detail, 15, .medium)
        let detailWidth = CGFloat(CTLineGetTypographicBounds(detailLine, nil, nil, nil))
        context.textPosition = CGPoint(x: floor((400 - detailWidth) / 2), y: 122)
        CTLineDraw(detailLine, context)
    }
}

private func confirmFrame(title: String, detail: String, action: String, selected: Int) -> Data {
    makeFrame { context in
        chrome("确认操作", in: context)
        let titleLine = line(title, 27, .semibold)
        let titleWidth = CGFloat(CTLineGetTypographicBounds(titleLine, nil, nil, nil))
        context.textPosition = CGPoint(x: floor((400 - titleWidth) / 2), y: 189)
        CTLineDraw(titleLine, context)
        let detailLine = line(detail, 14, .medium)
        let detailWidth = CGFloat(CTLineGetTypographicBounds(detailLine, nil, nil, nil))
        context.textPosition = CGPoint(x: floor((400 - detailWidth) / 2), y: 155)
        CTLineDraw(detailLine, context)
        let choices = ["取消", action]
        for index in 0..<2 {
            let bottom = CGFloat(102 - index * 38)
            if index == selected { dither(CGRect(x: 65, y: bottom, width: 270, height: 32), in: context) }
            circle(x: 79, y: bottom + 6, in: context)
            draw(choices[index], x: 116, y: bottom + 8, size: 18, weight: .semibold, in: context)
        }
    }
}

private func wifiSetupFrame() -> Data {
    makeFrame { context in
        drawCentered("连接 Wi-Fi", y: 258, size: 30, weight: .bold, in: context)
        drawCentered("用 iPhone 相机扫描并加入热点", y: 49, size: 14, weight: .semibold, in: context)
        drawCentered("连接热点，访问 192.168.4.1", y: 17, size: 14, weight: .medium, in: context)
    }
}

private func wifiConnectingFrame() -> Data {
    makeFrame { context in
        drawCentered("正在连接 Wi-Fi", y: 191, size: 30, weight: .bold, in: context)
        drawCentered("正在验证网络和密码，请稍候", y: 143, size: 16, weight: .medium, in: context)
        drawCentered("请保持 iPhone 与设备热点连接", y: 51, size: 14, weight: .medium, in: context)
    }
}

private func wifiConnectedFrame() -> Data {
    makeFrame { context in
        drawCentered("Wi-Fi 已连接", y: 199, size: 32, weight: .bold, in: context)
        drawCentered("设备地址", y: 156, size: 16, weight: .medium, in: context)
        drawCentered("请在 Mac App 中使用下面的地址", y: 69, size: 14, weight: .medium, in: context)
        drawCentered("正在进入提醒事项", y: 34, size: 14, weight: .medium, in: context)
    }
}

// Keep the existing 0...47 indexes stable: they are referenced by firmware.
var frames = (0..<11).map { menuFrame(selected: $0) }
frames.append(contentsOf: smartViews.indices.map(viewPickerFrame))
frames.append(detailBase(title: "同步状态", labels: ["上次同步", "待上传操作", "Mac 状态"]))
frames.append(networkMenuFrame(selected: 0))
frames.append(detailBase(title: "设备信息", labels: ["固件版本", "电池电量", "可用存储"]))
frames.append(messageFrame(
    title: "已请求同步", detail: "Mac 在线时会立即处理",
    footer: "同步后自动显示提醒事项 · 长按上键设置"
))
frames.append(messageFrame(title: "屏幕刷新完成", detail: "已执行一次完整刷新"))
frames.append(messageFrame(
    title: "画面缓存已清除", detail: "Mac 正在重新发送画面",
    footer: "同步后自动显示提醒事项 · 长按上键设置"
))
frames.append(messageFrame(
    title: "正在切换视图", detail: "Mac 正在准备新的提醒事项",
    footer: "同步后自动显示新视图 · 长按上键设置"
))

let confirmations = [
    ("重新配置 Wi-Fi？", "新网络成功前保留当前配置", "确认重新配网"),
    ("重启设备？", "已保存的设置不会丢失", "确认重启"),
    ("清除画面缓存？", "提醒事项数据不会被删除", "确认清除"),
    ("恢复出厂设置？", "Wi-Fi 和同步状态将被清除", "确认恢复")
]
for confirmation in confirmations {
    frames.append(confirmFrame(title: confirmation.0, detail: confirmation.1, action: confirmation.2, selected: 0))
    frames.append(confirmFrame(title: confirmation.0, detail: confirmation.1, action: confirmation.2, selected: 1))
}

frames.append(wifiSetupFrame())
frames.append(wifiConnectingFrame())
frames.append(wifiConnectedFrame())
frames.append(networkMenuFrame(selected: 1))
frames.append(messageFrame(
    title: "正在重连 Wi-Fi", detail: "使用设备中已保存的网络和密码",
    footer: "请稍候"
))
frames.append(messageFrame(
    title: "Wi-Fi 已重新连接", detail: "正在恢复提醒事项同步",
    footer: "即将返回提醒事项"
))
frames.append(messageFrame(
    title: "Wi-Fi 重连失败", detail: "请检查路由器，或选择重新配网",
    footer: "OK 返回网络设置 · 长按上键返回"
))

// Mac 不在线时，列表按键需要的选中帧和确认帧都无法生成，固件显示这一帧作为兜底反馈。
frames.append(messageFrame(
    title: "等待 Mac 连接", detail: "Mac App 在线后，按键选择和完成才会生效",
    footer: "稍后自动返回提醒事项 · 长按上键设置"
))
frames.append(messageFrame(
    title: "正在切换备忘录", detail: "Mac 正在读取最近 15 天的备忘录",
    footer: "同步后自动显示备忘录 · 长按上键设置"
))
frames.append(contentsOf: reminderViews.indices.map(reminderPickerFrame))
frames.append(standbyFrame(style: 0, hoursMode: false))
frames.append(standbyFrame(style: 1, hoursMode: false))
frames.append(standbyFrame(style: 0, hoursMode: true))
frames.append(standbyFrame(style: 1, hoursMode: true))
frames.append(calendarFrame())
frames.append(menuFrame(selected: 11))
frames.append(menuFrame(selected: 10, standbyInverted: true))

precondition(frames.count == 50)
let output = frames.reduce(into: Data()) { $0.append($1) }
precondition(output.count == frames.count * frameBytes)
let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "main/settings_frames.bin")
try output.write(to: destination, options: .atomic)
print("Wrote \(frames.count) frames (\(output.count) bytes) to \(destination.path)")

if CommandLine.arguments.count > 2 {
    let packed = [UInt8](frames[39])
    var grayscale = [UInt8](repeating: 255, count: width * height)
    for index in grayscale.indices where packed[index / 8] & UInt8(0x80 >> (index % 8)) == 0 {
        grayscale[index] = 0
    }
    let previewContext = CGContext(
        data: &grayscale, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    // Preview the count layer that firmware draws dynamically from viewCounts.
    let sampleCounts = ["3", "8", "6"]
    let rightEdges: [CGFloat] = [181, 375, 181, 375]
    let baselines: [CGFloat] = [186, 186, 89, 89]
    for index in sampleCounts.indices {
        drawRight(sampleCounts[index], right: rightEdges[index], y: baselines[index],
                  size: 22, weight: .semibold, in: previewContext)
    }
    let provider = CGDataProvider(data: Data(grayscale) as CFData)!
    let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
        bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
    )!
    let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    let preview = URL(fileURLWithPath: CommandLine.arguments[2])
    try png.write(to: preview, options: .atomic)
    print("Wrote view picker preview to \(preview.path)")
}

if CommandLine.arguments.count > 3 {
    let directory = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for (name, index) in [
        ("view-picker", 11), ("standby-seconds", 43),
        ("standby-calendar", 44), ("standby-hours", 45),
        ("calendar", 47)
    ] {
        let packed = [UInt8](frames[index])
        var grayscale = [UInt8](repeating: 255, count: width * height)
        for pixel in grayscale.indices where packed[pixel / 8] & UInt8(0x80 >> (pixel % 8)) == 0 {
            grayscale[pixel] = 0
        }
        let provider = CGDataProvider(data: Data(grayscale) as CFData)!
        let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
        try png.write(to: directory.appendingPathComponent("note4-\(name).png"), options: .atomic)
    }
}

if CommandLine.arguments.count > 4 {
    func glyph(_ character: Character, width: Int, height: Int, pointSize: CGFloat, condensed: Bool) -> Data {
        var grayscale = [UInt8](repeating: 255, count: width * height)
        let context = CGContext(
            data: &grayscale, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(false)
        context.setAllowsFontSmoothing(false)
        let rounded = NSFont.systemFont(ofSize: pointSize, weight: .black)
            .fontDescriptor.withDesign(.rounded)
        let fontName = condensed ? "HelveticaNeue-CondensedBlack"
            : (rounded.flatMap { NSFont(descriptor: $0, size: pointSize) }?.fontName ?? "HelveticaNeue-Black")
        let digitFont = CTFontCreateWithName(fontName as CFString, pointSize, nil)
        let text = CTLineCreateWithAttributedString(NSAttributedString(string: String(character), attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): digitFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ]))
        if character == ":" && !condensed {
            context.setFillColor(gray: 0, alpha: 1)
            context.fillEllipse(in: CGRect(x: 5, y: 35, width: 23, height: 23))
            context.fillEllipse(in: CGRect(x: 5, y: 104, width: 23, height: 23))
        } else {
            context.translateBy(x: 0, y: condensed ? 7 : 5)
            context.scaleBy(x: condensed ? 0.32 : 0.55, y: condensed ? 1.03 : 1.0)
            context.textPosition = CGPoint(x: character == ":" ? 7 : 0, y: 0)
            CTLineDraw(text, context)
        }
        var packed = [UInt8](repeating: 0xFF, count: width * height / 8)
        for index in grayscale.indices where grayscale[index] < 128 {
            packed[index / 8] &= ~UInt8(0x80 >> (index % 8))
        }
        return Data(packed)
    }
    let characters = Array("0123456789:")
    let digits = characters.reduce(into: Data()) {
        $0.append(glyph($1, width: 80, height: 176, pointSize: 220, condensed: false))
    } + characters.reduce(into: Data()) {
        $0.append(glyph($1, width: 64, height: 256, pointSize: 340, condensed: true))
    }
    func weekdayGlyph(_ value: String) -> Data {
        let glyphWidth = 48, glyphHeight = 24
        var grayscale = [UInt8](repeating: 255, count: glyphWidth * glyphHeight)
        let context = CGContext(data: &grayscale, width: glyphWidth, height: glyphHeight,
                                bitsPerComponent: 8, bytesPerRow: glyphWidth,
                                space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        draw(value, x: 0, y: 3, size: 17, weight: .medium, in: context)
        var packed = [UInt8](repeating: 0xFF, count: glyphWidth * glyphHeight / 8)
        for pixel in grayscale.indices where grayscale[pixel] < 128 {
            packed[pixel / 8] &= ~UInt8(0x80 >> (pixel % 8))
        }
        return Data(packed)
    }
    let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
    let atlas = digits + weekdays.reduce(into: Data()) { $0.append(weekdayGlyph($1)) }
    let destination = URL(fileURLWithPath: CommandLine.arguments[4])
    try atlas.write(to: destination, options: .atomic)
    print("Wrote standby glyphs (\(atlas.count) bytes) to \(destination.path)")
    if CommandLine.arguments.count > 3 {
        let directory = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        for (name, frame, small, centerX, topY) in [
            ("standby-seconds-filled", 43, false, 200, 40),
            ("standby-calendar-filled", 44, true, 139, 21)
        ] {
            let packed = [UInt8](frames[frame])
            var grayscale = [UInt8](repeating: 255, count: width * height)
            for pixel in grayscale.indices where packed[pixel / 8] & UInt8(0x80 >> (pixel % 8)) == 0 {
                grayscale[pixel] = 0
            }
            let glyphWidth = small ? 64 : 80
            let glyphHeight = small ? 256 : 176
            let glyphBytes = glyphWidth * glyphHeight / 8
            let base = small ? 11 * 80 * 176 / 8 : 0
            let value = Array("13:05")
            let advance = small ? 58 : 76
            let colonAdvance = small ? 20 : 32
            let total = 4 * advance + colonAdvance
            var cursorX = centerX - total / 2
            let bitmaps = [UInt8](digits)
            for character in value {
                let index = character == ":" ? 10 : Int(character.wholeNumberValue!)
                for row in 0..<glyphHeight { for column in 0..<glyphWidth {
                    let pixel = row * glyphWidth + column
                    let glyphByte = bitmaps[base + index * glyphBytes + pixel / 8]
                    if glyphByte & UInt8(0x80 >> (pixel % 8)) == 0 {
                        let x = cursorX + column, y = topY + row
                        if x >= 0 && x < width && y >= 0 && y < height { grayscale[y * width + x] = 255 }
                    }
                }}
                cursorX += character == ":" ? colonAdvance : advance
            }
            let provider = CGDataProvider(data: Data(grayscale) as CFData)!
            let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
            )!
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            try png.write(to: directory.appendingPathComponent("note4-\(name).png"), options: .atomic)
        }
    }
}
