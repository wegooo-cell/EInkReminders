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
    draw(footer, x: 12, y: 8, size: 10, weight: .medium, in: context)
}

private let menuItems = [
    "切换视图", "立即同步", "同步状态", "Wi-Fi 与网络", "刷新屏幕", "设备信息",
    "重启设备", "清除画面缓存", "恢复出厂设置", "返回提醒事项"
]

private func menuFrame(selected: Int) -> Data {
    makeFrame { context in
        let page = selected < 6 ? 0 : 1
        chrome("\(page + 1) / 2", in: context)
        let range = page == 0 ? 0..<6 : 6..<10
        var top: CGFloat = 244
        for index in range {
            let bottom = top - 32
            if index == selected { dither(CGRect(x: 7, y: bottom + 1, width: 386, height: 30), in: context) }
            circle(x: 15, y: bottom + 6, in: context)
            draw(menuItems[index], x: 51, y: bottom + 8, size: 18, weight: .semibold, in: context)
            drawRight("›", right: 383, y: bottom + 8, size: 20, weight: .semibold, in: context)
            top = bottom
        }
    }
}

private let smartViews = [
    ("今天", "calendar"),
    ("计划", "calendar.badge.clock"),
    ("全部", "tray.full"),
    ("完成", "checkmark")
]

private func drawSystemSymbol(_ name: String, in rect: CGRect, context: CGContext) {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil),
          let image = base.withSymbolConfiguration(.init(pointSize: 24, weight: .medium)) else { return }
    var proposed = CGRect(origin: .zero, size: image.size)
    guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return }
    context.saveGState()
    context.interpolationQuality = .none
    context.draw(cgImage, in: rect)
    context.restoreGState()
}

private func viewPickerFrame(selected: Int) -> Data {
    makeFrame { context in
        draw("切换视图", x: 13, y: 257, size: 34, weight: .bold, in: context)
        drawRight("1 / 1", right: 387, y: 269, size: 16, weight: .semibold, in: context)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 8, y: 27, width: 384, height: 1))
        draw("上/下选择 · OK 进入 · 长按上键返回", x: 12, y: 8, size: 10, weight: .medium, in: context)

        let cards = [
            CGRect(x: 12, y: 142, width: 182, height: 84),
            CGRect(x: 206, y: 142, width: 182, height: 84),
            CGRect(x: 12, y: 45, width: 182, height: 84),
            CGRect(x: 206, y: 45, width: 182, height: 84)
        ]
        for index in smartViews.indices {
            let card = cards[index]
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
            drawSystemSymbol(smartViews[index].1,
                             in: CGRect(x: card.minX + 16, y: card.maxY - 36, width: 24, height: 24),
                             context: context)
            draw(smartViews[index].0, x: card.minX + 16, y: card.minY + 13,
                 size: 19, weight: .semibold, in: context)
        }
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
             size: 13, weight: .medium, in: context)

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
        drawCentered("连接热点，访问 192.168.4.1", y: 17, size: 11, weight: .medium, in: context)
    }
}

private func wifiConnectingFrame() -> Data {
    makeFrame { context in
        drawCentered("正在连接 Wi-Fi", y: 191, size: 30, weight: .bold, in: context)
        drawCentered("正在验证网络和密码，请稍候", y: 143, size: 16, weight: .medium, in: context)
        drawCentered("请保持 iPhone 与设备热点连接", y: 51, size: 13, weight: .medium, in: context)
    }
}

private func wifiConnectedFrame() -> Data {
    makeFrame { context in
        drawCentered("Wi-Fi 已连接", y: 199, size: 32, weight: .bold, in: context)
        drawCentered("设备地址", y: 156, size: 16, weight: .medium, in: context)
        drawCentered("请在 Mac App 中使用下面的地址", y: 69, size: 14, weight: .medium, in: context)
        drawCentered("正在进入提醒事项", y: 34, size: 12, weight: .medium, in: context)
    }
}

var frames = menuItems.indices.map(menuFrame)
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

precondition(frames.count == 36)
let output = frames.reduce(into: Data()) { $0.append($1) }
precondition(output.count == frames.count * frameBytes)
let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "main/settings_frames.bin")
try output.write(to: destination, options: .atomic)
print("Wrote \(frames.count) frames (\(output.count) bytes) to \(destination.path)")

if CommandLine.arguments.count > 2 {
    let packed = [UInt8](frames[10])
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
    let sampleCounts = ["3", "6", "8", "12"]
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
