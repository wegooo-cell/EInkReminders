import EventKit
import Foundation

@MainActor
final class ReminderStore {
    private let eventStore = EKEventStore()
    private let identities: SyncIdentityStore

    init(identities: SyncIdentityStore) {
        self.identities = identities
    }

    var calendars: [EKCalendar] {
        eventStore.calendars(for: .reminder).sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    func requestAccess() async throws -> Bool {
        if #available(macOS 14.0, *) {
            return try await eventStore.requestFullAccessToReminders()
        }
        return try await withCheckedThrowingContinuation { continuation in
            eventStore.requestAccess(to: .reminder) { granted, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: granted) }
            }
        }
    }

    func fetchView(
        _ view: DeviceReminderView,
        calendarIdentifier: String?,
        includeAlertCandidates: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> ReminderViewSnapshot {
        // 未选择列表或所选列表已被删除时直接报错：谓词的 calendars 传 nil 会读取全部列表。
        guard let list = selectedCalendar(calendarIdentifier) else {
            throw StoreError.listUnavailable
        }

        let items: [ReminderItem]
        let totalCount: Int
        var alertCandidates: [ReminderItem] = []

        switch view {
        case .completed:
            let page = await fetchCompletedPage(in: list)
            items = page.items
            totalCount = page.totalCount

            if includeAlertCandidates {
                alertCandidates = await fetchIncomplete(in: list)
            }

        case .today, .scheduled, .all:
            let incomplete = await fetchIncomplete(in: list)
            if includeAlertCandidates { alertCandidates = incomplete }

            let visibleItems: [ReminderItem]
            switch view {
            case .today:
                visibleItems = incomplete.filter {
                    Self.belongsToToday($0, now: now, calendar: calendar)
                }
            case .scheduled:
                visibleItems = incomplete.filter { $0.dueAt != nil }
            case .all:
                visibleItems = incomplete
            case .completed:
                visibleItems = []
            }
            totalCount = visibleItems.count

            // Today and Scheduled are intentionally bounded so the device remains
            // quick even when the Apple list is very large. The All view has no
            // application-level item cap and is served on demand.
            let boundedItems = view == .all
                ? visibleItems
                : Array(visibleItems.prefix(20))
            items = view == .today
                ? Self.orderedLikeTodayScreen(boundedItems, now: now)
                : boundedItems
        }

        // An empty Today view may mean its work was finished. Check completed
        // reminders only in this case; every other empty smart view uses the
        // ordinary message and needs no extra EventKit query.
        let hasCompletedTodayItems: Bool
        if totalCount == 0 && view == .today {
            hasCompletedTodayItems = await hasCompletedTodayReminders(
                in: list, now: now, calendar: calendar
            )
        } else {
            hasCompletedTodayItems = false
        }
        let emptyState = ReminderEmptyState.resolve(
            view: view,
            visibleCount: totalCount,
            hasCompletedTodayItems: hasCompletedTodayItems
        )
        return ReminderViewSnapshot(
            items: items, totalCount: totalCount,
            emptyState: emptyState, alertCandidates: alertCandidates
        )
    }

    func apply(_ operation: DeviceOperation) throws {
        guard let appleId = operation.appleId ?? identities.appleId(for: operation.syncId) else {
            throw StoreError.reminderNotFound(operation.syncId)
        }

        guard let reminder = eventStore.calendarItem(withIdentifier: appleId) as? EKReminder else {
            // 提醒已被删除，或标识因 iCloud 全量重同步而失效：这条映射不会再用到。
            identities.remove(appleId: appleId)
            throw StoreError.reminderNotFound(operation.syncId)
        }

        identities.bind(syncId: operation.syncId, to: appleId)

        switch operation.type {
        case .setCompleted:
            let completed = operation.completed ?? true

            // 状态已经一致时不保存：重放同一条完成操作会反复改写 completionDate，产生多余的 iCloud 写入。
            guard reminder.isCompleted != completed else { return }

            reminder.isCompleted = completed
            reminder.completionDate = completed ? Date() : nil

        case .setDueAt:
            guard let dueAtEpochMs = operation.dueAtEpochMs, dueAtEpochMs > 0 else {
                throw StoreError.invalidDueDate
            }

            let date = Date(timeIntervalSince1970: TimeInterval(dueAtEpochMs) / 1_000)
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: date
            )
        }

        // 保存失败（例如列表只读）时带上标题，界面提示能看出是哪一项没有写回。
        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            throw StoreError.saveFailed(title: reminder.title ?? "未命名事项", underlying: error)
        }
    }

    private func toItem(_ reminder: EKReminder) -> ReminderItem {
        let appleId = reminder.calendarItemIdentifier
        let dueComponents = reminder.dueDateComponents
        let dueAt = dueComponents.flatMap { Calendar.current.date(from: $0) }
        return ReminderItem(
            syncId: identities.syncId(for: appleId),
            appleId: appleId,
            title: reminder.title ?? "未命名事项",
            notes: reminder.notes,
            dueAt: dueAt,
            hasDueTime: dueComponents?.hour != nil || dueComponents?.minute != nil,
            completed: reminder.isCompleted,
            priority: reminder.priority,
            updatedAt: reminder.lastModifiedDate ?? reminder.creationDate ?? Date()
        )
    }

    /// 读取匹配谓词的提醒；EventKit 在自己的线程回调，结果交回主 actor 后再处理。
    private func fetchReminders(matching predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
    }

    private func fetchIncomplete(in list: EKCalendar) async -> [ReminderItem] {
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: [list]
        )
        let reminders = await fetchReminders(matching: predicate)

        return reminders.map(toItem).sorted(by: ReminderStore.displayOrder)
    }

    /// 完成视图的一页：已完成提醒包含全部历史，先按更新时间排序，只把要显示的前 20 项转换成事项，
    /// 避免每次同步都为全部历史提醒逐项建立同步映射。
    private func fetchCompletedPage(in list: EKCalendar) async -> (items: [ReminderItem], totalCount: Int) {
        let predicate = eventStore.predicateForCompletedReminders(
            withCompletionDateStarting: nil,
            ending: nil,
            calendars: [list]
        )
        let completed = await fetchReminders(matching: predicate)
            .sorted(by: Self.recentlyUpdatedFirst)

        return (completed.prefix(20).map(toItem), completed.count)
    }

    private func hasCompletedTodayReminders(
        in list: EKCalendar, now: Date, calendar: Calendar
    ) async -> Bool {
        let predicate = eventStore.predicateForCompletedReminders(
            withCompletionDateStarting: nil,
            ending: nil,
            calendars: [list]
        )

        // toItem 属于主 actor：等结果回到主 actor 后再转换，不能在 EventKit 的回调线程里调用。
        let reminders = await fetchReminders(matching: predicate)

        return reminders.contains { reminder in
            guard let completedAt = reminder.completionDate,
                  calendar.isDate(completedAt, inSameDayAs: now) else { return false }

            return Self.belongsToToday(toItem(reminder), now: now, calendar: calendar)
        }
    }

    private func selectedCalendar(_ identifier: String?) -> EKCalendar? {
        identifier.flatMap { id in calendars.first { $0.calendarIdentifier == id } }
    }

    nonisolated static func belongsToToday(
        _ reminder: ReminderItem,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        // This project intentionally treats undated reminders as today's tasks.
        guard let dueAt = reminder.dueAt else { return true }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        // Match Reminders' Today behavior by including overdue incomplete items,
        // while excluding every future date—including tomorrow morning.
        return dueAt < tomorrow
    }

    /// 「今天」视图按屏幕的绘制顺序排列：NOTE4 先画不属于上午 / 下午 / 今晚分段的事项
    /// （逾期、只有日期、无日期），再按时段画当天有具体时间的事项。设备按列表顺序移动选中项，
    /// 顺序不一致时按下键会在屏幕上跳行。
    nonisolated static func orderedLikeTodayScreen(
        _ items: [ReminderItem],
        now: Date
    ) -> [ReminderItem] {
        let unsectioned = items.filter {
            DisplayRenderer.dayPeriod(for: $0, relativeTo: now) == nil
        }
        let sectioned = items.filter {
            DisplayRenderer.dayPeriod(for: $0, relativeTo: now) != nil
        }

        return unsectioned + sectioned
    }

    private static func displayOrder(_ lhs: ReminderItem, _ rhs: ReminderItem) -> Bool {
        switch (lhs.dueAt, rhs.dueAt) {
        case let (l?, r?): return l == r ? lhs.title < rhs.title : l < r
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return lhs.title.localizedCompare(rhs.title) == .orderedAscending
        }
    }

    /// 完成视图的顺序：最近更新的在前，更新时间相同按标题排列。缺少时间的提醒与 toItem 一致视为最新。
    private static func recentlyUpdatedFirst(_ lhs: EKReminder, _ rhs: EKReminder) -> Bool {
        let lhsUpdatedAt = lhs.lastModifiedDate ?? lhs.creationDate ?? .distantFuture
        let rhsUpdatedAt = rhs.lastModifiedDate ?? rhs.creationDate ?? .distantFuture

        if lhsUpdatedAt == rhsUpdatedAt {
            return (lhs.title ?? "未命名事项") < (rhs.title ?? "未命名事项")
        }
        return lhsUpdatedAt > rhsUpdatedAt
    }

    enum StoreError: LocalizedError {
        case reminderNotFound(String)
        case invalidDueDate
        case saveFailed(title: String, underlying: Error)
        case listUnavailable

        var errorDescription: String? {
            switch self {
            case .reminderNotFound(let id): return "找不到同步事项：\(id)"
            case .invalidDueDate: return "设备提交了无效的提醒时间"
            case .saveFailed(let title, let underlying):
                return "无法写回“\(title)”：\(underlying.localizedDescription)"
            case .listUnavailable: return "请选择要同步的提醒事项列表"
            }
        }
    }
}
