import EventKit
import Foundation

enum AutomaticSyncInterval: Int, CaseIterable, Identifiable {
    case thirtySeconds = 30
    case oneMinute = 60
    case tenMinutes = 600
    case thirtyMinutes = 1800
    case oneHour = 3600

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .thirtySeconds: return "30 秒"
        case .oneMinute: return "1 分钟"
        case .tenMinutes: return "10 分钟"
        case .thirtyMinutes: return "30 分钟"
        case .oneHour: return "1 小时"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var deviceURL: String {
        didSet { defaults.set(deviceURL, forKey: Keys.deviceURL) }
    }
    @Published var selectedCalendarId: String? {
        didSet { defaults.set(selectedCalendarId, forKey: Keys.calendarId) }
    }
    @Published private(set) var calendars: [(id: String, title: String)] = []
    @Published private(set) var reminders: [ReminderItem] = []
    @Published private(set) var activeView: DeviceReminderView = .today
    @Published private(set) var activeViewTotalCount = 0
    @Published private(set) var emptyState: ReminderEmptyState = .noItems
    @Published private(set) var statusText = "尚未同步"
    @Published private(set) var isSyncing = false
    @Published private(set) var displayWidth = ZectrixDisplayRenderer.width
    @Published private(set) var displayHeight = ZectrixDisplayRenderer.height
    @Published var automaticSync: Bool {
        didSet {
            defaults.set(automaticSync, forKey: Keys.automaticSync)
            configureAutomaticSyncTimer()
        }
    }
    @Published var automaticSyncInterval: AutomaticSyncInterval {
        didSet {
            defaults.set(automaticSyncInterval.rawValue, forKey: Keys.automaticSyncInterval)
            configureAutomaticSyncTimer()
        }
    }

    private let defaults: UserDefaults
    private let reminderStore: ReminderStore
    private var timer: Timer?
    private var deviceRequestTimer: Timer?
    private var changeObserver: NSObjectProtocol?
    private var reminderChangeSyncTask: Task<Void, Never>?
    private var reminderChangeSyncPending = false
    private var lastRenderedItems: [ReminderItem]?
    private var lastRenderProfile: String?
    private var lastRenderedEmptyState: ReminderEmptyState?
    private var cachedZectrixItems: [ReminderItem] = []
    private var cachedZectrixView: DeviceReminderView = .today
    private var cachedZectrixRevision: UInt64 = 0
    private var lastAlertSignatures: [String] = []
    private var isServingDisplayRequest = false

    init(
        previewReminders: [ReminderItem] = [],
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        let identities = SyncIdentityStore()
        reminderStore = ReminderStore(identities: identities)
        deviceURL = defaults.string(forKey: Keys.deviceURL) ?? "http://192.168.1.42"
        selectedCalendarId = defaults.string(forKey: Keys.calendarId)
        automaticSync = defaults.object(forKey: Keys.automaticSync) as? Bool ?? true
        automaticSyncInterval = AutomaticSyncInterval(
            rawValue: defaults.integer(forKey: Keys.automaticSyncInterval)
        ) ?? .thirtySeconds
        reminders = previewReminders
        activeViewTotalCount = previewReminders.count

        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleReminderChangeSync()
            }
        }
        configureAutomaticSyncTimer()
    }

    deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
        reminderChangeSyncTask?.cancel()
        timer?.invalidate()
        deviceRequestTimer?.invalidate()
    }

    private func configureAutomaticSyncTimer() {
        timer?.invalidate()
        deviceRequestTimer?.invalidate()
        timer = nil
        deviceRequestTimer = nil
        if automaticSync {
            timer = Timer.scheduledTimer(
                withTimeInterval: TimeInterval(automaticSyncInterval.rawValue),
                repeats: true
            ) { [weak self] _ in
                Task { @MainActor in
                    guard self?.automaticSync == true else { return }
                    await self?.sync()
                }
            }
        } else {
            reminderChangeSyncTask?.cancel()
            reminderChangeSyncTask = nil
            reminderChangeSyncPending = false
        }
        // A one-second device poll is still effectively immediate for button
        // interactions, while cutting idle Wi-Fi traffic to one quarter of the
        // previous rate so NOTE4 can spend time in modem sleep.
        deviceRequestTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.pollForDeviceSyncRequest() }
        }
    }

    private func scheduleReminderChangeSync() {
        guard automaticSync else { return }
        reminderChangeSyncPending = true
        reminderChangeSyncTask?.cancel()
        reminderChangeSyncTask = Task { [weak self] in
            // EventKit often emits several notifications for one edit. A very
            // short debounce lets the store settle without making the user
            // wait for the periodic fallback timer.
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
            } catch {
                return
            }
            await self?.flushReminderChangeSync()
        }
    }

    private func flushReminderChangeSync() async {
        while automaticSync, reminderChangeSyncPending, !Task.isCancelled {
            // Never drop a change that arrives while another device request or
            // synchronization is active. Wait briefly, then run a fresh fetch.
            if isSyncing || isServingDisplayRequest {
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                } catch {
                    return
                }
                continue
            }
            reminderChangeSyncPending = false
            statusText = "检测到提醒事项变化，正在同步…"
            await sync(force: true)
        }
    }

    private func pollForDeviceSyncRequest() async {
        guard !isSyncing, !isServingDisplayRequest, let baseURL = normalizedURL else { return }
        do {
            let client = DeviceClient(baseURL: baseURL)
            let deviceStatus = try await client.status()
            if deviceStatus.displayRequested == true,
               deviceStatus.view == cachedZectrixView,
               deviceStatus.revision == cachedZectrixRevision,
               !cachedZectrixItems.isEmpty {
                isServingDisplayRequest = true
                defer { isServingDisplayRequest = false }
                let operations = try await client.operations(after: 0)
                try await sendZectrixInteractionFrames(
                    client: client,
                    items: cachedZectrixItems,
                    selectedOriginalIndex: deviceStatus.selectedIndex ?? 0,
                    queuedCompletionIDs: Set(Self.completedOnDeviceIDs(from: operations))
                )
                return
            }
            if automaticSync,
               deviceStatus.syncRequested == true,
               deviceStatus.syncRequestAgeMs.map({ $0 >= 5_000 }) ?? true {
                await sync()
            }
        } catch {
            // The full scheduled/manual sync remains responsible for showing
            // connection errors; silent polling must not overwrite UI status.
        }
    }

    func prepare() async {
        do {
            guard try await reminderStore.requestAccess() else {
                statusText = "未获得提醒事项权限"
                return
            }
            calendars = reminderStore.calendars.map { ($0.calendarIdentifier, $0.title) }
            if selectedCalendarId == nil { selectedCalendarId = calendars.first?.id }
            await sync()
        } catch {
            statusText = error.localizedDescription
        }
    }

    func sync(force: Bool = false) async {
        guard !isSyncing, !isServingDisplayRequest else { return }
        guard let baseURL = normalizedURL else {
            statusText = "设备地址无效"
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let client = DeviceClient(baseURL: baseURL)
            let deviceStatus = try await client.status()
            if !force,
               deviceStatus.syncRequested == true,
               let age = deviceStatus.syncRequestAgeMs,
               age < 5_000 {
                return
            }
            displayWidth = deviceStatus.width
            displayHeight = deviceStatus.height
            guard deviceStatus.width == ZectrixDisplayRenderer.width,
                  deviceStatus.height == ZectrixDisplayRenderer.height else {
                statusText = "同步失败：当前版本仅支持 ZECTRIX NOTE4 黑白版（400 × 300）"
                return
            }
            activeView = deviceStatus.view ?? .today
            let renderProfile = "zectrix-note4-\(deviceStatus.firmwareVersion ?? "unknown")-\(activeView.rawValue)"
            // The device's durable queue is the source of truth. Always read
            // every unacknowledged operation: firmware reinstall/reset can
            // restart its sequence at 1 while the device MAC stays unchanged.
            // Completion writes are idempotent and successful operations are
            // removed only by the ACK below.
            let operations = try await client.operations(after: 0)
            let sortedOperations = operations.sorted(by: { $0.sequence < $1.sequence })
            for operation in sortedOperations {
                try reminderStore.apply(operation, calendarIdentifier: selectedCalendarId)
            }

            let viewSnapshot = try await reminderStore.fetchView(
                activeView,
                calendarIdentifier: selectedCalendarId,
                includeAlertCandidates: true
            )
            activeViewTotalCount = viewSnapshot.totalCount
            emptyState = viewSnapshot.emptyState
            reminders = viewSnapshot.items
            let needsRefresh = lastRenderedItems != reminders ||
                lastRenderProfile != renderProfile ||
                lastRenderedEmptyState != emptyState ||
                Self.requiresFrameRebuild(deviceRevision: deviceStatus.revision)
            let revision = UInt64(Date().timeIntervalSince1970 * 1_000)
            let now = Date()
            let alertItems = Self.pendingAlerts(from: viewSnapshot.alertCandidates, now: now)
            let alertSignatures = alertItems.map { "\($0.syncId)|\(Int64(($0.dueAt?.timeIntervalSince1970 ?? 0) * 1_000))|\($0.title)" }
            let alertsChanged = alertSignatures != lastAlertSignatures
            let shouldSendSnapshot = needsRefresh || alertsChanged || deviceStatus.syncRequested == true || !operations.isEmpty
            if shouldSendSnapshot {
                let alerts: [DeviceAlert]? = try alertItems.map { item in
                    DeviceAlert(
                        syncId: item.syncId, appleId: item.appleId,
                        dueAtEpochMs: Int64(item.dueAt!.timeIntervalSince1970 * 1_000),
                        bitmap: try ZectrixDisplayRenderer.renderAlertPatch(title: item.title).base64EncodedString()
                    )
                }
                try await client.send(snapshot: DeviceSnapshot(
                    revision: revision,
                    reminders: reminders,
                    viewCounts: nil,
                    currentViewCount: viewSnapshot.items.count,
                    replaceDisplay: needsRefresh,
                    sentAtEpochMs: Int64(Date().timeIntervalSince1970 * 1_000),
                    alerts: alerts
                ))
                cachedZectrixItems = reminders
                cachedZectrixView = activeView
                cachedZectrixRevision = revision
                lastAlertSignatures = alertSignatures
            }
            if needsRefresh {
                let selectableCount = activeView == .completed
                    ? reminders.count
                    : reminders.lazy.filter { !$0.completed }.count
                try await client.send(
                    display: try ZectrixDisplayRenderer.render(
                        reminders,
                        selectedIndex: nil,
                        view: activeView,
                        emptyState: emptyState
                    ),
                    index: 0,
                    state: .idle
                )
                if selectableCount > 0 {
                    try await sendZectrixInteractionFrames(
                        client: client,
                        items: reminders,
                        selectedOriginalIndex: 0,
                        queuedCompletionIDs: []
                    )
                }
                lastRenderedItems = reminders
                lastRenderProfile = renderProfile
                lastRenderedEmptyState = emptyState
            }
            // The operation is acknowledged only after EventKit, the snapshot,
            // and every required display frame have all succeeded. Replaying a
            // completion after a transient failure is safe and idempotent.
            if let last = operations.map(\.sequence).max() {
                try await client.acknowledge(through: last)
            }
            if deviceStatus.syncRequested == true {
                try await client.acknowledgeSyncRequest()
            }
            statusText = "已同步“\(activeView.title)”视图 \(viewSnapshot.totalCount) 项\(needsRefresh ? "并刷新屏幕" : "") · \(Self.clock.string(from: Date()))"
        } catch {
            statusText = "同步失败：\(error.localizedDescription)"
        }
    }

    private func sendZectrixInteractionFrames(
        client: DeviceClient,
        items: [ReminderItem],
        selectedOriginalIndex: Int,
        queuedCompletionIDs: Set<String>
    ) async throws {
        let currentItems = Self.itemsMarkingCompleted(items, syncIds: queuedCompletionIDs)
        let selectedIndex = Self.renderSelectionIndex(
            originalIndex: selectedOriginalIndex,
            items: currentItems,
            view: activeView
        )
        try await client.send(
            display: try ZectrixDisplayRenderer.render(
                currentItems,
                selectedIndex: selectedIndex,
                view: activeView
            ),
            index: selectedOriginalIndex,
            state: .normal
        )

        guard activeView != .completed,
              currentItems.indices.contains(selectedOriginalIndex),
              !currentItems[selectedOriginalIndex].completed else { return }
        var predictedIDs = queuedCompletionIDs
        predictedIDs.insert(currentItems[selectedOriginalIndex].syncId)
        let predictedItems = Self.itemsMarkingCompleted(items, syncIds: predictedIDs)
        let nextOriginalIndex = Self.nextAvailableOriginalIndex(
            after: selectedOriginalIndex,
            items: predictedItems
        ) ?? selectedOriginalIndex
        let nextSelectedIndex = Self.renderSelectionIndex(
            originalIndex: nextOriginalIndex,
            items: predictedItems,
            view: activeView
        )
        try await client.send(
            display: try ZectrixDisplayRenderer.render(
                predictedItems,
                selectedIndex: nextSelectedIndex,
                view: activeView
            ),
            index: selectedOriginalIndex,
            state: .confirmation
        )
    }

    private var normalizedURL: URL? {
        var value = deviceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains("://") { value = "http://" + value }
        return URL(string: value)
    }

    private static let clock: DateFormatter = {
        let value = DateFormatter()
        value.dateFormat = "HH:mm:ss"
        return value
    }()

    static func completedOnDeviceIDs(from operations: [DeviceOperation]) -> [String] {
        operations.compactMap { operation in
            operation.type == .setCompleted && operation.completed != false ? operation.syncId : nil
        }
    }

    static func pendingAlerts(from items: [ReminderItem], now: Date) -> [ReminderItem] {
        items.filter { item in
            !item.completed && item.hasDueTime &&
                (item.dueAt.map { $0 >= now.addingTimeInterval(-30) } ?? false)
        }.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            .prefix(32).map { $0 }
    }

    static func requiresFrameRebuild(deviceRevision: UInt64) -> Bool {
        // The NOTE4 marks its revision as zero after a local cache clear or
        // when its idle frame is missing. Re-upload the image even if EventKit
        // returns exactly the same reminders as last time.
        deviceRevision == 0
    }

    static func itemsMarkingCompleted(
        _ reminders: [ReminderItem],
        syncIds: Set<String>
    ) -> [ReminderItem] {
        reminders.map { item in
            guard syncIds.contains(item.syncId) else { return item }
            var completed = item
            completed.completed = true
            return completed
        }
    }

    static func renderSelectionIndex(
        originalIndex: Int,
        items: [ReminderItem],
        view: DeviceReminderView
    ) -> Int? {
        guard items.indices.contains(originalIndex) else { return nil }
        if view == .completed { return originalIndex }
        let selectedID = items[originalIndex].syncId
        return items.filter { !$0.completed }.firstIndex { $0.syncId == selectedID }
    }

    static func nextAvailableOriginalIndex(
        after originalIndex: Int,
        items: [ReminderItem]
    ) -> Int? {
        guard !items.isEmpty else { return nil }
        for offset in 1...items.count {
            let candidate = (originalIndex + offset) % items.count
            if !items[candidate].completed { return candidate }
        }
        return nil
    }

    private enum Keys {
        static let deviceURL = "deviceURL"
        static let calendarId = "calendarId"
        static let automaticSync = "automaticSync"
        static let automaticSyncInterval = "automaticSyncInterval"
    }
}
