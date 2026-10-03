import AppKit
import Foundation

@main
enum CalendarPreview {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12))!
        let examples: [(Int, String)] = [
            (1, "客户会议"), (7, "白露"), (10, "写视频脚本"),
            (11, "看书"), (14, "拍摄剪辑"), (17, "发布视频"),
            (21, "出门"), (22, "换牌申请"), (23, "提交项目方案"),
            (23, "整理资料"), (23, "回复客户邮件"), (23, "检查项目进度"),
            (25, "中秋节聚会")
        ]
        let items = examples.enumerated().map { index, example in
            ReminderItem(
                syncId: "preview-\(index)", title: example.1,
                dueAt: calendar.date(from: DateComponents(
                    year: 2026, month: 9, day: example.0, hour: 10
                )),
                hasDueTime: true, completed: false, priority: 0, updatedAt: now
            )
        }
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for (name, isDetail) in [("calendar-month", false), ("calendar-day", true)] {
            let packed = try ZectrixDisplayRenderer.renderCalendar(
                items, monthOffset: 0, selectedDay: 23,
                selectingDay: true, dayDetail: isDetail, detailPage: 0, generatedAt: now
            )
            let bytes = [UInt8](packed)
            var grayscale = [UInt8](repeating: 255, count: 400 * 300)
            for pixel in grayscale.indices where bytes[pixel / 8] & UInt8(0x80 >> (pixel % 8)) == 0 {
                grayscale[pixel] = 0
            }
            let provider = CGDataProvider(data: Data(grayscale) as CFData)!
            let image = CGImage(
                width: 400, height: 300, bitsPerComponent: 8, bitsPerPixel: 8,
                bytesPerRow: 400, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
            )!
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            try png.write(to: destination.appendingPathComponent("\(name).png"), options: .atomic)
        }
        let sixWeekDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 12))!
        let packed = try ZectrixDisplayRenderer.renderCalendar(
            items, monthOffset: 0, selectedDay: 15,
            selectingDay: true, dayDetail: false, detailPage: 0, generatedAt: sixWeekDate
        )
        let bytes = [UInt8](packed)
        var grayscale = [UInt8](repeating: 255, count: 400 * 300)
        for pixel in grayscale.indices where bytes[pixel / 8] & UInt8(0x80 >> (pixel % 8)) == 0 {
            grayscale[pixel] = 0
        }
        let provider = CGDataProvider(data: Data(grayscale) as CFData)!
        let image = CGImage(
            width: 400, height: 300, bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: 400, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
        try png.write(to: destination.appendingPathComponent("calendar-month-six-weeks.png"), options: .atomic)
    }
}
