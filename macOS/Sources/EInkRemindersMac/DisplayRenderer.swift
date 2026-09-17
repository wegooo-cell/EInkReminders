import Foundation

/// Shared layout helpers used by the NOTE4 renderer.
enum DisplayRenderer {
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

    /// 事项右侧的到期标签；日历（含时区）由调用方注入，默认跟随系统。
    static func displayDueLabel(
        for reminder: ReminderItem,
        relativeTo reference: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let dueAt = reminder.dueAt else { return "今天" }

        let time = fixedFormatter("HH:mm", calendar: calendar)

        if calendar.isDate(dueAt, inSameDayAs: reference) {
            return reminder.hasDueTime ? time.string(from: dueAt) : "今天"
        }

        if let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: reference)
        ), calendar.isDate(dueAt, inSameDayAs: tomorrow) {
            return reminder.hasDueTime ? "明天 \(time.string(from: dueAt))" : "明天"
        }

        let date = fixedFormatter(
            reminder.hasDueTime ? "M/d HH:mm" : "M月d日",
            calendar: calendar
        )
        return date.string(from: dueAt)
    }

    /// 「今天」视图的上午 / 下午 / 今晚分段；日历（含时区）由调用方注入，默认跟随系统。
    static func dayPeriod(
        for reminder: ReminderItem,
        relativeTo reference: Date = Date(),
        calendar: Calendar = .current
    ) -> DayPeriod? {
        guard reminder.hasDueTime,
              let dueAt = reminder.dueAt,
              calendar.isDate(dueAt, inSameDayAs: reference) else { return nil }

        switch calendar.component(.hour, from: dueAt) {
        case ..<12: return .morning
        case 12..<17: return .afternoon
        default: return .evening
        }
    }

    /// 按固定格式输出日期的格式化器：不受系统 12 / 24 小时制设置影响，日历与时区取自调用方。
    private static func fixedFormatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()

        // 固定格式必须配 POSIX locale：否则系统设为 12 小时制时，
        // "HH:mm" 会被改写成「上午10:00」，标签变宽，可能压住较长的标题。
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format

        return formatter
    }

    enum RenderError: Error {
        case contextCreationFailed
    }
}
