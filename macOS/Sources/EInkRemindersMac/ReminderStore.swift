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

    func fetchIncomplete(calendarIdentifier: String?) async throws -> [ReminderItem] {
        let selected = selectedCalendar(calendarIdentifier)
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: selected.map { [$0] }
        )
        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
        return reminders.map(toItem).sorted(by: ReminderStore.displayOrder)
    }

    func fetchView(
        _ view: DeviceReminderView,
        calendarIdentifier: String?,
        includeAlertCandidates: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> ReminderViewSnapshot {
        let allItems: [ReminderItem]
        var alertCandidates: [ReminderItem] = []
        switch view {
        case .completed:
            allItems = try await fetchCompleted(calendarIdentifier: calendarIdentifier)
            if includeAlertCandidates {
                alertCandidates = try await fetchIncomplete(calendarIdentifier: calendarIdentifier)
            }
        case .today, .scheduled, .all:
            let incomplete = try await fetchIncomplete(calendarIdentifier: calendarIdentifier)
            if includeAlertCandidates { alertCandidates = incomplete }
            switch view {
            case .today:
                allItems = incomplete.filter { Self.belongsToToday($0, now: now, calendar: calendar) }
            case .scheduled:
                allItems = incomplete.filter { $0.dueAt != nil }
            case .all:
                allItems = incomplete
            case .completed:
                allItems = []
            }
        }
        // Today, Scheduled and Completed are intentionally bounded so the
        // device remains quick even when the Apple list is very large. The All
        // view has no application-level item cap and is served on demand.
        let items = view == .all ? allItems : Array(allItems.prefix(20))
        // An empty Today view may mean its work was finished. Check completed
        // reminders only in this case; every other empty smart view uses the
        // ordinary message and needs no extra EventKit query.
        let hasCompletedTodayItems: Bool
        if allItems.isEmpty && view == .today {
            hasCompletedTodayItems = await hasCompletedTodayReminders(
                calendarIdentifier: calendarIdentifier, now: now, calendar: calendar
            )
        } else {
            hasCompletedTodayItems = false
        }
        let emptyState = ReminderEmptyState.resolve(
            view: view,
            visibleCount: allItems.count,
            hasCompletedTodayItems: hasCompletedTodayItems
        )
        return ReminderViewSnapshot(
            items: items, totalCount: allItems.count,
            emptyState: emptyState, alertCandidates: alertCandidates
        )
    }

    func completedItems(withSyncIds syncIds: [String]) -> [ReminderItem] {
        syncIds.compactMap { syncId in
            guard let appleId = identities.appleId(for: syncId),
                  let reminder = eventStore.calendarItem(withIdentifier: appleId) as? EKReminder,
                  reminder.isCompleted else { return nil }
            return toItem(reminder)
        }
    }

    func create(
        title: String,
        dueAt: Date,
        hasDueTime: Bool,
        calendarIdentifier: String?
    ) throws {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw StoreError.emptyTitle }
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = value
        reminder.calendar = calendarIdentifier.flatMap { id in
            calendars.first { $0.calendarIdentifier == id }
        } ?? eventStore.defaultCalendarForNewReminders()
        let fields: Set<Calendar.Component> = hasDueTime
            ? [.year, .month, .day, .hour, .minute]
            : [.year, .month, .day]
        reminder.dueDateComponents = Calendar.current.dateComponents(fields, from: dueAt)
        try eventStore.save(reminder, commit: true)
    }

    func apply(_ operation: DeviceOperation, calendarIdentifier: String?) throws {
        switch operation.type {
        case .create:
            guard let title = operation.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                throw StoreError.emptyTitle
            }
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = title
            reminder.notes = operation.notes
            reminder.calendar = calendarIdentifier.flatMap { id in calendars.first { $0.calendarIdentifier == id } }
                ?? eventStore.defaultCalendarForNewReminders()
            if let dueAt = operation.dueAt {
                reminder.dueDateComponents = Calendar.current.dateComponents(in: .current, from: dueAt)
            }
            try eventStore.save(reminder, commit: true)
            identities.bind(syncId: operation.syncId, to: reminder.calendarItemIdentifier)

        case .setCompleted:
            guard let appleId = operation.appleId ?? identities.appleId(for: operation.syncId),
                  let reminder = eventStore.calendarItem(withIdentifier: appleId) as? EKReminder else {
                throw StoreError.reminderNotFound(operation.syncId)
            }
            identities.bind(syncId: operation.syncId, to: appleId)
            reminder.isCompleted = operation.completed ?? true
            reminder.completionDate = reminder.isCompleted ? Date() : nil
            try eventStore.save(reminder, commit: true)

        case .setDueAt:
            guard let appleId = operation.appleId ?? identities.appleId(for: operation.syncId),
                  let reminder = eventStore.calendarItem(withIdentifier: appleId) as? EKReminder else {
                throw StoreError.reminderNotFound(operation.syncId)
            }
            guard let dueAtEpochMs = operation.dueAtEpochMs, dueAtEpochMs > 0 else {
                throw StoreError.invalidDueDate
            }
            identities.bind(syncId: operation.syncId, to: appleId)
            let date = Date(timeIntervalSince1970: TimeInterval(dueAtEpochMs) / 1_000)
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: date
            )
            try eventStore.save(reminder, commit: true)
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

    private func fetchCompleted(calendarIdentifier: String?) async throws -> [ReminderItem] {
        let selected = selectedCalendar(calendarIdentifier)
        let predicate = eventStore.predicateForCompletedReminders(
            withCompletionDateStarting: nil,
            ending: nil,
            calendars: selected.map { [$0] }
        )
        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
        return reminders.map(toItem).sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt { return lhs.title < rhs.title }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func hasCompletedTodayReminders(
        calendarIdentifier: String?, now: Date, calendar: Calendar
    ) async -> Bool {
        let selected = selectedCalendar(calendarIdentifier)
        let predicate = eventStore.predicateForCompletedReminders(
            withCompletionDateStarting: nil,
            ending: nil,
            calendars: selected.map { [$0] }
        )
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) {
                let found = ($0 ?? []).contains { reminder in
                    guard let completedAt = reminder.completionDate,
                          calendar.isDate(completedAt, inSameDayAs: now) else { return false }
                    return Self.belongsToToday(self.toItem(reminder), now: now, calendar: calendar)
                }
                continuation.resume(returning: found)
            }
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

    private static func displayOrder(_ lhs: ReminderItem, _ rhs: ReminderItem) -> Bool {
        switch (lhs.dueAt, rhs.dueAt) {
        case let (l?, r?): return l == r ? lhs.title < rhs.title : l < r
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return lhs.title.localizedCompare(rhs.title) == .orderedAscending
        }
    }

    enum StoreError: LocalizedError {
        case emptyTitle
        case reminderNotFound(String)
        case invalidDueDate

        var errorDescription: String? {
            switch self {
            case .emptyTitle: return "设备提交了空标题"
            case .reminderNotFound(let id): return "找不到同步事项：\(id)"
            case .invalidDueDate: return "设备提交了无效的提醒时间"
            }
        }
    }
}
