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

    static func displayDueLabel(
        for reminder: ReminderItem,
        relativeTo reference: Date = Date()
    ) -> String {
        guard let dueAt = reminder.dueAt else { return "今天" }
        let calendar = Calendar.current
        let time = DateFormatter()
        time.dateFormat = "HH:mm"
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
        let date = DateFormatter()
        date.dateFormat = reminder.hasDueTime ? "M/d HH:mm" : "M月d日"
        return date.string(from: dueAt)
    }

    static func dayPeriod(
        for reminder: ReminderItem,
        relativeTo reference: Date = Date()
    ) -> DayPeriod? {
        guard reminder.hasDueTime,
              let dueAt = reminder.dueAt,
              Calendar.current.isDate(dueAt, inSameDayAs: reference) else { return nil }
        switch Calendar.current.component(.hour, from: dueAt) {
        case ..<12: return .morning
        case 12..<17: return .afternoon
        default: return .evening
        }
    }

    enum RenderError: Error {
        case contextCreationFailed
    }
}
